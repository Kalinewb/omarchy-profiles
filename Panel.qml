import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
// For ToplevelManager alone: the window set is what the session recorder is
// debounced off, and there is no other way to be told a window opened without
// polling the compositor.
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Profiles: which whole-machine look is active, and a picker to change it.
//
// This file is only the face. Every decision lives in bin/omarchy-profile,
// which the rows shell out to — so switching still works from a terminal or a
// keybind while the shell is reloading, and the panel never has to know how a
// theme or a bar preset gets applied.
//
// The current profile is read from the engine's state file rather than tracked
// here. That is deliberate: the state file is the single answer to "which
// profile am I in", shared by the widget, the script and anything else that
// asks. It lives under ~/.local/state and NOT inside this plugin directory,
// because ~/.config/omarchy/plugins is watched recursively — a write in here
// would tear down every panel, service and bar widget in the shell, including
// this popup, on every single switch.
Panel {
  id: root
  moduleName: "graveklar.profiles"
  ipcTarget: "graveklar.profiles"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/omarchy-profiles/current.json"
  readonly property string engine: home + "/.config/omarchy/plugins/graveklar.profiles/bin/omarchy-profile"

  readonly property string indexPath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/omarchy-profiles/profiles.json"

  // Read from the engine's index, never hardcoded: profiles are created and
  // removed at runtime, and a baked-in list shows names that no longer exist
  // while hiding the ones that do.
  property var profiles: []

  function parseIndex(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      if (!Array.isArray(parsed)) return
      var out = []
      for (var i = 0; i < parsed.length; i++) {
        var p = parsed[i]
        if (!p) continue
        out.push({
          id: String(p.name || ""),
          label: String(p.name || "").replace(/^./, function (c) { return c.toUpperCase() }),
          icon: String(p.icon || "") || (p.master ? "\u{f0493}" : "\u{f01bc}"),
          blurb: String(p.description || ""),
          master: !!p.master,
          hidden: !!p.hidden,
          locked: !!p.locked,
          // From the engine's root store, not from the profile's own JSON:
          // this is the fact a settings edit must not be able to change.
          hasPassword: !!p.hasPassword,
          identity: String(p.identity || "")
        })
        if (p.master) root.masterName = String(p.name || "")
      }
      root.profiles = out
    } catch (e) {
      console.warn("graveklar.profiles", "Ignoring bad profile index", root.indexPath, e)
    }
  }

  property string currentProfile: ""
  property bool cursorActive: false
  property int cursor: 0

  // "picker" switches profiles; "manage" creates, removes and hides them.
  // One panel with two views rather than two plugins, because they are the same
  // list seen two ways and a second bar icon would be clutter.
  //
  // A stack rather than a flat string: every view is reached from somewhere, and
  // "back" means the place it was opened from. The hand-rolled chain this
  // replaces had to name each return path, so a view reachable from two places
  // could only go back to one of them.
  property var viewStack: ["picker"]
  readonly property string view: viewStack[viewStack.length - 1]

  // Moving between views resets the cursor: the lists are different lengths, so
  // a carried-over index can point past the end of the one now on screen.
  function pushView(v) { viewStack = viewStack.concat([v]); cursor = 0; cursorActive = false }
  function popView() { if (viewStack.length > 1) viewStack = viewStack.slice(0, -1); cursor = 0 }
  function resetView(v) { viewStack = [v] }

  property string masterName: ""

  // Which profile a remove confirmation is about. Empty means no dialog.
  // Owned here, not by the manage view: a ConfirmDialog needs anchors, and a
  // Column child may not have them.
  property string pendingRemoval: ""

  // Which profile the settings view is editing.
  property string settingsProfile: ""
  // Which profile the edit form is renaming or relabelling, and what the engine
  // said about the last save.
  property string editProfile: ""
  property string metaError: ""
  // What `capture` last answered. Cleared by its own timer: it is a receipt,
  // not a state.
  property string captureNote: ""
  property bool captureFailed: false
  property var pluginCatalog: []
  property var overviewRows: []
  property string pendingClose: ""

  readonly property string overviewPath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/omarchy-profiles/overview.json"
  property var settingsDisabled: []
  property var settingsAllowedApps: []
  // Every application the edited profile could be allowed, from the engine's
  // enumerator. Not read from DesktopEntries any more: an application a profile
  // hides is a NoDisplay entry while that profile is active, and the list that
  // switches it back on is exactly the list it would drop out of.
  property var settingsAllApps: []

  // ------------------------------------------------------------ config view
  //
  // Which profile the config page is describing, and the four answers it needs.
  // Everything below the first group is machine-wide, so only configData is
  // per-profile; the rest is asked once and is the same on every page.
  property string configProfile: ""
  property var configData: null
  property var isolateRows: []
  property var isolateCandidates: []
  property var globalStatus: null
  // The engine's own refusal, rendered inline under the custom-path field.
  property string configError: ""
  property var resolvePreview: null
  // ok | unknown | broken, from `capabilities`. Never assumed: the toggles it
  // gates are the ones that can take the desktop with them.
  property string hyprReload: "unknown"
  // Tier-3 rollbacks, keyed by profile. An absent file and {} mean the same
  // thing: nothing outstanding.
  property var hyprErrors: ({})

  function openConfig(profile) {
    root.configProfile = profile
    root.configError = ""
    root.resolvePreview = null
    root.pushView("config")
    root.loadConfig()
  }

  function loadConfig() {
    if (root.configProfile === "") return
    root.loadConfigSession()
    root.ask(["config", root.configProfile, "--json"], "", function (ok, parsed) {
      if (ok && parsed && !parsed.error) root.configData = parsed
    })
    root.ask(["isolate", "list", "--json"], "", function (ok, parsed) {
      root.isolateRows = (ok && Array.isArray(parsed)) ? parsed : []
    })
    root.ask(["isolate", "candidates", "--json"], "", function (ok, parsed) {
      root.isolateCandidates = (ok && Array.isArray(parsed)) ? parsed : []
    })
    root.ask(["global", "status", "--json"], "", function (ok, parsed) {
      root.globalStatus = (ok && parsed && !parsed.error) ? parsed : null
    })
    root.ask(["capabilities", "--json"], "", function (ok, parsed) {
      root.hyprReload = (ok && parsed && parsed.hyprland_reload)
        ? String(parsed.hyprland_reload) : "unknown"
    })
  }

  // Isolating moves real files between stores, so its answer matters: the
  // engine refuses a blocklisted path, and that refusal is the only thing the
  // user can act on.
  function isolateAdd(path, plugin, reload) {
    root.configError = ""
    var args = ["isolate", "add", path, "--json"]
    if (plugin && plugin !== "") args = args.concat(["--plugin", plugin])
    if (reload && reload !== "") args = args.concat(["--reload", reload])
    root.ask(args, "", function (ok, parsed) {
      if (!ok) {
        var err = parsed && parsed.error ? String(parsed.error) : "failed"
        root.configError = err === "blocklisted"
          ? String(parsed.reason || "that file cannot be isolated")
          : err === "busy" ? "A switch is running — try again in a moment"
          : err === "held_paths" || err === "interrupted_switch"
            ? "Switching is blocked until Setup repairs it"
            : "Could not isolate that path"
        return
      }
      root.loadConfig()
    })
  }

  function isolateRemove(path) {
    root.configError = ""
    root.ask(["isolate", "remove", path, "--json"], "", function (ok, parsed) {
      if (!ok) {
        root.configError = "Could not stop isolating that path"
        return
      }
      root.loadConfig()
    })
  }

  function resolveCustom(path) {
    if (path === "") { root.resolvePreview = null; return }
    root.ask(["isolate", "resolve", path, "--json"], "", function (ok, parsed) {
      root.resolvePreview = (parsed && !parsed.error) ? parsed : null
    })
  }

  function runGlobal(args) {
    root.configError = ""
    root.ask(["global"].concat(String(args).split(" ").filter(function (a) { return a !== "" })),
             "", function (ok, parsed) {
      if (!ok) root.configError = "Could not change the global workspace"
      root.loadConfig()
    })
  }

  // Which profile a password is being asked for, and what about. The idle timer
  // watches passwordFor too: a question on screen must never be timed out
  // without somebody deciding anything.
  property string passwordFor: ""
  // "enter" | "set" | "change" | "reset" | "clear" | "rename" | "remove"
  property string passwordMode: ""
  property string passwordError: ""
  // Seconds; while it is above zero the field is read-only and counting down.
  property int passwordRetryIn: 0
  property bool faceTrying: false
  // The pending empty-stdin `set` that is trying a bound face, kept so it can
  // be terminated the moment something is typed.
  property var faceProc: null
  // The second argument of a two-name verb — today only `rename`.
  property string passwordArg: ""
  // Whether a face can be tried at all. Asked once per open; `absent` means the
  // face plugin is not installed and there is nothing to try.
  //
  // The state string itself, not a boolean, because the Manage view renders
  // three different things from it: the face row (only on `ok`), the dim
  // "face plugin not installed" caption on a profile that still names an
  // identity, and nothing at all.
  property string faceState: "unknown"
  readonly property bool faceInstalled: root.faceState === "ok"
  // Enrolled faces, from `identity list --json`. Only asked for when the plugin
  // is there: on a machine without it the answer is always the empty list.
  property var identityNames: []
  // What the last bind or clear said, rendered under the face row.
  property string faceError: ""
  property string createError: ""
  property string pendingSetup: ""

  // What Setup says, as the engine says it.
  //
  // null is "not asked yet" and is never healthy: an unanswered question and a
  // healthy machine must not look the same. setupOutcome tells the view which
  // of the three it is — pending, answered, or the engine could not answer.
  property var setupRows: null
  property string setupOutcome: ""
  property string setupError: ""
  property int setupElapsed: 0

  function loadSetup(gate) {
    root.ask(["setup", "status", "--json"], "", function (ok, parsed, code) {
      if (ok && Array.isArray(parsed)) {
        root.setupRows = parsed
        root.setupOutcome = "ok"
      } else {
        root.setupRows = []
        root.setupOutcome = (parsed && parsed.error) ? String(parsed.error) : ("exit " + code)
      }
      if (gate) root.applySetupGate()
    })
  }

  function setupRow(id) {
    if (!root.setupRows) return null
    for (var i = 0; i < root.setupRows.length; i++)
      if (root.setupRows[i] && root.setupRows[i].id === id) return root.setupRows[i]
    return null
  }

  function rowNeedsWork(row) {
    return !!row && (row.state === "needs_action" || row.state === "broken")
  }

  // Two rows are not "something to look at later": without adoption there is no
  // profile to switch to, and with a switch half done nothing may be captured.
  // Everything else badges the hero and lets the user carry on.
  readonly property var blockingRows: ["adopt", "switch"]

  function setupBlocking() {
    if (!root.setupRows) return false
    for (var i = 0; i < root.blockingRows.length; i++)
      if (root.rowNeedsWork(root.setupRow(root.blockingRows[i]))) return true
    return false
  }

  readonly property int setupBadge: {
    if (!setupRows) return 0
    var n = 0
    for (var i = 0; i < setupRows.length; i++) {
      var s = setupRows[i] ? String(setupRows[i].state) : ""
      if (s !== "ok" && s !== "absent") n++
    }
    return n
  }

  function applySetupGate() {
    if (root.setupBlocking() || root.switchStalled) root.resetView("setup")
  }

  function runFix(id) {
    root.pendingSetup = id
    root.setupError = ""
    root.setupElapsed = 0
    root.ask(["setup", "fix", id], "", function (ok, parsed, code) {
      root.pendingSetup = ""
      if (!ok) {
        var err = parsed && parsed.error ? String(parsed.error) : ("exit " + code)
        root.setupError = err === "busy" ? "Busy — try again when the switch finishes"
                        : "That did not work (" + err + ")"
      }
      // A fix changes what every other row can see, so the whole set is asked
      // again rather than the one row patched in place.
      root.loadSetup(false)
    })
  }

  // Set when a switch was authorised and then never arrived. The engine is the
  // only thing that can say why, so the panel's job is to stop pretending it is
  // still switching and to send the user where the answer is.
  property bool switchStalled: false

  readonly property string catalogPath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/omarchy-profiles/plugins.json"

  // The auto-close exists for one case only: a misclick on the bar icon, which
  // should not leave a panel sitting open.
  //
  // It used to restart on interaction instead, which closed the panel while it
  // was being read — scrolling a sixty-row plugin list and hovering rows are
  // not things that were calling keepAlive, so eight seconds of reading looked
  // exactly like eight seconds of absence. Tracking every kind of interaction
  // is the wrong fix; the question is not "have you touched it recently" but
  // "did you mean to open it at all".
  //
  // So the timer is armed on open and cancelled for good by the first
  // interaction of any kind. After that the panel stays until it is closed.
  readonly property int idleCloseMs: 12000
  property bool touchedSinceOpen: false
  function keepAlive() {
    root.touchedSinceOpen = true
    idleClose.stop()
  }

  // The switcher's list. Hidden profiles are still in `profiles` so the manage
  // view can unhide them; only this derived list drops them.
  readonly property var visibleProfiles: {
    var out = []
    for (var i = 0; i < profiles.length; i++) if (!profiles[i].hidden) out.push(profiles[i])
    return out
  }

  // Fire-and-forget: every mutation goes through the engine and comes back as a
  // changed index file, so the UI never holds a second copy of the truth.
  function runEngine(args) {
    if (!root.bar || typeof root.bar.run !== "function") {
      console.warn("graveklar.profiles", "No bar facade to run the engine through")
      return
    }
    root.bar.run(root.engine + " " + args)
  }
  // Set while the engine runs so a row can show it was the one picked; the
  // state file arriving is what actually clears it.
  property string applying: ""

  // Ask the engine and get the answer back, rather than watching a file for a
  // side effect. "That password was wrong" needs an exit code, and bar.run() is
  // execDetached: no stdout, no status, nothing to wait on. runEngine stays for
  // the mutations whose result IS a watched file (hide, show, plugin enable,
  // catalog, overview).
  //
  // Through `bash -c 'exec "$@"' -- <engine> <args>`. The exec matters: without
  // it the wrapper shell stays alive as the parent, and a TERM sent to cancel a
  // face attempt would kill the wrapper while the engine kept running. Bash
  // still exits 126/127 itself when exec fails, so a missing engine fires
  // onExited instead of leaving the panel waiting forever.
  //
  // args is an argv array, never a joined string: a profile named "old work"
  // has to arrive as one argument, and a password never goes near argv at all.
  //
  // callback(ok, parsed, code):
  //   exit 0        ok = true, parsed = the JSON if stdout parsed, else null.
  //                 Prose-only verbs succeed with parsed === null.
  //   anything else ok = false, parsed = the engine's {"error": …} if it printed
  //                 one, else {error: "failed", code}. Code 2 is an auth
  //                 refusal and 3 is busy (plan-merged.md §2 rule 3).
  // Returns the Process it started, so a caller can signal it — which is how a
  // face attempt is cancelled the instant a password is typed. A call that had
  // to queue returns null: nothing has started yet, so there is nothing to
  // signal.
  function ask(args, stdinText, callback) {
    var job = { args: args || [], stdin: String(stdinText || ""), callback: callback || null }
    for (var i = 0; i < root.askPool.length; i++) {
      if (!root.askPool[i].busy) { root.startAsk(root.askPool[i], job); return root.askPool[i] }
    }
    // Four at once is more than the panel ever needs; a fifth waits rather than
    // letting a stuck engine call spawn processes without bound.
    root.askQueue = root.askQueue.concat([job])
    return null
  }

  property var askQueue: []

  function startAsk(proc, job) {
    proc.busy = true
    proc.job = job
    proc.collected = ""
    proc.stdinText = job.stdin
    proc.stdinEnabled = true
    proc.command = ["bash", "-c", "exec \"$@\"", "--", root.engine].concat(job.args)
    proc.running = true
  }

  function askFinished(proc, code) {
    var job = proc.job
    var out = String(proc.collected || "")
    proc.busy = false
    proc.job = null

    var parsed = null
    if (out.trim() !== "") {
      try { parsed = JSON.parse(out) } catch (e) { parsed = null }
    }
    var ok = code === 0
    if (!ok && (!parsed || typeof parsed !== "object" || parsed.error === undefined))
      parsed = { error: "failed", code: code }

    // The slot is handed on before the callback runs: a callback that throws
    // must not strand whatever was queued behind it.
    if (root.askQueue.length > 0) {
      var next = root.askQueue[0]
      root.askQueue = root.askQueue.slice(1)
      root.startAsk(proc, next)
    }
    if (job && job.callback) job.callback(ok, parsed, code)
  }

  function indexOf(id) {
    for (var i = 0; i < profiles.length; i++) if (profiles[i].id === id) return i
    return -1
  }

  function visibleIndexOf(id) {
    for (var i = 0; i < visibleProfiles.length; i++) if (visibleProfiles[i].id === id) return i
    return -1
  }

  function entry(id) {
    var i = indexOf(id)
    return i >= 0 ? profiles[i] : null
  }

  function label(id) {
    var e = entry(id)
    return e ? e.label : (id === "" ? "Profile" : id)
  }

  function icon(id) {
    var e = entry(id)
    return e ? e.icon : "󰒓"
  }

  function tooltip() {
    if (applying !== "") return "Switching to " + label(applying) + "…"
    if (switchStalled) return "The switch did not finish — open Setup"
    if (setupBlocking()) return "Profiles — setup needed"
    if (currentProfile === "") return "Machine profile: not set"
    return "Machine profile: " + label(currentProfile)
  }

  // Switching is two things, and only the first of them can be answered here.
  //
  // Stage 1 is an authentication verdict: exit 0 means the engine was allowed
  // to switch and is now doing it in a detached process that will restart this
  // shell. Nothing below waits for the switch to finish, because this QML will
  // not exist when it does — current.json arriving and applyTimeout expiring
  // are the only two signals there are.
  function apply(id) {
    var e = root.entry(id)
    if (e && (e.hasPassword || e.locked)) { root.beginUnlock(id); return }
    root.startSwitch(id, "")
  }

  // Bumped by every attempt, so a verdict for an attempt that has been
  // superseded is dropped rather than allowed to overwrite the newer one's
  // state. The password phase makes that ordinary: a face attempt and a typed
  // one can be in flight at once.
  property int switchSerial: 0

  function startSwitch(id, secret) {
    root.applying = id
    root.switchStalled = false
    root.switchError = ""
    var serial = ++root.switchSerial
    return root.ask(["set", id, "--json"], secret, function (ok, parsed, code) {
      // 143 is a face attempt this panel cancelled itself: empty stdout,
      // nothing written, no lock held. It is not an answer to anything.
      if (serial !== root.switchSerial || code === 143) return
      if (ok) {
        applyTimeout.restart()
        root.passwordFor = ""
        root.close()
        return
      }
      root.applying = ""
      root.handleAuthError(id, parsed, code)
    })
  }

  // Opening a protected profile.
  //
  // Three cases, and only one of them shows a field straight away:
  //
  //   locked with no password  there is nothing to type. Empty stdin makes the
  //                            engine raise the owner's prompt, which polkit
  //                            draws for itself.
  //   a bound face             worth trying silently first, but never at the
  //                            cost of making the user wait: the field appears
  //                            at once and the face attempt runs beside it.
  //   plain password           the field, with no round trip spent first.
  function beginUnlock(id) {
    root.passwordFor = id
    root.passwordMode = "enter"
    root.passwordError = ""
    root.passwordRetryIn = 0
    root.faceTrying = false
    root.faceProc = null
    var e = root.entry(id)
    if (!e) return
    if (e.locked && !e.hasPassword) { root.startSwitch(id, ""); return }
    if (e.identity !== "" && root.faceInstalled) {
      root.faceTrying = true
      root.faceProc = root.startSwitch(id, "")
    }
  }

  // A late face success would take the state lock and turn this typed password
  // into "busy" for a switch that is in fact happening. So the face attempt is
  // cancelled, not ignored, and not waited for: authentication happens before
  // the lock is taken, so a terminated attempt leaves nothing behind to undo.
  function submitPassword(id, text) {
    if (String(text || "") === "") return   // empty stdin means "no password supplied"
    if (root.faceProc) { root.faceProc.signal(15); root.faceProc = null }
    root.faceTrying = false
    root.passwordError = ""
    root.startSwitch(id, text)
  }

  // Managing a password, removing a profile, renaming one: everything whose
  // secret is collected by the prompt but which is not a switch.
  function submitManage(mode, id, secret) {
    var args = null
    if (mode === "set") args = ["password", "set", id, "--json"]
    else if (mode === "reset") args = ["password", "reset", id, "--json"]
    else if (mode === "change") args = ["password", "change", id, "--json"]
    else if (mode === "clear") args = ["password", "clear", id, "--json"]
    else if (mode === "remove") args = ["remove", id, "--json"]
    else if (mode === "rename") args = ["rename", id, root.passwordArg, "--json"]
    if (!args) return
    root.passwordError = ""
    root.ask(args, secret, function (ok, parsed, code) {
      if (ok) {
        // The edit form is looking at a profile that no longer has that name.
        // Following it here rather than closing the page keeps the icon and
        // description fields on what the user is editing.
        if (mode === "rename" && root.editProfile === id) root.editProfile = root.passwordArg
        root.passwordFor = ""
        root.passwordMode = ""
        root.passwordArg = ""
        root.passwordError = ""
        // Every one of these verbs rewrites the index itself; the watcher picks
        // it up. Setup is asked again because `locks` and `stale-hashes` are
        // about exactly what just changed.
        root.loadSetup(false)
        return
      }
      root.handleAuthError(id, parsed, code)
    })
  }

  // Open the prompt for something other than entering a profile.
  function beginManage(id, mode) {
    root.passwordFor = id
    root.passwordMode = mode
    root.passwordError = ""
    root.passwordRetryIn = 0
    root.faceTrying = false
    root.faceProc = null
  }

  // The edit form calls this; the prompt does the rest.
  function beginRename(id, to) {
    root.passwordArg = to
    var e = root.entry(id)
    if (e && (e.hasPassword || e.locked)) { root.beginManage(id, "rename"); return }
    root.submitManage("rename", id, "")
  }

  // ------------------------------------------------------------- the face
  //
  // Asked on every open rather than remembered: the face plugin can be
  // installed or removed between two openings of this panel, and a profile that
  // names an identity on a machine where it is gone must not offer to try one.
  function loadFaces() {
    root.faceError = ""
    root.ask(["capabilities", "--json"], "", function (ok, parsed) {
      root.faceState = (ok && parsed && parsed.face) ? String(parsed.face) : "unknown"
      if (!root.faceInstalled) { root.identityNames = []; return }
      root.ask(["identity", "list", "--json"], "", function (ok2, parsed2) {
        root.identityNames = (ok2 && parsed2 && Array.isArray(parsed2.names)) ? parsed2.names : []
      })
    })
  }

  // Both of these are the owner's to decide, and polkit's agent draws that
  // prompt for itself: nothing here collects it, and nothing here can proceed
  // without it. The engine rewrites the index, so the binding arrives back the
  // same way every other change does.
  function bindIdentity(profile, identity) {
    root.faceError = ""
    root.ask(["identity", "bind", profile, identity, "--json"], "", function (ok, parsed) {
      if (ok) return
      root.faceError = root.faceRefusal(parsed)
    })
  }

  function clearIdentity(profile) {
    root.faceError = ""
    root.ask(["identity", "clear", profile, "--json"], "", function (ok, parsed) {
      if (ok) return
      root.faceError = root.faceRefusal(parsed)
    })
  }

  function faceRefusal(parsed) {
    var err = parsed && parsed.error ? String(parsed.error) : "failed"
    if (err === "owner_declined") return "Not authorised"
    if (err === "face_absent") return "The face plugin is not installed"
    if (err === "no_such_identity") return "No face is enrolled under that name"
    if (err === "helper_unavailable") return "The helpers are not installed — open Setup"
    return "That did not work"
  }

  function cancelPassword() {
    if (root.faceProc) { root.faceProc.signal(15); root.faceProc = null }
    root.faceTrying = false
    root.passwordFor = ""
    root.passwordMode = ""
    root.passwordArg = ""
    root.passwordError = ""
    root.passwordRetryIn = 0
    root.applying = ""
  }

  // The contract's exit-2 codes, each with a different thing for the user to
  // do. A wrong password and a rate limit must never render alike: one is "try
  // again", the other is "you cannot try again yet".
  function handleAuthError(id, parsed, code) {
    root.faceTrying = false
    var err = parsed && parsed.error ? String(parsed.error) : "failed"

    if (err === "needs_password") {
      // Nothing was tried and nothing was wrong: the field simply appears.
      root.passwordError = ""
    } else if (err === "bad_password") {
      root.passwordError = "Wrong password"
    } else if (err === "rate_limited") {
      root.passwordRetryIn = parsed.retry_after || 30
      root.passwordError = ""
    } else if (err === "owner_declined") {
      root.passwordError = "Not authorised"
      // On a profile locked without a password there is no field to fall back
      // to, so there is nothing left to show.
      var e = root.entry(id)
      if (!e || !e.hasPassword) { root.cancelPassword(); return }
    } else if (err === "no_password") {
      // Not a refusal: the profile has no password at all. The index the panel
      // is holding is out of date.
      root.passwordFor = ""
      root.runEngine("refresh")
      return
    } else if (err === "empty_password") {
      root.passwordError = "Type the password"
    } else if (err === "helper_unavailable") {
      // Never "wrong password": the helper is missing or unregistered, which
      // is the polkit row's business.
      root.passwordFor = ""
      root.switchError = "The password helpers are not installed — open Setup"
      root.loadSetup(true)
      root.pushView("setup")
      return
    } else if (err === "stale_password") {
      root.passwordError = "A password is still stored under that name — clear it in Setup"
    } else if (err === "interrupted_switch" || err === "held_paths") {
      root.passwordFor = ""
      root.switchError = "The last switch did not finish — open Setup"
      root.loadSetup(true)
      root.pushView("setup")
      return
    } else if (code === 3) {
      root.passwordError = "Another switch is still running"
    } else {
      root.passwordError = "Could not check the password"
    }

    if (root.passwordFor === "") {
      root.passwordFor = id
      if (root.passwordMode === "") root.passwordMode = "enter"
    }
    root.switchError = ""
  }

  // Creating a profile is the one form that can come back with something to
  // say about a password: a hash left behind by a deleted profile of the same
  // name.
  function createProfile(name, fromMaster) {
    root.createError = ""
    root.ask(["create", name, fromMaster ? "--from-master" : "--clean"], "", function (ok, parsed, code) {
      if (ok) return
      var err = parsed && parsed.error ? String(parsed.error) : ""
      root.createError = err === "stale_password"
        ? "A password is still stored for a deleted profile with this name — clear it in Setup"
        : "Could not create that profile"
    })
  }

  // One line under the hero title, cleared by the next attempt or by arriving
  // somewhere.
  property string switchError: ""

  // Where each view says it is, in one table rather than a ternary chain per
  // piece of chrome. Every view has a row; a lookup that misses still answers,
  // so a view added later is never chrome-less.
  readonly property var viewChrome: ({
    "picker":   { title: "Profiles",        meta: "Same files, a different desk",
                  hint: "j/k move · enter apply · middle-click the bar to cycle" },
    "manage":   { title: "Manage profiles", meta: "Create, remove, or hide a profile",
                  hint: "esc closes · the arrow returns to switching" },
    "settings": { title: "",                meta: "What this profile may use",
                  hint: "back returns to the list · closes itself if left alone" },
    "overview": { title: "What is open",    meta: "Nothing closes when you switch",
                  hint: "measured from each window's cgroup, not estimated" },
    "config":   { title: "Configuration",   meta: "What a desk is, and what every desk shares",
                  hint: "back returns to the list · the lower groups apply to every profile" },
    "setup":    { title: "Setup",           meta: "What has to be true before this works",
                  hint: "each row is one thing; Fix does it for you" },
    "edit":     { title: "Edit profile",    meta: "Its name, its icon, and the line under it",
                  hint: "a protected profile asks for its password before the name changes" },
    "purge":    { title: "Remove Profiles", meta: "What goes, and what is handed back",
                  hint: "nothing is removed until Remove is pressed" }
  })

  function chrome() {
    var c = root.viewChrome[root.view]
    return c ? c : { title: "Profiles", meta: "", hint: "" }
  }

  // The settings view is titled by what it is editing, which no table can hold.
  function viewTitle() {
    return root.view === "settings" ? root.settingsProfile : root.chrome().title
  }

  // Navigation, in functions rather than in the controls, so the back arrow and
  // the removal confirmation take exactly the same route out of a view.
  function navBack() {
    // From the picker the arrow goes the other way: it is the only way in.
    if (root.view === "picker") { root.pushView("manage"); return }
    if (root.view === "settings") root.settingsProfile = ""
    if (root.view === "edit") root.editProfile = ""
    root.popView()
  }

  function openOverview() {
    root.runEngine("overview")
    root.pushView("overview")
  }

  // ------------------------------------------------------------- edit view
  //
  // A page of its own rather than a row that unfolds: the icon grid alone is
  // sixteen cells, and an expansion that tall under one profile pushes every
  // other one off the panel.
  function openEdit(profile) {
    root.editProfile = profile
    root.metaError = ""
    root.pushView("edit")
  }

  // Icon and description only. The name goes through `rename`, which moves a
  // password hash and a face binding with it and has to authenticate first.
  function submitMeta(profile, icon, description) {
    root.metaError = ""
    var args = ["meta", profile, "--icon", String(icon), "--description", String(description), "--json"]
    root.ask(args, "", function (ok, parsed) {
      if (ok) { root.popView(); return }
      var err = parsed && parsed.error ? String(parsed.error) : "failed"
      root.metaError = err === "bad_icon" ? "That is more than one glyph"
                     : err === "bad_description" ? "That is longer than one line"
                     : "Could not save that"
    })
  }

  // Capture is a write with no watched file to land in — `capture` rewrites the
  // active profile's own JSON and nothing the panel reads — so it goes through
  // ask() and reports for itself. It can also come back busy, which is exactly
  // what the button must not swallow.
  function captureNow() {
    root.captureNote = "Saving…"
    root.captureFailed = false
    root.ask(["capture"], "", function (ok, parsed, code) {
      if (ok) { root.captureNote = "Saved this desk as it is now"; captureNoteTimer.restart(); return }
      root.captureFailed = true
      var err = parsed && parsed.error ? String(parsed.error) : ""
      root.captureNote = (code === 3 || err === "busy") ? "A switch is running — try again in a moment"
                       : (err === "interrupted_switch" || err === "held_paths")
                         ? "The last switch did not finish — open Setup"
                       : "Could not save this desk"
      captureNoteTimer.restart()
    })
  }

  // ---------------------------------------------------------- reopen apps
  //
  // Two answers from the same verb, kept apart because they are about two
  // different profiles: `sessionData` is the ACTIVE profile's, and decides
  // whether the Restore windows button is on the picker; `configSession` is
  // whichever profile the config page is describing.
  //
  // The button is the guarantee, not the notification. The engine raises
  // "Restore windows?" only once the shell is up, and a switch or a restart
  // while it is pending destroys it with no answer and so no replay — at which
  // point this is the only way back to those windows.
  property var sessionData: null
  property var configSession: null
  property string sessionError: ""

  function loadSession() {
    if (root.currentProfile === "") { root.sessionData = null; return }
    root.ask(["session", "show", "--json", root.currentProfile], "", function (ok, parsed) {
      root.sessionData = (ok && parsed && !parsed.error) ? parsed : null
    })
  }

  function loadConfigSession() {
    if (root.configProfile === "") { root.configSession = null; return }
    root.ask(["session", "show", "--json", root.configProfile], "", function (ok, parsed) {
      root.configSession = (ok && parsed && !parsed.error) ? parsed : null
    })
  }

  // Whether the picker offers it at all: a record with something in it, an
  // empty block, and a profile that has not been told never to ask.
  readonly property bool canRestore: {
    var s = root.sessionData
    if (!s || root.currentProfile === "") return false
    if (String(s.restore_apps || "ask") === "off") return false
    if (!Array.isArray(s.apps) || s.apps.length === 0) return false
    return !!s.blockEmpty
  }

  function restoreWindows() {
    if (root.currentProfile === "") return
    root.sessionError = ""
    root.ask(["session", "restore", root.currentProfile], "", function (ok, parsed, code) {
      if (ok) {
        // The windows are what the answer looks like; nothing here needs to
        // render a count. Hiding the button is just refusing to offer it twice.
        root.sessionData = null
        root.close()
        return
      }
      var err = parsed && parsed.error ? String(parsed.error) : ""
      root.sessionError = (code === 3 || err === "busy") ? "Another switch is still running"
                        : err === "not_empty" ? "This desk already has windows open"
                        : err === "not_active" ? "Switch to that profile first"
                        : "Could not reopen those windows"
      root.loadSession()
    })
  }

  function sessionMode(profile, value) {
    root.ask(["session", "mode", profile, String(value), "--json"], "", function (ok) {
      if (!ok) return
      root.loadConfig()
      if (profile === root.currentProfile) root.loadSession()
    })
  }

  function sessionClear(profile) {
    root.ask(["session", "clear", profile, "--json"], "", function (ok) {
      if (!ok) return
      root.loadConfigSession()
      if (profile === root.currentProfile) root.loadSession()
    })
  }

  // ----------------------------------------------------------------- purge
  //
  // Taking the plugin off the machine. Everything on the screen comes from
  // `purge --dry-run --json`, which writes nothing: what is listed is what the
  // engine would delete, from the engine, rather than a second description of
  // it maintained here.
  //
  // Two buttons and one rule — nothing is removed until Remove is pressed. The
  // export is a separate invocation for the same reason: it has to have
  // succeeded, visibly, before the irreversible one is worth offering.
  property var purgeManifest: null
  // "" not asked yet · "ok" · anything else is what went wrong. Never healthy
  // by default: an unanswered dry run and an empty machine must not look alike.
  property string purgeState: ""
  property string purgeError: ""
  property string purgeNote: ""
  property bool purgeExported: false
  property bool purgeBusy: false
  // The clone is the user's plugin, listed in the manifest and asked about
  // rather than assumed: it is a bar widget they may want to keep.
  property bool purgeKeepIndicator: false
  property string purgeExportDir: ""

  // Set when `purge --yes` itself came back `not_master` — the profile changed
  // between this screen opening and Remove being pressed. The engine's refusal
  // wins over the manifest's answer, and renders as the same screen.
  property bool purgeRaced: false

  // From the manifest, not from the panel's own idea of the active profile: the
  // engine is the one that will refuse, and it answers both questions at once.
  readonly property bool purgeOnMaster: {
    if (root.purgeRaced) return false
    var m = root.purgeManifest
    if (m && m.master) return String(m.current || "") === String(m.master)
    return root.currentProfile !== "" && root.currentProfile === root.masterName
  }

  function openPurge() {
    root.purgeManifest = null
    root.purgeState = ""
    root.purgeError = ""
    root.purgeNote = ""
    root.purgeExported = false
    root.purgeBusy = false
    root.purgeRaced = false
    if (root.purgeExportDir === "") root.purgeExportDir = root.home + "/omarchy-profiles-export"
    root.pushView("purge")
    root.ask(["purge", "--dry-run", "--json"], "", function (ok, parsed, code) {
      if (ok && parsed && !parsed.error) {
        root.purgeManifest = parsed
        root.purgeState = "ok"
        return
      }
      root.purgeManifest = null
      root.purgeState = (parsed && parsed.error) ? String(parsed.error) : ("exit " + code)
    })
  }

  function purgeExport(dir) {
    var d = String(dir || "").trim()
    if (d === "") return
    root.purgeExportDir = d
    root.purgeError = ""
    root.purgeNote = "Copying…"
    root.purgeBusy = true
    root.ask(["purge", "--export", d, "--json"], "", function (ok, parsed, code) {
      root.purgeBusy = false
      if (ok && parsed && parsed.ok) {
        root.purgeExported = true
        root.purgeNote = "Copied " + (parsed.files || 0) + " file(s) to " + d + ". Nothing has been removed."
        return
      }
      root.purgeNote = ""
      var err = parsed && parsed.error ? String(parsed.error) : "failed"
      root.purgeError = err === "busy" || code === 3 ? "A switch is running — try again in a moment"
                      : err === "not_a_directory" ? "That path is a file, not a directory"
                      : err === "no_directory" ? "Type where the copy should go"
                      : "Could not copy them there"
    })
  }

  // The last thing this panel ever does. The engine prints its result and only
  // then removes the plugin, which reloads every panel in the shell — so this
  // callback may simply never run, and that is success, not a hang.
  function purgeRemove() {
    root.purgeError = ""
    root.purgeNote = "Removing…"
    root.purgeBusy = true
    var args = ["purge", "--yes", "--json"]
    if (root.purgeKeepIndicator) args = args.concat(["--keep-indicator"])
    root.ask(args, "", function (ok, parsed, code) {
      root.purgeBusy = false
      if (ok) {
        root.purgeNote = "Removed. The shell is restarting."
        return
      }
      root.purgeNote = ""
      var err = parsed && parsed.error ? String(parsed.error) : "failed"
      if (err === "not_master") {
        // A race: the profile changed between this screen opening and Remove
        // being pressed. The screen becomes the off-master one, which is the
        // same thing said the same way.
        root.purgeRaced = true
        root.purgeError = ""
        return
      }
      root.purgeError = (err === "busy" || code === 3) ? "A switch is running — try again in a moment"
                      : err === "interrupted_switch" || err === "held_paths"
                        ? "The last switch did not finish — open Setup"
                      : "Could not remove it"
    })
  }

  // Off master the flow cannot continue by itself: a switch restarts the shell,
  // which takes this panel with it. So this switches, and the user opens the
  // screen again — which is what the button says.
  function purgeSwitchToMaster() {
    if (root.masterName === "") return
    root.apply(root.masterName)
  }

  function openSettings(profile) {
    root.settingsProfile = profile
    root.pushView("settings")
    root.runEngine("catalog")
    root.loadSettingsApps(profile)
  }

  function loadSettingsApps(profile) {
    root.settingsAllApps = []
    if (profile === "") return
    root.ask(["apps", "list", "--json", profile], "", function (ok, parsed) {
      // A failure leaves it empty, and the view falls back to what the machine
      // is showing right now — wrong about hidden apps, but never blank.
      if (ok && parsed && Array.isArray(parsed.all)) root.settingsAllApps = parsed.all
    })
  }

  function parseState(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      if (parsed && typeof parsed === "object" && typeof parsed.profile === "string") {
        var arrived = parsed.profile !== root.currentProfile
        root.currentProfile = parsed.profile
        root.applying = ""
        // Arriving somewhere is the only thing that clears a stalled switch:
        // the file naming the new profile is written by the switch itself.
        if (arrived) { root.switchStalled = false; root.switchError = "" }
        var i = root.visibleIndexOf(parsed.profile)
        if (i >= 0) root.cursor = i
        // A different profile has a different record and a different block, and
        // this file changing is the only announcement a switch ever makes.
        if (arrived) { root.sessionError = ""; root.loadSession() }
        return
      }
      console.warn("graveklar.profiles", "State file has no profile field", root.statePath)
    } catch (e) {
      // Half-written file, or something that is not JSON. Keep the last known
      // profile rather than blanking the widget.
      console.warn("graveklar.profiles", "Ignoring bad state file", root.statePath, e)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    // Fresh arm: this open might be the misclick.
    touchedSinceOpen = false
    cursorActive = false
    if (currentProfile !== "") cursor = Math.max(0, visibleIndexOf(currentProfile))
    stateFile.reload()
    // Recomputed on open rather than polled: it reads /proc for every window,
    // which is not something to do on a timer for a panel nobody is looking at.
    root.runEngine("overview")
    // Asked on every open, and it decides which view this open lands on: a
    // panel that offers a profile list while nothing can switch is worse than
    // one that says what is wrong.
    root.setupError = ""
    root.loadSetup(true)
    // Whether a bound face is worth trying at all. Asked here rather than
    // guessed from the index: a profile can name an identity on a machine
    // where the face plugin has since been removed.
    root.loadFaces()
    // Asked on every open rather than cached: the block empties and fills while
    // the panel is shut, and a stale answer here either offers to reopen
    // windows that are already there or hides the offer when it is wanted.
    root.sessionError = ""
    root.loadSession()
    if (root.switchStalled) root.resetView("setup")
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  AskProcess { id: askProc0 }
  AskProcess { id: askProc1 }
  AskProcess { id: askProc2 }
  AskProcess { id: askProc3 }
  readonly property var askPool: [askProc0, askProc1, askProc2, askProc3]

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    property string lastText: ""
    onLoaded: {
      var t = text()
      if (t === stateFile.lastText) return
      stateFile.lastText = t
      root.parseState(t)
    }
    // No state file yet means no profile has been applied. Leave the label
    // generic instead of claiming one.
    onLoadFailed: root.currentProfile = ""
  }

  // Why every watcher compares the text before assigning:
  //
  // A Repeater whose model is a JS array rebuilds EVERY delegate when the array
  // is reassigned, even if the new array is identical. The rebuilt row under the
  // pointer is a different item, and Qt Quick only delivers an enter event on
  // the next mouse MOVE -- so a button the cursor is already sitting on goes
  // cold and stays cold until the mouse is jiggled. The engine rewrites these
  // files often, frequently with byte-identical content, so the cheap guard
  // below is what keeps a still pointer on a live button.

  FileView {
    id: overviewFile
    path: root.overviewPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    property string lastText: ""
    onLoaded: {
      try {
        var t = text()
        if (t === overviewFile.lastText) return
        overviewFile.lastText = t
        var parsed = JSON.parse(t)
        if (Array.isArray(parsed)) root.overviewRows = parsed
      } catch (e) {
        console.warn("graveklar.profiles", "Ignoring bad overview", root.overviewPath, e)
      }
    }
    onLoadFailed: root.overviewRows = []
  }

  FileView {
    id: catalogFile
    path: root.catalogPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    property string lastText: ""
    onLoaded: {
      try {
        var t = text()
        if (t === catalogFile.lastText) return
        catalogFile.lastText = t
        var parsed = JSON.parse(t)
        if (Array.isArray(parsed)) root.pluginCatalog = parsed
      } catch (e) {
        console.warn("graveklar.profiles", "Ignoring bad plugin catalog", root.catalogPath, e)
      }
    }
    onLoadFailed: root.pluginCatalog = []
  }

  // The edited profile's own file, so its switches show its saved state rather
  // than the machine's current state.
  FileView {
    id: profileFile
    path: root.settingsProfile === "" ? ""
          : (Quickshell.env("XDG_CONFIG_HOME") || root.home + "/.config")
            + "/omarchy/profiles/" + root.settingsProfile + ".json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    property string lastText: ""
    onLoaded: {
      try {
        var t = text()
        if (t === profileFile.lastText) return
        profileFile.lastText = t
        var parsed = JSON.parse(t)
        var d = (parsed && parsed.plugins && parsed.plugins.disabled) || []
        root.settingsDisabled = Array.isArray(d) ? d : []
        var a = (parsed && parsed.apps && parsed.apps.allowed) || []
        root.settingsAllowedApps = Array.isArray(a) ? a : []
      } catch (e) {
        root.settingsDisabled = []
        root.settingsAllowedApps = []
      }
    }
    onLoadFailed: root.settingsDisabled = []
  }

  // Tier-3 rollbacks. Watched rather than asked for, because it is written by
  // a switch — which is to say by a process that has already killed this panel
  // once and will do so again; the file is what survives that.
  FileView {
    id: hyprErrorsFile
    path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state")
          + "/omarchy-profiles/hypr-errors.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    property string lastText: ""
    onLoaded: {
      try {
        var t = text()
        if (t === hyprErrorsFile.lastText) return
        hyprErrorsFile.lastText = t
        var parsed = JSON.parse(t)
        root.hyprErrors = (parsed && typeof parsed === "object") ? parsed : ({})
      } catch (e) {
        root.hyprErrors = ({})
      }
    }
    // Absent means nothing is outstanding, exactly like {}.
    onLoadFailed: root.hyprErrors = ({})
  }

  FileView {
    id: indexFile
    path: root.indexPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    property string lastText: ""
    onLoaded: {
      var t = text()
      if (t === indexFile.lastText) return
      indexFile.lastText = t
      root.parseIndex(t)
    }
    onLoadFailed: root.profiles = []
  }

  // Same cold-start problem as the state file: the index does not exist until
  // the engine has run once, and a watch cannot announce a file under a
  // directory that was missing when the watch began.
  Timer {
    interval: 2000
    repeat: true
    running: root.profiles.length === 0
    triggeredOnStart: true
    onTriggered: indexFile.reload()
  }

  // Cold start. watchChanges cannot announce a file whose parent directory did
  // not exist when the watch began — which is the normal case on a fresh
  // machine, where the state directory is created by the first
  // `omarchy-profile set`. A one-shot retry is not enough either: the engine
  // may first run minutes or days after the shell started.
  //
  // So poll until the file has been read once, then stop. `running` is bound to
  // "we still don't know the profile", so this timer disables itself the moment
  // it succeeds and the watcher takes over for every later write.
  Timer {
    interval: 2000
    repeat: true
    running: root.currentProfile === ""
    triggeredOnStart: true
    onTriggered: stateFile.reload()
  }

  // A click goes out through the engine, which takes a moment to write state.
  // Nudge the read rather than waiting on the cold-start poll or the watcher.
  Timer {
    id: applyReload
    interval: 600
    repeat: true
    triggeredOnStart: false
    running: root.applying !== ""
    onTriggered: stateFile.reload()
  }

  Timer {
    id: idleClose
    interval: root.idleCloseMs
    repeat: false
    // Stops for good once anything has been touched, and never runs while a
    // confirmation, a password prompt or a Setup step is open: each is a
    // question waiting for an answer, and timing it out would dismiss it
    // without the user deciding.
    running: root.opened && !root.touchedSinceOpen
             && root.pendingRemoval === "" && root.pendingClose === ""
             && root.passwordFor === "" && root.pendingSetup === ""
             && root.view !== "purge"
    onTriggered: if (root.opened && !root.touchedSinceOpen) root.close()
  }

  // The switch was authorised and then nothing arrived. Nothing can report back
  // — the process that was doing it restarts this shell — so the absence of
  // current.json changing IS the signal, and the answer is in Setup's `switch`
  // row, which reads the journal the engine left behind.
  Timer {
    id: applyTimeout
    interval: 20000
    repeat: false
    onTriggered: {
      if (root.applying !== "" && root.applying !== root.currentProfile)
        root.switchStalled = true
      root.applying = ""
    }
  }

  // A capture leaves nothing on screen to show it happened — the desk it saved
  // is the desk already there — so the button says so for a few seconds and
  // then stops saying it.
  Timer {
    id: captureNoteTimer
    interval: 5000
    repeat: false
    onTriggered: root.captureNote = ""
  }

  // How long the running fix has been running. A Setup step that installs
  // something can take seconds, and a button that goes quiet is indistinguishable
  // from one that did nothing.
  Timer {
    interval: 1000
    repeat: true
    running: root.pendingSetup !== ""
    onTriggered: root.setupElapsed = root.setupElapsed + 1
  }

  // What was open, written down about ten seconds after it stops changing.
  //
  // Debounced, because the interesting moment is not the window opening but
  // the set settling: opening a terminal, a browser and an editor in a row is
  // one record, not three. Ten seconds is also short enough that a desk shut
  // down normally has been written before the last window goes.
  //
  // Quickshell.execDetached with an argv, NOT bar.run: that facade starts a
  // login shell per call, which is a whole bash profile every ten seconds for
  // a command that has no output anybody reads. The engine's own lock makes
  // one widget per monitor harmless.
  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { recordDebounce.restart() }
  }

  Timer {
    id: recordDebounce
    interval: 10000
    repeat: false
    onTriggered: Quickshell.execDetached([root.engine, "session", "record"])
  }

  // Once per boot, decided entirely by the engine.
  //
  // This runs on every shell start, which is every switch — the widget checks
  // nothing and knows nothing about markers. The engine's
  // $XDG_RUNTIME_DIR/omarchy-profiles/login directory is the only guard there
  // is, which is what makes it correct: a marker the GUI also consulted would
  // be two answers to one question.
  Component.onCompleted: Quickshell.execDetached([root.engine, "login"])

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }

    // omarchy-shell graveklar.profiles current
    function current(): string { return root.currentProfile }

    // omarchy-shell graveklar.profiles set dev
    function set(name: string): string {
      var id = String(name || "")
      if (root.indexOf(id) < 0) return "unknown or hidden profile: " + id
      root.apply(id)
      return "ok"
    }

    // omarchy-shell graveklar.profiles promptUnlock work
    //
    // How a keybinding asks for a password: `next` has nowhere to type, so it
    // hands the profile here and stops. `login` uses it too.
    function promptUnlock(name: string): string {
      var id = String(name || "")
      if (root.indexOf(id) < 0) return "unknown profile"
      root.open()
      root.resetView("picker")
      root.beginUnlock(id)
      return "ok"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon(root.applying !== "" ? root.applying : root.currentProfile)
    active: root.applying !== ""
    tooltipText: root.tooltip()
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.bar.run(root.engine + " next")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    // Anchored over the whole panel, and deliberately NOT a Column child: QML
    // refuses anchors inside a Column, and without them the dialog was laid
    // out as an ordinary row that filled the panel with a blank page.
    ConfirmDialog {
      id: removeDialog
      anchors.fill: parent
      z: 10
      opened: root.pendingRemoval !== ""
      message: "Remove the profile \"" + root.pendingRemoval + "\"?\n\nIts saved theme, bar, plugin list and any per-profile plugin data (a signed-in Spotify session, its own dock) are deleted. Any windows still open on its workspaces move to " + (root.masterName === "" ? "the master" : root.masterName) + " — nothing is left stranded."
      confirmText: "Remove"
      cancelText: "Keep"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onCanceled: root.pendingRemoval = ""
      onConfirmed: {
        var name = root.pendingRemoval
        root.pendingRemoval = ""
        // The removed profile may be the one the settings view was editing.
        if (root.view === "settings") root.navBack()
        var e = root.entry(name)
        if (e && (e.hasPassword || e.locked)) {
          // The engine authenticates before it moves a single window, so a
          // refused password here leaves the profile exactly as it was.
          root.beginManage(name, "remove")
          return
        }
        root.ask(["remove", name, "--json"], "", function (ok, parsed, code) {
          if (!ok) root.handleAuthError(name, parsed, code)
        })
      }
    }

    ConfirmDialog {
      id: closeDialog
      anchors.fill: parent
      z: 10
      opened: root.pendingClose !== ""
      message: "Close everything open in \"" + root.pendingClose + "\"?\n\nEach window is asked to close, so anything with unsaved work can still stop you. The profile itself is kept."
      confirmText: "Close them"
      cancelText: "Leave them"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onCanceled: root.pendingClose = ""
      onConfirmed: {
        root.runEngine("close " + root.pendingClose)
        root.pendingClose = ""
        root.runEngine("overview")
      }
    }

    // Above the confirmations: a remove is confirmed first and authenticated
    // second, so the prompt has to draw over the dialog that raised it.
    PasswordPrompt {
      id: passwordPrompt
      anchors.fill: parent
      z: 11
      panel: root
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      // Anything at all: a hover, a click, a key. One of these fires long
      // before twelve seconds if a person is actually looking at the panel.
      // Inside the key catcher rather than beside it: KeyboardPanel's default
      // property is a single contentItem, and a handler is not an Item.
      HoverHandler {
        onHoveredChanged: if (hovered) root.keepAlive()
      }

      TapHandler {
        onTapped: root.keepAlive()
      }

      // Inert while a password is being asked for: Enter belongs to the prompt,
      // and an arrow key must not move a cursor the user cannot see.
      onMoveRequested: function (dx, dy) {
        if (root.passwordFor !== "") return
        root.keepAlive()
        root.cursorActive = true
        var len = (root.view === "manage" ? root.profiles.length : root.visibleProfiles.length)
        if (dy !== 0) root.cursor = Math.max(0, Math.min(Math.max(0, len - 1), root.cursor + dy))
      }
      onActivateRequested: {
        if (root.passwordFor !== "") return
        // Enter only switches in the picker; in the manage view the row's own
        // buttons are the actions, and an accidental Enter must not delete one.
        if (root.view !== "picker") return
        var e = root.visibleProfiles[root.cursor]
        if (e) root.apply(e.id)
      }
      // Escape answers the prompt first: it closes the question, not the panel
      // behind it, and switches nothing.
      onCloseRequested: if (root.passwordFor !== "") root.cancelPassword(); else root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      // The plugin list runs to ~60 rows, far past any sensible panel height.
      // Without this the Column simply drew past the panel's own bounds and
      // over the desktop. clip + StopAtBounds keeps it inside; `interactive`
      // engages only when there is genuinely more than fits, so short views
      // still behave like a static panel rather than a scroll area.
      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // Scrolling a sixty-row list is the clearest possible sign this was
        // not a misclick, and it was the main thing closing the panel mid-read.
        onMovementStarted: root.keepAlive()

      Column {
        id: column
        width: flick.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: root.viewTitle()
          // Empty outside the picker: the pill names the profile you are IN,
          // which only matters while choosing one. Showing "Master" beside the
          // title "test" read as a label on test.
          detail: root.view === "picker" && root.currentProfile !== "" ? root.label(root.currentProfile)
                  : root.view === "edit" && root.editProfile !== "" ? root.label(root.editProfile) : ""
          // In order of what the person most needs to know: an error about the
          // thing they just did, the switch in progress, a Setup badge, and
          // only then the view's own strapline.
          meta: root.switchError !== "" ? root.switchError
                : root.applying !== "" ? "Switching to " + root.label(root.applying) + "…"
                : (root.view !== "setup" && root.setupBadge > 0)
                  ? (root.setupBadge === 1 ? "One thing needs attention in Setup"
                                           : root.setupBadge + " things need attention in Setup")
                : root.chrome().meta
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              // On a page about one profile the hero wears that profile's icon,
              // not the active profile's — which is also how the edit form
              // shows what it just changed.
              text: root.icon(root.view === "settings" && root.settingsProfile !== "" ? root.settingsProfile
                              : root.view === "edit" && root.editProfile !== "" ? root.editProfile
                              : root.currentProfile)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          // The way between the views, in the one place a hero control belongs.
          // One step back each press, so a view returns to whatever opened it
          // rather than jumping to the switcher.
          trailingControl: Component {
            PanelActionButton {
              iconText: root.view === "picker" ? "󰒓" : "󰌍"
              tooltipText: root.view === "picker" ? "Manage profiles" : "Back"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                root.keepAlive()
                root.navBack()
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---------------------------------------------------------- picker

        // Under the hero and above the list: it is about the desk you are
        // standing in, not one you might switch to, and putting it beside the
        // rows would read as a per-row control.
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.view === "picker" && (root.canRestore || root.sessionError !== "")

          Button {
            visible: root.canRestore
            width: parent.width
            leftAlign: true
            bordered: true
            iconText: "󰑓"
            text: {
              var n = (root.sessionData && root.sessionData.apps) ? root.sessionData.apps.length : 0
              return "Restore windows — " + n + (n === 1 ? " app was" : " apps were") + " open here"
            }
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: { root.keepAlive(); root.restoreWindows() }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            visible: root.sessionError !== ""
            text: root.sessionError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.view === "picker"

          PanelSectionHeader {
            width: parent.width
            text: "SWITCH PROFILE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            // Hidden profiles stay out of the switcher but remain in the
            // manage view, which is the whole point of hiding one.
            model: root.visibleProfiles

            ProfileRow {
              required property var modelData
              required property int index
              width: column.width
              entry: modelData
              rowIndex: index
            }
          }

          // Nothing to switch to. The old text named a command to type, which is
          // the one thing this plugin is not: Setup adopts the machine.
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.visibleProfiles.length === 0

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: "No profiles yet. Setup adopts this machine as your master profile — it reads the desktop as it is now and changes nothing."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Button {
              text: "Open Setup"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: { root.keepAlive(); root.pushView("setup") }
            }
          }

          // The badge on the hero says something needs attention; this is the
          // way to it. Without it the badge would be a dead end.
          Button {
            visible: root.setupBadge > 0 && root.visibleProfiles.length > 0
            text: "Open Setup"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: { root.keepAlive(); root.pushView("setup") }
          }
        }

        // ---------------------------------------------------------- manage

        ManageView {
          width: parent.width
          visible: root.view === "manage"
          profiles: root.profiles
          currentProfile: root.currentProfile
          masterName: root.masterName
          foreground: root.foreground
          accent: root.accent
          dim: root.dim
          fontFamily: root.fontFamily
          cursorActive: root.cursorActive
          cursor: root.cursor
          visibleCount: root.visibleProfiles.length
          faceState: root.faceState
          identityNames: root.identityNames
          faceError: root.faceError
          captureNote: root.captureNote
          captureFailed: root.captureFailed
          onRunEngine: function (args) { root.keepAlive(); root.runEngine(args) }
          onCursorMoved: function (index) { root.keepAlive(); root.cursorActive = true; root.cursor = index }
          onConfirmRemove: function (profile) { root.keepAlive(); root.pendingRemoval = profile }
          onOpenOverview: { root.keepAlive(); root.openOverview() }
          onOpenSettings: function (profile) { root.keepAlive(); root.openSettings(profile) }
          onOpenConfig: function (profile) { root.keepAlive(); root.openConfig(profile) }
          createError: root.createError
          onPasswordAction: function (profile, mode) { root.keepAlive(); root.beginManage(profile, mode) }
          onCreateProfile: function (name, fromMaster) { root.keepAlive(); root.createProfile(name, fromMaster) }
          onOpenEdit: function (profile) { root.keepAlive(); root.openEdit(profile) }
          onBindIdentity: function (profile, identity) { root.keepAlive(); root.bindIdentity(profile, identity) }
          onClearIdentity: function (profile) { root.keepAlive(); root.clearIdentity(profile) }
          onCaptureNow: { root.keepAlive(); root.captureNow() }
          onOpenPurge: { root.keepAlive(); root.openPurge() }
        }

        ProfileMetaForm {
          width: parent.width
          visible: root.view === "edit"
          panel: root
        }

        OverviewView {
          width: parent.width
          visible: root.view === "overview"
          rows: root.overviewRows
          currentProfile: root.currentProfile
          foreground: root.foreground
          accent: root.accent
          dim: root.dim
          fontFamily: root.fontFamily
          onRunEngine: function (args) { root.keepAlive(); root.runEngine(args) }
          onConfirmClose: function (profile) { root.keepAlive(); root.pendingClose = profile }
          onTouched: root.keepAlive()
        }

        SetupView {
          width: parent.width
          visible: root.view === "setup"
          panel: root
        }

        ConfigView {
          width: parent.width
          visible: root.view === "config"
          panel: root
        }

        PurgeView {
          width: parent.width
          visible: root.view === "purge"
          panel: root
        }

        SettingsView {
          width: parent.width
          visible: root.view === "settings"
          profile: root.settingsProfile
          isMaster: root.settingsProfile === root.masterName
          plugins: root.pluginCatalog
          disabled: root.settingsDisabled
          allowedApps: root.settingsAllowedApps
          candidateApps: root.settingsAllApps
          foreground: root.foreground
          accent: root.accent
          dim: root.dim
          fontFamily: root.fontFamily
          onRunEngine: function (args) { root.keepAlive(); root.runEngine(args) }
          onTouched: root.keepAlive()
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          topPadding: Style.space(2)
          text: root.chrome().hint
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
      }
    }
  }

  // One slot of ask()'s pool. Reused rather than created per call, because a
  // Process built at call time would be garbage while it was still running.
  component AskProcess: Process {
    id: proc
    property bool busy: false
    property var job: null
    property string collected: ""
    property string stdinText: ""

    running: false
    stdinEnabled: true
    // waitForEnd, so the whole document is there when onExited reads it; the
    // copy kept on streamFinished is what the house pattern reads back.
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: proc.collected = text
    }
    onStarted: {
      if (proc.stdinText !== "") proc.write(proc.stdinText)
      proc.stdinText = ""
      // Closing the stream is what makes the engine's read return — without it
      // a verb that reads a password waits for EOF that never comes.
      proc.stdinEnabled = false
    }
    onExited: function (code, status) { root.askFinished(proc, code) }
  }

  // One profile: icon, name, one line of what it does. CursorSurface carries
  // both states the panel contract asks for — `hasCursor` for where the
  // keyboard is, `current` for which profile is actually active — so hover and
  // keyboard can never paint two highlights at once.
  component ProfileRow: CursorSurface {
    id: row
    property var entry: null
    property int rowIndex: 0

    foreground: root.foreground
    accent: root.accent
    hasCursor: root.cursorActive && root.cursor === row.rowIndex
    current: row.entry && row.entry.id === root.currentProfile

    implicitHeight: rowContent.implicitHeight + Style.space(16)

    Row {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: row.entry ? row.entry.icon : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: rowContent.width - rowContent.spacing * 2 - 2 * Style.space(10)
        spacing: 0

        Row {
          width: parent.width
          spacing: Style.space(5)

          Text {
            textFormat: Text.PlainText
            text: row.entry ? row.entry.label : ""
            // Master is distinguished by colour, not by a tag beside the name.
            color: (row.entry && row.entry.master) ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: row.current
            elide: Text.ElideRight
          }

          // A padlock here so a prompt on switching is never a surprise.
          Text {
            textFormat: Text.PlainText
            visible: !!(row.entry && row.entry.locked)
            text: "󰌾"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          textFormat: Text.PlainText
          text: row.entry ? row.entry.blurb : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }

    // Hover moves the panel's single cursor rather than painting its own
    // highlight — that is the CursorSurface contract.
    HoverHandler {
      onHoveredChanged: if (hovered) {
        root.cursorActive = true
        root.cursor = row.rowIndex
      }
    }

    TapHandler {
      onTapped: if (row.entry) root.apply(row.entry.id)
    }
  }
}
