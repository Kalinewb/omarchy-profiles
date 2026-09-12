import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// What one profile is allowed to use: applications on one page, plugins on
// another.
//
// Two pages rather than one long column, because they are answers to different
// questions — "what can I launch" and "what does my desktop show" — and mixing
// them meant scrolling past sixty plugins to reach the apps.
//
// Within plugins, the categories are filter buttons at the top rather than
// headings in the list. Headings still require scrolling to find the group you
// want, which is the thing they were supposed to solve.
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
  // Desktop-entry ids this profile may launch. Master ignores it.
  property var allowedApps: []

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  signal runEngine(string args)
  signal touched()

  // "plugins" | "apps"
  property string page: "plugins"
  // "" means every category.
  property string category: ""
  // "" all · "omarchy" first-party only · "addons" third-party only. Separate
  // from the kind filter because "which of my add-ons is this" is a different
  // question from "what kind of thing is it".
  property string source: ""

  spacing: Style.space(10)

  function isDisabled(id) {
    for (var i = 0; i < disabled.length; i++) if (disabled[i] === id) return true
    return false
  }

  function isAllowed(id) {
    if (root.isMaster) return true
    for (var i = 0; i < allowedApps.length; i++) if (allowedApps[i] === id) return true
    return false
  }

  // The recognisable-first order: things you can point at on your own screen
  // before the machinery behind them.
  readonly property var categoryOrder: ["Bar widgets", "Panels", "Overlays", "Services", "Menus", "Bars", "Other"]

  readonly property var categories: {
    var seen = {}
    for (var i = 0; i < plugins.length; i++) seen[String(plugins[i].category || "Other")] = true
    var out = []
    for (var j = 0; j < categoryOrder.length; j++) if (seen[categoryOrder[j]]) out.push(categoryOrder[j])
    for (var k in seen) if (out.indexOf(k) === -1) out.push(k)
    return out
  }

  readonly property var shownPlugins: {
    var out = []
    for (var i = 0; i < plugins.length; i++) {
      var p = plugins[i]
      if (root.category !== "" && String(p.category || "Other") !== root.category) continue
      if (root.source === "omarchy" && !p.firstParty) continue
      if (root.source === "addons" && p.firstParty) continue
      out.push(p)
    }
    return out
  }

  // Every launchable application on the machine. Read straight from
  // DesktopEntries rather than through the engine: it is always current and
  // needs no refresh step.
  readonly property var allApps: {
    var out = []
    var values = DesktopEntries.applications.values || []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e || e.noDisplay) continue
      out.push({ id: String(e.id || ""), name: String(e.name || e.id || "") })
    }
    out.sort(function (a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1 })
    return out
  }

  // ------------------------------------------------------------- page chips

  Row {
    width: parent.width
    spacing: Style.space(6)

    Button {
      text: "Plugins"
      selected: root.page === "plugins"
      foreground: root.page === "plugins" ? root.accent : root.dim
      fontFamily: root.fontFamily
      onClicked: { root.touched(); root.page = "plugins" }
    }

    Button {
      text: "Apps"
      selected: root.page === "apps"
      foreground: root.page === "apps" ? root.accent : root.dim
      fontFamily: root.fontFamily
      onClicked: { root.touched(); root.page = "apps" }
    }
  }

  Text {
    width: parent.width
    visible: root.isMaster
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: "The master sees everything, so there is nothing to restrict here."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  // ----------------------------------------------------------- plugins page

  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: root.page === "plugins" && !root.isMaster

    Row {
      width: parent.width
      spacing: Style.space(4)

      Button {
        text: "Everything"
        selected: root.source === ""
        foreground: root.source === "" ? root.accent : root.dim
        fontFamily: root.fontFamily
        onClicked: { root.touched(); root.source = "" }
      }

      Button {
        text: "Omarchy"
        selected: root.source === "omarchy"
        foreground: root.source === "omarchy" ? root.accent : root.dim
        fontFamily: root.fontFamily
        onClicked: { root.touched(); root.source = "omarchy" }
      }

      Button {
        text: "Add-ons"
        selected: root.source === "addons"
        foreground: root.source === "addons" ? root.accent : root.dim
        fontFamily: root.fontFamily
        onClicked: { root.touched(); root.source = "addons" }
      }
    }

    // Categories as buttons, so picking a group is one click rather than a
    // hunt through headings.
    Flow {
      width: parent.width
      spacing: Style.space(4)

      Button {
        text: "All"
        selected: root.category === ""
        foreground: root.category === "" ? root.accent : root.dim
        fontFamily: root.fontFamily
        onClicked: { root.touched(); root.category = "" }
      }

      Repeater {
        model: root.categories

        Button {
          required property var modelData
          text: String(modelData)
          selected: root.category === String(modelData)
          foreground: root.category === String(modelData) ? root.accent : root.dim
          fontFamily: root.fontFamily
          onClicked: { root.touched(); root.category = String(modelData) }
        }
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Button {
        // Scoped to what is on screen, so "all" from a filtered view means the
        // filter rather than the whole machine.
        text: root.category === "" ? "Enable all" : "Enable all " + root.category.toLowerCase()
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          root.touched()
          root.runEngine("plugin " + root.profile + " enable-all" + (root.category === "" ? "" : " " + JSON.stringify(root.category)))
        }
      }

      Button {
        text: root.category === "" ? "Disable all" : "Disable all " + root.category.toLowerCase()
        foreground: root.dim
        fontFamily: root.fontFamily
        onClicked: {
          root.touched()
          root.runEngine("plugin " + root.profile + " disable-all" + (root.category === "" ? "" : " " + JSON.stringify(root.category)))
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.shownPlugins.length + (root.shownPlugins.length === 1 ? " plugin" : " plugins")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.shownPlugins

      PluginToggleRow {
        required property var modelData
        width: root.width
        plugin: modelData
      }
    }
  }

  // -------------------------------------------------------------- apps page

  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: root.page === "apps" && !root.isMaster

    // Honest about the gap: the list is real and the choices are saved, but
    // nothing filters the launcher on them yet.
    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "Choices here are saved to the profile, but not enforced yet — the launcher still shows every app until it filters on the active profile."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Button {
        text: "Allow all"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: { root.touched(); root.runEngine("apps " + root.profile + " allow-all") }
      }

      Button {
        text: "Allow none"
        foreground: root.dim
        fontFamily: root.fontFamily
        onClicked: { root.touched(); root.runEngine("apps " + root.profile + " deny-all") }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.allowedApps.length + " of " + root.allApps.length + " allowed"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.allApps

      AppToggleRow {
        required property var modelData
        width: root.width
        app: modelData
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

      // What the thing actually does. A list of bare names tells you nothing
      // about what switching one off will cost you, which is the whole reason
      // to read this screen.
      Text {
        width: nameCol.width
        visible: text !== ""
        textFormat: Text.PlainText
        text: prow.plugin ? String(prow.plugin.description || "") : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        // Two lines: enough for the sentence most authors write, without one
        // verbose README paragraph pushing the rest of the list off screen.
        maximumLineCount: 2
        elide: Text.ElideRight
      }

      Text {
        width: nameCol.width
        visible: prow.pinned || !!(prow.plugin && prow.plugin.firstParty)
        textFormat: Text.PlainText
        text: prow.pinned ? "Pinned — switching this off would leave no way back"
                          : "An Omarchy default"
        color: prow.pinned ? root.accent : root.dim
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
      interactive: !prow.locked
      foreground: root.foreground
      accent: root.accent
      onToggled: {
        if (prow.locked) return
        root.touched()
        root.runEngine("plugin " + root.profile + (prow.on ? " disable " : " enable ") + prow.pid)
      }
    }
  }

  // One application: its name, and whether this profile may launch it.
  component AppToggleRow: Item {
    id: arow
    property var app: null

    readonly property string aid: arow.app ? String(arow.app.id || "") : ""
    readonly property bool on: root.isAllowed(arow.aid)

    implicitHeight: Math.max(appName.implicitHeight, asw.implicitHeight) + Style.space(6)

    Text {
      id: appName
      anchors.left: parent.left
      anchors.right: asw.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: arow.app ? String(arow.app.name || arow.aid) : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    ToggleSwitch {
      id: asw
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: arow.on
      foreground: root.foreground
      accent: root.accent
      onToggled: {
        root.touched()
        root.runEngine("apps " + root.profile + (arow.on ? " deny " : " allow ") + arow.aid)
      }
    }
  }
}
