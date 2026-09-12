import QtQuick
import qs.Commons
import qs.Ui

// What every profile is holding open.
//
// Profiles persist by design — switching away kills nothing, which is what
// makes "I am working, now I want to game" safe to do without thinking. The
// cost is that several profiles can quietly be holding several browsers, and
// the only defence is being able to see it before you wonder where the memory
// went.
//
// The numbers come from the engine, which attributes windows by workspace and
// reads memory from each window's cgroup. Both matter: attribution by workspace
// counts a terminal you opened by hand exactly like one a profile switch
// opened, and cgroup memory is real accounting rather than a guess.
Column {
  id: root

  property var rows: []
  property string currentProfile: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  signal runEngine(string args)
  signal confirmClose(string profile)
  signal touched()

  spacing: Style.space(6)

  function human(bytes) {
    var b = Number(bytes) || 0
    if (b >= 1073741824) return (Math.round(b / 1073741824 * 10) / 10) + " GB"
    if (b >= 1048576) return Math.round(b / 1048576) + " MB"
    return "—"
  }

  readonly property real totalMemory: {
    var t = 0
    for (var i = 0; i < rows.length; i++) t += Number(rows[i].memory) || 0
    return t
  }

  readonly property int totalWindows: {
    var n = 0
    for (var i = 0; i < rows.length; i++) n += Number(rows[i].windows) || 0
    return n
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: root.rows.length === 0
      ? "Nothing measured yet."
      : root.totalWindows + (root.totalWindows === 1 ? " window" : " windows")
        + " open across every profile, using " + root.human(root.totalMemory) + "."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root.rows

    OverviewRow {
      required property var modelData
      width: root.width
      entry: modelData
    }
  }

  // One profile: what it holds, and the one action worth having here.
  component OverviewRow: CursorSurface {
    id: orow
    property var entry: null

    readonly property string name: orow.entry ? String(orow.entry.profile || "") : ""
    readonly property bool active: !!(orow.entry && orow.entry.active)
    readonly property int windows: orow.entry ? (Number(orow.entry.windows) || 0) : 0
    // The catch-all row for workspaces outside every block. It is not a profile,
    // so it cannot be switched to or closed as one.
    readonly property bool real: orow.entry && orow.entry.offset !== null && orow.entry.offset !== undefined

    property bool hovered: false

    foreground: root.foreground
    accent: root.accent
    hasCursor: orow.hovered
    current: orow.active

    implicitHeight: obody.implicitHeight + Style.space(12)

    Item {
      id: obody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      implicitHeight: Math.max(otext.implicitHeight, oactions.implicitHeight)

      Column {
        id: otext
        anchors.left: parent.left
        anchors.right: oactions.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Row {
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            text: orow.name
            color: orow.real ? (orow.active ? root.accent : root.foreground) : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: orow.active
          }

          Text {
            textFormat: Text.PlainText
            text: orow.windows === 0 ? "empty"
                  : orow.windows + (orow.windows === 1 ? " window · " : " windows · ")
                    + root.human(orow.entry.memory)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          width: otext.width
          textFormat: Text.PlainText
          visible: text !== ""
          // The app names are the useful part: "6 GB" prompts the question,
          // "chromium, foot x3, steam" answers it.
          text: {
            if (!orow.entry || !orow.entry.apps) return ""
            var out = []
            for (var i = 0; i < orow.entry.apps.length; i++) {
              var a = orow.entry.apps[i]
              out.push(String(a.class) + (a.count > 1 ? " ×" + a.count : ""))
            }
            return out.join(", ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        id: oactions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        PanelActionButton {
          visible: orow.real && !orow.active
          iconText: "󰁔"
          tooltipText: "Switch to " + orow.name
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: { root.touched(); root.runEngine("set " + orow.name) }
        }

        PanelActionButton {
          visible: orow.real && orow.windows > 0
          iconText: "󰅖"
          tooltipText: "Ask the " + orow.windows + " window(s) in " + orow.name + " to close"
          foreground: root.foreground
          hoverColor: Color.urgent
          fontFamily: root.fontFamily
          onClicked: { root.touched(); root.confirmClose(orow.name) }
        }
      }
    }

    HoverHandler {
      onHoveredChanged: orow.hovered = hovered
    }
  }
}
