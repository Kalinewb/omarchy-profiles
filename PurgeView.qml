import QtQuick
import qs.Commons
import qs.Ui

// Removing the plugin: the confirmation, and the two buttons.
//
// Everything on this page is `purge --dry-run --json`, rendered. Nothing here
// knows what a purge removes — if the engine grows a step, its manifest grows a
// field and this lists it; if it loses one, this stops listing it. A second
// description of "what will be deleted", maintained here, is exactly the kind
// that goes quietly out of date and then lies to somebody at the one moment it
// matters.
//
// One rule the layout exists to enforce: nothing is removed until Remove is
// pressed, and off master there is no Remove to press.
Column {
  id: view

  property var panel: null

  readonly property color foreground: panel ? panel.foreground : Color.foreground
  readonly property color accent: panel ? panel.accent : Color.accent
  readonly property color dim: panel ? panel.dim : Color.muted
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family

  readonly property var m: (panel && panel.purgeManifest) ? panel.purgeManifest : null
  readonly property string outcome: panel ? panel.purgeState : ""
  readonly property bool onMaster: !!panel && panel.purgeOnMaster
  readonly property string masterName: view.m ? String(view.m.master || "") : (panel ? panel.masterName : "")

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(10)

  function kb(bytes) {
    var b = Number(bytes || 0)
    if (b < 1024) return b + " B"
    if (b < 1024 * 1024) return (b / 1024).toFixed(1) + " kB"
    return (b / 1048576).toFixed(1) + " MB"
  }

  function baseName(path) {
    var p = String(path || "")
    var i = p.lastIndexOf("/")
    return i >= 0 ? p.slice(i + 1) : p
  }

  // The stores, grouped by the profile they belong to — which is how a person
  // thinks about them ("work's looknfeel.lua"), not how they are stored.
  readonly property var groups: {
    var out = []
    var byName = ({})
    var stores = (view.m && Array.isArray(view.m.stores)) ? view.m.stores : []
    for (var i = 0; i < stores.length; i++) {
      var s = stores[i]
      var name = String(s.profile || "")
      if (byName[name] === undefined) {
        byName[name] = out.length
        out.push({ profile: name, files: [] })
      }
      out[byName[name]].files.push(s)
    }
    return out
  }

  // ------------------------------------------------------------- the asking

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: view.outcome !== "ok"
    text: {
      if (!view.panel) return ""
      if (view.outcome === "") return "Working out what is here…"
      return "Could not read what is installed (" + view.outcome + ")."
    }
    color: view.outcome === "" ? view.dim : Color.urgent
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
  }

  // ------------------------------------------------------------ what it does

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: view.outcome === "ok"
    text: "This removes Profiles from the machine and hands the desktop back as "
          + (view.masterName === "" ? "the master profile" : view.masterName)
          + " has it: its theme, its bar, its plugins, every application visible again. "
          + "The other profiles and everything saved in them are deleted."
    color: view.foreground
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
  }

  // ------------------------------------------------------------- the windows

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: view.outcome === "ok" && !!view.m && Number(view.m.windows_to_move || 0) > 0
    text: {
      var n = view.m ? Number(view.m.windows_to_move || 0) : 0
      return n + (n === 1 ? " window moves" : " windows move") + " onto "
             + (view.masterName === "" ? "the master profile" : view.masterName)
             + "'s workspaces first — nothing is closed, and nothing is left where the keys cannot reach it."
    }
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  // --------------------------------------------------------------- the files

  PanelSectionHeader {
    width: parent.width
    visible: view.outcome === "ok" && view.groups.length > 0
    text: "SAVED SETTINGS THAT WILL BE DELETED"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  Repeater {
    model: view.outcome === "ok" ? view.groups : []

    Column {
      required property var modelData
      width: view.width
      spacing: 0

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: String(modelData.profile)
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: modelData.files

        Text {
          required property var modelData
          textFormat: Text.PlainText
          width: view.width
          wrapMode: Text.WordWrap
          // Named, not counted. A tier-3 file is this profile's own Hyprland
          // configuration and exists nowhere else on the machine, so "work's
          // looknfeel.lua" is the whole point of showing this list at all.
          text: {
            var extra = Array.isArray(modelData.extra) ? modelData.extra : []
            var tail = extra.length > 0 ? "  (and " + extra.join(", ") + ")" : ""
            return "    " + view.baseName(modelData.path) + " · " + view.kb(modelData.bytes)
                   + (Number(modelData.tier) === 3 ? " · Hyprland settings" : "")
                   + tail
          }
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ----------------------------------------------------------- the rest of it

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: view.outcome === "ok" && text !== ""
    text: {
      if (!view.m) return ""
      var parts = []
      var a = view.m.apps || {}
      var hidden = Number(a.hidden || 0) + Number(a.modified || 0)
      if (hidden > 0) parts.push(hidden + (hidden === 1 ? " hidden application comes back into the menu"
                                                        : " hidden applications come back into the menu"))
      if (Number(a.edited_while_hidden || 0) > 0)
        parts.push(Number(a.edited_while_hidden) + " of them you have edited since — your edits are kept")
      var n = Number(view.m.sessions || 0)
      if (n > 0) parts.push(n + (n === 1 ? " record of what was open" : " records of what was open"))
      var orph = Array.isArray(view.m.orphaned) ? view.m.orphaned.length : 0
      if (orph > 0) parts.push(orph + (orph === 1 ? " file set aside earlier" : " files set aside earlier"))
      var root = view.m.root || {}
      if (Number(root.passwords || 0) > 0)
        parts.push(Number(root.passwords) + (Number(root.passwords) === 1 ? " stored password" : " stored passwords"))
      if (Number(root.identities || 0) > 0)
        parts.push(Number(root.identities) + " face binding")
      if (root.helpers || root.policy) parts.push("the two password helpers and their system permissions")
      if (view.m.keys && view.m.keys.managed_file) parts.push("the workspace keys file and the line that loads it")
      return parts.length === 0 ? "" : "Also: " + parts.join(" · ") + "."
    }
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  // Held paths: files a failed rotation left in place. They are not deleted,
  // and saying so is the point — someone reading this list has to know which of
  // their files survive.
  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: view.outcome === "ok" && !!view.m
             && Array.isArray(view.m.pending_owner) && view.m.pending_owner.length > 0
    text: {
      var p = (view.m && Array.isArray(view.m.pending_owner)) ? view.m.pending_owner : []
      return "Left exactly where they are, because a switch could not file them: " + p.join(", ") + "."
    }
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  // ------------------------------------------------------- the keys you wrote

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: view.outcome === "ok" && !!view.m && !!view.m.keys
             && Array.isArray(view.m.keys.hand_written) && view.m.keys.hand_written.length > 0
    // Shown and not fixed, deliberately: this is the user's own configuration,
    // which this plugin does not edit. After a purge it calls a script that is
    // gone, so it is the one thing they have to do themselves.
    text: {
      var h = (view.m && view.m.keys && Array.isArray(view.m.keys.hand_written)) ? view.m.keys.hand_written : []
      return "You bind workspace keys by hand in " + h.join(", ")
             + ". That block calls this plugin, so after it is removed those keys stop working — take it out yourself; nothing here will edit your configuration."
    }
    color: Color.urgent
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  // -------------------------------------------------------------- the widget

  Item {
    width: parent.width
    visible: view.outcome === "ok" && !!view.m && String(view.m.indicator || "") !== ""
    implicitHeight: Math.max(indicatorLabels.implicitHeight, indicatorSwitch.implicitHeight) + Style.space(6)

    Column {
      id: indicatorLabels
      anchors.left: parent.left
      anchors.right: indicatorSwitch.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Keep the workspace widget"
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: {
          var id = view.m ? String(view.m.indicator || "") : ""
          return "'" + id + "' is a copy of Omarchy's own workspace widget, made for this plugin. Off: it is removed and Omarchy's own goes back on the bar."
        }
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    ToggleSwitch {
      id: indicatorSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: !!view.panel && view.panel.purgeKeepIndicator
      foreground: view.foreground
      accent: view.accent
      onToggled: {
        if (!view.panel) return
        view.panel.keepAlive()
        view.panel.purgeKeepIndicator = !view.panel.purgeKeepIndicator
      }
    }
  }

  PanelSeparator { foreground: view.foreground; visible: view.outcome === "ok" }

  // ---------------------------------------------------------- export first

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: view.outcome === "ok"
    text: "Copy it all somewhere first. Nothing is removed by this."
    color: view.foreground
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  TextField {
    id: exportField
    width: parent.width
    visible: view.outcome === "ok"
    text: view.panel ? view.panel.purgeExportDir : ""
    placeholderText: "~/omarchy-profiles-export"
    foreground: view.foreground
    accent: view.accent
    font.family: view.fontFamily
    onAccepted: if (view.panel) { view.panel.keepAlive(); view.panel.purgeExport(text) }
    onTextChanged: if (view.panel) view.panel.keepAlive()
  }

  Row {
    width: parent.width
    visible: view.outcome === "ok"
    spacing: Style.space(6)

    Button {
      text: (view.panel && view.panel.purgeExported) ? "Export again" : "Export first"
      bordered: true
      enabled: !!view.panel && !view.panel.purgeBusy
      foreground: view.foreground
      fontFamily: view.fontFamily
      fontSize: Style.font.caption
      onClicked: {
        if (!view.panel) return
        view.panel.keepAlive()
        view.panel.purgeExport(exportField.text)
      }
    }

    // On master: the irreversible one. Off it: the only thing that can be done
    // from here, because a switch restarts the shell and this panel with it.
    Button {
      visible: view.onMaster
      text: "Remove"
      bordered: true
      enabled: !!view.panel && !view.panel.purgeBusy
      foreground: Color.urgent
      fontFamily: view.fontFamily
      fontSize: Style.font.caption
      onClicked: {
        if (!view.panel) return
        view.panel.keepAlive()
        view.panel.purgeRemove()
      }
    }

    Button {
      visible: !view.onMaster
      text: "Switch to " + (view.masterName === "" ? "master" : view.masterName) + " first"
      bordered: true
      foreground: view.foreground
      fontFamily: view.fontFamily
      fontSize: Style.font.caption
      onClicked: {
        if (!view.panel) return
        view.panel.keepAlive()
        view.panel.purgeSwitchToMaster()
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: view.outcome === "ok" && !view.onMaster
    text: "Removing puts the machine back as " + (view.masterName === "" ? "the master profile" : view.masterName)
          + " has it, so it has to be the profile you are in. Switching restarts the shell — open this again afterwards."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: !!view.panel && view.panel.purgeNote !== ""
    text: view.panel ? view.panel.purgeNote : ""
    color: view.accent
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: !!view.panel && view.panel.purgeError !== ""
    text: view.panel ? view.panel.purgeError : ""
    color: Color.urgent
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }
}
