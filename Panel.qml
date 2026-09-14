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

  // Which profile a password is being asked for, and which Setup row is waiting
  // on an answer. Nothing writes them yet — the prompt and the Setup view are
  // later phases — but the idle timer already has to know that a question is on
  // screen, and a property that is always "" is a cheaper stub than a timer
  // condition that changes shape later.
  property string passwordFor: ""
  property string pendingSetup: ""

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
  function ask(args, stdinText, callback) {
    var job = { args: args || [], stdin: String(stdinText || ""), callback: callback || null }
    for (var i = 0; i < root.askPool.length; i++) {
      if (!root.askPool[i].busy) { root.startAsk(root.askPool[i], job); return }
    }
    // Four at once is more than the panel ever needs; a fifth waits rather than
    // letting a stuck engine call spawn processes without bound.
    root.askQueue = root.askQueue.concat([job])
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
    if (currentProfile === "") return "Machine profile: not set"
    return "Machine profile: " + label(currentProfile)
  }

  // Every row does exactly this: hand the name to the engine and close. No
  // theme or bar logic in QML.
  function apply(id) {
    if (!root.bar || typeof root.bar.run !== "function") {
      console.warn("graveklar.profiles", "No bar facade to run the engine through")
      return
    }
    root.applying = id
    applyTimeout.restart()
    root.bar.run(root.engine + " set " + id)
    root.close()
  }

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
    "setup":    { title: "Setup",           meta: "", hint: "" },
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
  }

  function parseState(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      if (parsed && typeof parsed === "object" && typeof parsed.profile === "string") {
        root.currentProfile = parsed.profile
        root.applying = ""
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

  // If the engine dies without writing state, stop showing "switching…".
  Timer {
    id: applyTimeout
    interval: 20000
    repeat: false
    onTriggered: root.applying = ""
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
        root.runEngine("remove " + root.pendingRemoval)
        root.pendingRemoval = ""
        // The removed profile may be the one the settings view was editing.
        if (root.view === "settings") root.navBack()
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

      onMoveRequested: function (dx, dy) {
        root.keepAlive()
        root.cursorActive = true
        var len = (root.view === "manage" ? root.profiles.length : root.visibleProfiles.length)
        if (dy !== 0) root.cursor = Math.max(0, Math.min(Math.max(0, len - 1), root.cursor + dy))
      }
      onActivateRequested: {
        // Enter only switches in the picker; in the manage view the row's own
        // buttons are the actions, and an accidental Enter must not delete one.
        if (root.view !== "picker") return
        var e = root.visibleProfiles[root.cursor]
        if (e) root.apply(e.id)
      }
      onCloseRequested: root.close()
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
          meta: root.applying !== "" ? "Switching to " + root.label(root.applying) + "…"
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

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.visibleProfiles.length === 0
            wrapMode: Text.WordWrap
            text: "No profiles yet. Run `omarchy-profile init` to adopt this machine as your master profile."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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

        SettingsView {
          width: parent.width
          visible: root.view === "settings"
          profile: root.settingsProfile
          isMaster: root.settingsProfile === root.masterName
          plugins: root.pluginCatalog
          disabled: root.settingsDisabled
          allowedApps: root.settingsAllowedApps
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
