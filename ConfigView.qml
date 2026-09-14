import QtQuick
import qs.Commons
import qs.Ui

// Configuration: what a profile is, and what is allowed to differ between
// profiles.
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
    text: "THIS DESK"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: "These are what a profile is. They are always its own."
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

  PanelSeparator { foreground: view.foreground }

  // --------------------------------------------------------- 2 · plugin data

  PanelSectionHeader {
    width: parent.width
    text: "PLUGIN DATA"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Changes here apply to every profile."
    color: view.accent
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
    wrapMode: Text.WordWrap
    text: "Per-profile: every desk keeps its own copy — each signs in separately."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  PanelSeparator { foreground: view.foreground }

  // ------------------------------------------------------------ 3 · Hyprland

  PanelSectionHeader {
    width: parent.width
    text: "HYPRLAND"
    foreground: view.foreground
    fontFamily: view.fontFamily
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
    text: "Applies live with hyprctl reload, which also re-runs startup commands that are not marked once and resets settings changed on the fly."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: "monitors.lua, hyprmoncfg-monitors.lua and profiles-keys.lua are not offered: hardware and Setup-managed files stay shared."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  PanelSeparator { foreground: view.foreground }

  // --------------------------------------------------------- 4 · custom path

  PanelSectionHeader {
    width: parent.width
    text: "ANY OTHER FILE"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  Dropdown {
    width: parent.width
    visible: view.candidates.length > 0
    label: "Known files"
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
        // A star on the one the active profile is using right now, the same
        // mark `isolate list` prints in a terminal.
        text: (modelData.active ? "* " : "  ") + String(modelData.path)
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }

      Button {
        id: removeButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Shared again"
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
    text: "EVERY PROFILE"
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
        text: drow.entry ? String(drow.entry.path) : ""
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }
    }

    Row {
      id: dataButtons
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Button {
        text: "Shared"
        selected: !drow.on
        foreground: drow.on ? view.dim : view.accent
        fontFamily: view.fontFamily
        fontSize: Style.font.caption
        onClicked: {
          if (!view.panel || !drow.on) return
          view.panel.keepAlive()
          view.panel.isolateRemove(String(drow.entry.path))
        }
      }

      Button {
        text: "Per-profile"
        selected: drow.on
        foreground: drow.on ? view.accent : view.dim
        fontFamily: view.fontFamily
        fontSize: Style.font.caption
        onClicked: {
          if (!view.panel || drow.on) return
          view.panel.keepAlive()
          view.panel.isolateAdd(String(drow.entry.path), "", "")
        }
      }
    }
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

    ToggleSwitch {
      id: hyprSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: hrow.on
      // Disabled with the reason above, never silently inert: tier 3 is the
      // one thing here that cannot be proven to work on every machine.
      interactive: view.hyprUsable
      opacity: view.hyprUsable ? 1 : 0.45
      foreground: view.foreground
      accent: view.accent
      onToggled: {
        if (!view.panel || !view.hyprUsable) return
        view.panel.keepAlive()
        if (hrow.on) view.panel.isolateRemove(hrow.path)
        else view.panel.isolateAdd(hrow.path, "", "hypr")
      }
    }
  }
}
