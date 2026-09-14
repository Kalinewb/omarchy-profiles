import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
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
  property bool faceInstalled: false
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

  // Phase 6's edit form calls this; the prompt does the rest.
  function beginRename(id, to) {
    root.passwordArg = to
    var e = root.entry(id)
    if (e && (e.hasPassword || e.locked)) { root.beginManage(id, "rename"); return }
    root.submitManage("rename", id, "")
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
  // piece of chrome. config, setup and edit arrive in later phases; their rows
  // are here now so a lookup for a view that is not built yet still answers.
  readonly property var viewChrome: ({
    "picker":   { title: "Profiles",        meta: "Same files, a different desk",
                  hint: "j/k move · enter apply · middle-click the bar to cycle" },
    "manage":   { title: "Manage profiles", meta: "Create, remove, or hide a profile",
                  hint: "esc closes · the arrow returns to switching" },
    "settings": { title: "",                meta: "What this profile may use",
                  hint: "back returns to the list · closes itself if left alone" },
    "overview": { title: "What is open",    meta: "Nothing closes when you switch",
                  hint: "measured from each window's cgroup, not estimated" },
    "config":   { title: "Configuration",   meta: "", hint: "" },
    "setup":    { title: "Setup",           meta: "What has to be true before this works",
                  hint: "each row is one thing; Fix does it for you" },
    "edit":     { title: "Edit profile",    meta: "", hint: "" }
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
    root.popView()
  }

  function openOverview() {
    root.runEngine("overview")
    root.pushView("overview")
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
    root.ask(["capabilities", "--json"], "", function (ok, parsed) {
      root.faceInstalled = !!(ok && parsed && parsed.face === "ok")
    })
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

  // How long the running fix has been running. A Setup step that installs
  // something can take seconds, and a button that goes quiet is indistinguishable
  // from one that did nothing.
  Timer {
    interval: 1000
    repeat: true
    running: root.pendingSetup !== ""
    onTriggered: root.setupElapsed = root.setupElapsed + 1
  }

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
          detail: root.view === "picker" && root.currentProfile !== "" ? root.label(root.currentProfile) : ""
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
              text: root.icon(root.view === "settings" && root.settingsProfile !== ""
                              ? root.settingsProfile : root.currentProfile)
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
          onRunEngine: function (args) { root.keepAlive(); root.runEngine(args) }
          onCursorMoved: function (index) { root.keepAlive(); root.cursorActive = true; root.cursor = index }
          onConfirmRemove: function (profile) { root.keepAlive(); root.pendingRemoval = profile }
          onOpenOverview: { root.keepAlive(); root.openOverview() }
          onOpenSettings: function (profile) { root.keepAlive(); root.openSettings(profile) }
          createError: root.createError
          onPasswordAction: function (profile, mode) { root.keepAlive(); root.beginManage(profile, mode) }
          onCreateProfile: function (name, fromMaster) { root.keepAlive(); root.createProfile(name, fromMaster) }
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
