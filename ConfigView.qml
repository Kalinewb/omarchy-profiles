import QtQuick
import qs.Commons
import qs.Ui

// Configuration: what a profile is, and what is allowed to differ between
// profiles. Every machine-wide row answers one question in the same two words,
// "Same as master" or "Separate", explained once where that half begins.
//
// The first group is display only — theme, wallpaper, bar, counts — because
// those things are always the profile's own and are changed where they live.
// Everything below it is machine-wide: isolating a path is one decision for the
// whole machine, not a per-profile setting, and that is stated once at the top
// of each group rather than repeated on every row.
//
// Nothing here mutates local state. Every control calls the engine and lets the
// answer come back through the panel's watchers, so this view and a terminal
// cannot disagree about what is isolated.
Column {
  id: view

  property var panel: null

  readonly property color foreground: panel ? panel.foreground : Color.foreground
  readonly property color accent: panel ? panel.accent : Color.accent
  readonly property color dim: panel ? panel.dim : Color.muted
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family

  readonly property string profile: panel ? panel.configProfile : ""
  readonly property var cfg: (panel && panel.configData) ? panel.configData : null
  readonly property var rows: (panel && panel.isolateRows) ? panel.isolateRows : []
  readonly property var candidates: (panel && panel.isolateCandidates) ? panel.isolateCandidates : []
  readonly property var globalStatus: (panel && panel.globalStatus) ? panel.globalStatus : null

  // What this profile remembers having open, and whether it is asked about.
  // The mode comes from `config --json` and the list from `session show
  // --json`, which is also where the mode would be — one source is enough, and
  // the config page already has the first one open.
  readonly property var session: (panel && panel.configSession) ? panel.configSession : null
  readonly property string restoreMode: {
    var m = view.cfg ? String(view.cfg.restore_apps || "ask") : "ask"
    return (m === "off" || m === "always") ? m : "ask"
  }
  readonly property var remembered: (view.session && Array.isArray(view.session.apps)) ? view.session.apps : []
  readonly property int rememberedCount: view.remembered.length
  property bool rememberedOpen: false

  // ok | unknown | broken. Anything else is treated as unknown: a fact nobody
  // could determine must never look like a healthy one.
  readonly property string reloadState: panel ? panel.hyprReload : "unknown"
  readonly property bool hyprUsable: view.reloadState === "ok"
  readonly property string hyprReason: view.reloadState === "broken"
    ? "Hyprland did not pick up a swapped file on this machine, so these are not offered."
    : "Whether Hyprland re-reads a swapped file has not been measured here yet — Setup can check."

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(12)

  function isolated(path) {
    for (var i = 0; i < view.rows.length; i++)
      if (String(view.rows[i].path) === path) return view.rows[i]
    return null
  }

  // The rollback record for this profile, if it names this file. Written by the
  // engine when a switch into the profile found new config errors in it.
  function rollbackFor(path) {
    if (!view.panel || !view.panel.hyprErrors) return null
    var e = view.panel.hyprErrors[view.profile]
    if (!e || !e.files) return null
    for (var i = 0; i < e.files.length; i++) if (String(e.files[i]) === path) return e
    return null
  }

  function shorten(p) {
    var s = String(p || "")
    var cut = s.lastIndexOf("/")
    return cut > 0 ? "~/…/" + s.substring(cut + 1) : s
  }

  // ------------------------------------------------------------- 1 · desktop

  PanelSectionHeader {
    width: parent.width
    text: "ONLY " + (view.panel ? String(view.panel.label(view.profile)).toUpperCase() : view.profile.toUpperCase())
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Always this profile's own. Change them while you are in it and they are kept when you leave."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Column {
    width: parent.width
    spacing: Style.space(2)

    FactRow { label: "Theme";       value: view.cfg ? String(view.cfg.theme || "—") : "…" }
    FactRow { label: "Wallpaper";   value: view.cfg ? (String(view.cfg.wallpaper || "") === "" ? "the theme's own" : String(view.cfg.wallpaper).replace(/^.*\//, "")) : "…" }
    FactRow { label: "Bar";         value: view.cfg ? (view.cfg.bar && view.cfg.bar.captured ? view.cfg.bar.widgets + " widgets, captured" : "Omarchy's own") : "…" }
    FactRow { label: "Plugins";     value: view.cfg && view.cfg.plugins ? view.cfg.plugins.enabled + " of " + view.cfg.plugins.total + " on" : "…" }
    FactRow { label: "Apps";        value: view.cfg && view.cfg.apps ? (view.cfg.master ? "every application" : view.cfg.apps.allowed + " of " + view.cfg.apps.total + " visible") : "…" }
    FactRow { label: "Workspaces";  value: view.cfg && view.cfg.workspaces ? view.cfg.workspaces.first + "–" + view.cfg.workspaces.last : "…" }
    FactRow { label: "Do not disturb"; value: view.cfg ? (view.cfg.dnd ? "on" : "off") : "…" }
    FactRow {
      label: "Idle"
      value: view.cfg && view.cfg.idle && view.cfg.idle.screensaver !== undefined
             ? ("screen " + view.cfg.idle.screensaver + "s · lock " + (view.cfg.idle.lock || 0) + "s")
             : "—"
    }
  }

  // Reopening what was open. Part of "this desk" because it is: the record is
  // the profile's own, like its theme and its workspaces, and nothing about it
  // is machine-wide.
  Text {
    textFormat: Text.PlainText
    width: parent.width
    topPadding: Style.space(6)
    text: "Reopen apps when entering"
    color: view.foreground
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
  }

  Row {
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: [
        { value: "off",    label: "Off" },
        { value: "ask",    label: "Ask" },
        { value: "always", label: "Always" }
      ]

      Button {
        required property var modelData
        text: String(modelData.label)
        selected: view.restoreMode === String(modelData.value)
        foreground: view.restoreMode === String(modelData.value) ? view.accent : view.dim
        fontFamily: view.fontFamily
        fontSize: Style.font.caption
        onClicked: {
          if (!view.panel || view.restoreMode === String(modelData.value)) return
          view.panel.keepAlive()
          view.panel.sessionMode(view.profile, String(modelData.value))
        }
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    // Ask promises to be ASKED, not to be guaranteed a notification: a switch
    // or a shell restart while one is pending destroys it, and the button in
    // the picker is what the promise actually rests on.
    text: view.restoreMode === "off"
          ? "This desk opens empty after a restart."
          : view.restoreMode === "always"
            ? "After a restart, what was open reopens by itself."
            : "After a restart you'll be asked whether to reopen what was open."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  // Collapsed, because it is a list nobody needs until they doubt it. The count
  // is the part that matters; the names are there to settle the doubt.
  Button {
    visible: view.rememberedCount > 0
    text: (view.rememberedOpen ? "󰅀  " : "󰅂  ") + "Remembered apps (" + view.rememberedCount + ")"
    foreground: view.foreground
    fontFamily: view.fontFamily
    fontSize: Style.font.caption
    onClicked: {
      if (view.panel) view.panel.keepAlive()
      view.rememberedOpen = !view.rememberedOpen
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(2)
    visible: view.rememberedOpen && view.rememberedCount > 0

    Repeater {
      model: view.remembered

      Text {
        required property var modelData
        textFormat: Text.PlainText
        width: parent.width
        text: "  " + String(modelData.workspace) + " · " + String(modelData.name || modelData.id)
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Button {
      text: "Forget"
      bordered: true
      foreground: view.foreground
      fontFamily: view.fontFamily
      fontSize: Style.font.caption
      onClicked: {
        if (!view.panel) return
        view.panel.keepAlive()
        view.panel.sessionClear(view.profile)
        view.rememberedOpen = false
      }
    }
  }

  PanelSeparator { foreground: view.foreground }

  // ------------------------------------------------- 2 · what profiles share
  //
  // Everything from here down is one decision for the whole machine, and every
  // row answers the same question with the same two words. Said once, here,
  // before the first row — not under the last one.

  PanelSectionHeader {
    width: parent.width
    text: "ALL PROFILES"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Everything below is set once for the whole machine, not per profile."
    color: view.accent
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Column {
    width: parent.width
    spacing: Style.space(2)

    LegendRow { term: "Same as master"; meaning: "every profile uses master's copy — a change made in any of them changes it for all" }
    LegendRow { term: "Separate";       meaning: "each profile keeps its own copy, and changes stay in that profile" }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    topPadding: Style.space(6)
    text: "Plugin data"
    color: view.foreground
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Sign-ins and settings a plugin keeps in its own files. Separate means, for example, a different Spotify account in each profile."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    // Isolated plugin paths first, then the ones that could be. Both come from
    // the engine — declarations in plugin manifests plus its own small table —
    // so a plugin that starts declaring appears here with nothing changed.
    model: {
      var out = []
      for (var i = 0; i < view.rows.length; i++) {
        var r = view.rows[i]
        if (String(r.source) !== "declared" && String(r.source) !== "table") continue
        out.push({ path: String(r.path), name: String(r.plugin || r.path), isolated: true })
      }
      for (var j = 0; j < view.candidates.length; j++) {
        var c = view.candidates[j]
        out.push({ path: String(c.path), name: String(c.name || c.plugin || c.path), isolated: false })
      }
      return out
    }

    DataRow {
      required property var modelData
      width: view.width
      entry: modelData
    }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: view.rows.length === 0 && view.candidates.length === 0
    wrapMode: Text.WordWrap
    text: "No installed plugin keeps data of its own."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  // ------------------------------------------------------------ 3 · Hyprland

  Text {
    textFormat: Text.PlainText
    width: parent.width
    topPadding: Style.space(6)
    text: "Hyprland"
    color: view.foreground
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: !view.hyprUsable
    wrapMode: Text.WordWrap
    text: view.hyprReason
    color: Color.urgent
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: [
      { file: "looknfeel.lua", label: "Look and feel", blurb: "Gaps, rounding, blur, animations" },
      { file: "bindings.lua",  label: "Keybindings",   blurb: "Your own keys, not the workspace keys" },
      { file: "input.lua",     label: "Input",         blurb: "Keyboard layout, repeat, touchpad" }
    ]

    HyprRow {
      required property var modelData
      width: view.width
      entry: modelData
    }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Separate files are swapped in with hyprctl reload on every switch, which also re-runs startup commands not marked once and undoes settings changed on the fly."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Monitors and the workspace keys are always the same as master: they describe the hardware and are managed by Setup."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  // --------------------------------------------------------- 4 · custom path

  Text {
    textFormat: Text.PlainText
    width: parent.width
    topPadding: Style.space(6)
    text: "Other files and folders"
    color: view.foreground
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Anything else is the same as master. Pick a file, or type a path and press Enter, to make it separate."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Dropdown {
    width: parent.width
    visible: view.candidates.length > 0
    label: "Suggested"
    value: ""
    options: {
      var out = [{ value: "", label: "Pick one…" }]
      for (var i = 0; i < view.candidates.length; i++)
        out.push({ value: String(view.candidates[i].path), label: String(view.candidates[i].name || view.candidates[i].path) })
      return out
    }
    foreground: view.foreground
    accent: view.accent
    fontFamily: view.fontFamily
    onChanged: function (value) {
      if (!view.panel || String(value) === "") return
      view.panel.keepAlive()
      view.panel.isolateAdd(String(value), "", "")
    }
  }

  TextField {
    id: customField
    width: parent.width
    placeholderText: "~/.config/something.json"
    foreground: view.foreground
    accent: view.accent
    font.family: view.fontFamily
    // The engine validates and its refusal renders below; nothing here decides
    // what a legal path is.
    onAccepted: {
      if (!view.panel || text.trim() === "") return
      view.panel.keepAlive()
      view.panel.isolateAdd(text.trim(), "", "")
      text = ""
    }
    onTextChanged: { if (view.panel) view.panel.keepAlive(); resolveTimer.restart() }
  }

  // 300 ms after the last keystroke, not on every one: `resolve` is a stat, but
  // a process per character is still a process per character.
  Timer {
    id: resolveTimer
    interval: 300
    onTriggered: if (view.panel) view.panel.resolveCustom(customField.text.trim())
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: text !== ""
    text: {
      if (!view.panel) return ""
      if (view.panel.configError !== "") return view.panel.configError
      var r = view.panel.resolvePreview
      if (!r || customField.text.trim() === "") return ""
      if (r.blocklisted) return String(r.reason || "that one cannot be isolated")
      if (!r.exists) return "no such path — it will be created per profile on first use"
      var kb = r.kind === "file" ? " · " + (r.size / 1024).toFixed(1) + " KB" : ""
      return "exists · " + r.kind + kb
    }
    color: (view.panel && (view.panel.configError !== ""
            || (view.panel.resolvePreview && view.panel.resolvePreview.blocklisted)))
           ? Color.urgent : view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    // Everything isolated that is not a plugin declaration and not one of the
    // three Hyprland files: the paths someone added by hand.
    model: {
      var out = []
      for (var i = 0; i < view.rows.length; i++)
        if (String(view.rows[i].source) === "custom") out.push(view.rows[i])
      return out
    }

    Item {
      required property var modelData
      width: view.width
      implicitHeight: customLabel.implicitHeight + Style.space(8)

      Text {
        id: customLabel
        anchors.left: parent.left
        anchors.right: removeButton.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: String(modelData.path)
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }

      Button {
        id: removeButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Same as master"
        bordered: true
        foreground: view.dim
        fontFamily: view.fontFamily
        fontSize: Style.font.caption
        onClicked: {
          if (!view.panel) return
          view.panel.keepAlive()
          view.panel.isolateRemove(String(modelData.path))
        }
      }
    }
  }

  PanelSeparator { foreground: view.foreground }

  // ----------------------------------------------------- 5 · every profile

  PanelSectionHeader {
    width: parent.width
    text: "SHARED WORKSPACE"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(globalLabels.implicitHeight, globalSwitch.implicitHeight) + Style.space(6)

    Column {
      id: globalLabels
      anchors.left: parent.left
      anchors.right: globalSwitch.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "A workspace outside every desk"
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: {
          if (!view.globalStatus) return "Music, a download, a long build — things that are not part of any desk."
          if (!view.globalStatus.enabled) return "Music, a download, a long build — things that are not part of any desk."
          var n = view.globalStatus.windows ? view.globalStatus.windows.length : 0
          return "special:" + view.globalStatus.name + " · " + (n === 0 ? "nothing there" : n + (n === 1 ? " window" : " windows"))
        }
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    ToggleSwitch {
      id: globalSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: !!(view.globalStatus && view.globalStatus.enabled)
      foreground: view.foreground
      accent: view.accent
      onToggled: {
        if (!view.panel) return
        view.panel.keepAlive()
        view.panel.runGlobal(globalSwitch.checked ? "disable" : "enable")
      }
    }
  }

  Row {
    width: parent.width
    spacing: Style.space(6)
    visible: !!(view.globalStatus && view.globalStatus.enabled)

    TextField {
      id: globalName
      width: parent.width - renameButton.width - Style.space(6)
      placeholderText: view.globalStatus ? String(view.globalStatus.name || "music") : "music"
      foreground: view.foreground
      accent: view.accent
      font.family: view.fontFamily
      onAccepted: renameButton.clicked()
    }

    Button {
      id: renameButton
      text: "Rename"
      bordered: true
      foreground: view.foreground
      fontFamily: view.fontFamily
      fontSize: Style.font.caption
      onClicked: {
        if (!view.panel || globalName.text.trim() === "") return
        view.panel.keepAlive()
        view.panel.runGlobal("enable " + globalName.text.trim())
        globalName.text = ""
      }
    }
  }

  // Its keys live in the file Setup manages, so this is the same kind of
  // one-click repair a Setup row offers rather than a second mechanism.
  Row {
    width: parent.width
    spacing: Style.space(6)
    visible: !!(view.globalStatus && view.globalStatus.enabled && !view.globalStatus.keysBound)

    Text {
      textFormat: Text.PlainText
      width: parent.width - keysButton.width - Style.space(6)
      wrapMode: Text.WordWrap
      text: "It has no keys yet: nothing toggles it and nothing sends a window there."
      color: view.dim
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }

    Button {
      id: keysButton
      text: "Bind keys"
      bordered: true
      foreground: view.foreground
      fontFamily: view.fontFamily
      fontSize: Style.font.caption
      onClicked: {
        if (!view.panel) return
        view.panel.keepAlive()
        view.panel.runGlobal("keys")
      }
    }
  }

  // ------------------------------------------------------------- components

  component FactRow: Item {
    id: fact
    property string label: ""
    property string value: ""
    width: view.width
    implicitHeight: factValue.implicitHeight + Style.space(4)

    Text {
      id: factLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: fact.label
      color: view.dim
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      id: factValue
      anchors.left: factLabel.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: fact.value
      color: view.foreground
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  // One plugin's own data, and whether every profile gets its own copy.
  //
  // Two plain buttons rather than a switch: "shared" and "per-profile" are two
  // named states a person can recognise, and a bare switch would have to be
  // labelled with one of them anyway.
  component DataRow: Item {
    id: drow
    property var entry: null

    readonly property bool on: !!(drow.entry && drow.entry.isolated)

    implicitHeight: Math.max(dataLabels.implicitHeight, dataButtons.implicitHeight) + Style.space(8)

    Column {
      id: dataLabels
      anchors.left: parent.left
      anchors.right: dataButtons.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: drow.entry ? String(drow.entry.name) : ""
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: drow.entry ? view.shorten(drow.entry.path) : ""
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }
    }

    ScopeChoice {
      id: dataButtons
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      separate: drow.on
      onPicked: function (separate) {
        if (!view.panel || separate === drow.on) return
        view.panel.keepAlive()
        if (separate) view.panel.isolateAdd(String(drow.entry.path), "", "")
        else view.panel.isolateRemove(String(drow.entry.path))
      }
    }
  }

  // "Same as master" or "Separate": the one choice every row on this page
  // offers, in the same words, so no row needs its own legend.
  component ScopeChoice: Row {
    id: scope
    property bool separate: false
    property bool usable: true
    signal picked(bool separate)

    spacing: Style.space(6)
    opacity: scope.usable ? 1 : 0.45

    Button {
      text: "Same as master"
      selected: !scope.separate
      enabled: scope.usable
      foreground: scope.separate ? view.dim : view.accent
      fontFamily: view.fontFamily
      fontSize: Style.font.caption
      onClicked: scope.picked(false)
    }

    Button {
      text: "Separate"
      selected: scope.separate
      enabled: scope.usable
      foreground: scope.separate ? view.accent : view.dim
      fontFamily: view.fontFamily
      fontSize: Style.font.caption
      onClicked: scope.picked(true)
    }
  }

  component LegendRow: Text {
    property string term: ""
    property string meaning: ""
    width: view.width
    textFormat: Text.StyledText
    wrapMode: Text.WordWrap
    text: "<b>" + term + "</b> — " + meaning
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  // One Hyprland file: whether every profile has its own copy of it, and — if
  // this profile's copy broke the config — where that copy was kept.
  component HyprRow: Item {
    id: hrow
    property var entry: null

    readonly property string path: hrow.entry ? "~/.config/hypr/" + hrow.entry.file : ""
    readonly property bool on: view.isolated(hrow.path) !== null
    readonly property var rollback: view.rollbackFor(hrow.path)

    implicitHeight: Math.max(hyprLabels.implicitHeight, hyprSwitch.implicitHeight) + Style.space(8)

    Column {
      id: hyprLabels
      anchors.left: parent.left
      anchors.right: hyprSwitch.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: hrow.entry ? String(hrow.entry.label) : ""
        color: view.hyprUsable ? view.foreground : view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: hrow.entry ? (hrow.entry.blurb + " · " + hrow.entry.file) : ""
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      // The rollback message: only for the file the compositor's error named,
      // so a good override beside a broken one says nothing.
      Text {
        width: parent.width
        visible: !!hrow.rollback
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: {
          if (!hrow.rollback) return ""
          var first = (hrow.rollback.errors && hrow.rollback.errors.length > 0)
                      ? String(hrow.rollback.errors[0]) : ""
          var kept = ""
          for (var i = 0; hrow.rollback.kept && i < hrow.rollback.kept.length; i++)
            if (String(hrow.rollback.kept[i]).indexOf(hrow.entry.file) >= 0) kept = String(hrow.rollback.kept[i])
          return "This profile's copy had errors, so the previous file is in use."
                 + (first === "" ? "" : "\n" + first)
                 + (kept === "" ? "" : "\nYour copy is kept at " + view.shorten(kept))
        }
        color: Color.urgent
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    ScopeChoice {
      id: hyprSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      separate: hrow.on
      // Disabled with the reason above, never silently inert: tier 3 is the
      // one thing here that cannot be proven to work on every machine.
      usable: view.hyprUsable
      onPicked: function (separate) {
        if (!view.panel || !view.hyprUsable || separate === hrow.on) return
        view.panel.keepAlive()
        if (separate) view.panel.isolateAdd(hrow.path, "", "hypr")
        else view.panel.isolateRemove(hrow.path)
      }
    }
  }
}
