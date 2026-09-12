import QtQuick
import qs.Commons
import qs.Ui

// What one profile is allowed to use.
//
// Plugins are grouped by what they are — bar widgets, panels, services,
// overlays — because a flat list of sixty ids is unreadable and the grouping is
// the only thing that tells you what switching one off will actually change.
//
// A toggle records the choice in the profile and, when that profile is the
// active one, applies it to the running shell in the same step. Recording
// without applying would be worse than doing nothing: the next switch captures
// live state over the edit and it disappears.
Column {
  id: root

  property string profile: ""
  property bool isMaster: false
  property var plugins: []
  // Plugin ids this profile has switched off.
  property var disabled: []

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  signal runEngine(string args)
  signal touched()

  spacing: Style.space(10)

  function isDisabled(id) {
    for (var i = 0; i < disabled.length; i++) if (disabled[i] === id) return true
    return false
  }

  // The categories present in the catalog, in a deliberate order: the ones a
  // person recognises from looking at their screen come first.
  readonly property var categoryOrder: ["Bar widgets", "Panels", "Overlays", "Services", "Menus", "Bars", "Other"]

  readonly property var categories: {
    var seen = {}
    for (var i = 0; i < plugins.length; i++) {
      var c = String(plugins[i].category || "Other")
      seen[c] = true
    }
    var out = []
    for (var j = 0; j < categoryOrder.length; j++) if (seen[categoryOrder[j]]) out.push(categoryOrder[j])
    for (var k in seen) if (out.indexOf(k) === -1) out.push(k)
    return out
  }

  function pluginsIn(category) {
    var out = []
    for (var i = 0; i < plugins.length; i++) {
      if (String(plugins[i].category || "Other") === category) out.push(plugins[i])
    }
    return out
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: root.isMaster
      ? "The master sees everything, so there is nothing to restrict here."
      : "Switch off what this profile should not have. Changes are saved to the profile; if you are in it now, they apply immediately."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  // ------------------------------------------------------------------- apps

  Column {
    width: parent.width
    spacing: Style.space(4)

    PanelSectionHeader {
      width: parent.width
      text: "APPLICATIONS"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    // Said plainly rather than shown as a list of switches that do nothing:
    // hiding an app needs the launcher to filter on the active profile, and
    // that part is not built yet.
    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "Not yet. Per-profile app visibility needs the launcher to filter on the active profile — until that lands, every profile sees every app."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // ---------------------------------------------------------------- plugins

  Repeater {
    model: root.categories

    Column {
      required property var modelData
      width: root.width
      spacing: Style.space(2)

      PanelSectionHeader {
        width: parent.width
        text: String(modelData).toUpperCase()
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: root.pluginsIn(modelData)

        PluginToggleRow {
          required property var modelData
          width: root.width
          plugin: modelData
        }
      }
    }
  }

  // One plugin: its name, and whether this profile may use it.
  component PluginToggleRow: Item {
    id: prow
    property var plugin: null

    readonly property string pid: prow.plugin ? String(prow.plugin.id || "") : ""
    readonly property bool pinned: !!(prow.plugin && prow.plugin.pinned)
    readonly property bool locked: prow.pinned || !!(prow.plugin && prow.plugin.canDisable === false)
    readonly property bool on: !root.isDisabled(prow.pid)

    implicitHeight: Math.max(nameCol.implicitHeight, sw.implicitHeight) + Style.space(6)

    Column {
      id: nameCol
      anchors.left: parent.left
      anchors.right: sw.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        width: nameCol.width
        textFormat: Text.PlainText
        text: prow.plugin ? String(prow.plugin.name || prow.pid) : ""
        color: prow.locked ? root.dim : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: nameCol.width
        visible: prow.pinned
        textFormat: Text.PlainText
        // The picker is pinned for a concrete reason, so say it rather than
        // leaving a greyed-out switch unexplained.
        text: "Pinned — switching this off would leave no way back"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    ToggleSwitch {
      id: sw
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: prow.on
      interactive: !prow.locked && !root.isMaster
      foreground: root.foreground
      accent: root.accent
      onToggled: {
        if (prow.locked || root.isMaster) return
        root.touched()
        root.runEngine("plugin " + root.profile + (prow.on ? " disable " : " enable ") + prow.pid)
      }
    }
  }
}
