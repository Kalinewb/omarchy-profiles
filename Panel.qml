import QtQuick
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
        if (!p || p.hidden) continue
        out.push({
          id: String(p.name || ""),
          label: String(p.name || "").replace(/^./, function (c) { return c.toUpperCase() }),
          icon: String(p.icon || "") || (p.master ? "󰒓" : "󰆼"),
          blurb: String(p.description || ""),
          master: !!p.master
        })
      }
      root.profiles = out
    } catch (e) {
      console.warn("graveklar.profiles", "Ignoring bad profile index", root.indexPath, e)
    }
  }

  property string currentProfile: ""
  property bool cursorActive: false
  property int cursor: 0
  // Set while the engine runs so a row can show it was the one picked; the
  // state file arriving is what actually clears it.
  property string applying: ""

  function indexOf(id) {
    for (var i = 0; i < profiles.length; i++) if (profiles[i].id === id) return i
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

  function parseState(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      if (parsed && typeof parsed === "object" && typeof parsed.profile === "string") {
        root.currentProfile = parsed.profile
        root.applying = ""
        var i = root.indexOf(parsed.profile)
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
    cursorActive = false
    if (currentProfile !== "") cursor = Math.max(0, indexOf(currentProfile))
    stateFile.reload()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseState(text())
    // No state file yet means no profile has been applied. Leave the label
    // generic instead of claiming one.
    onLoadFailed: root.currentProfile = ""
  }

  FileView {
    id: indexFile
    path: root.indexPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseIndex(text())
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

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function (dx, dy) {
        root.cursorActive = true
        if (dy !== 0) root.cursor = Math.max(0, Math.min(root.profiles.length - 1, root.cursor + dy))
      }
      onActivateRequested: root.apply(root.profiles[root.cursor].id)
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Profiles"
          detail: root.currentProfile !== "" ? root.label(root.currentProfile) : "Not set"
          meta: root.applying !== "" ? "Switching to " + root.label(root.applying) + "…"
                                     : "Same apps and files, different machine"
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.icon(root.currentProfile)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(4)

          PanelSectionHeader {
            width: parent.width
            text: "SWITCH PROFILE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.profiles

            ProfileRow {
              required property var modelData
              required property int index
              width: column.width
              entry: modelData
              rowIndex: index
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          topPadding: Style.space(2)
          text: "j/k move · enter apply · middle-click the bar to cycle"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
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

        Text {
          textFormat: Text.PlainText
          text: row.entry ? row.entry.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.current
          elide: Text.ElideRight
          width: parent.width
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
