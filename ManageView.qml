import QtQuick
import qs.Commons
import qs.Ui

// The manage view: every profile with its inline actions, plus the form that
// creates a new one.
//
// Actions do not mutate anything here. Each one calls the engine and lets the
// index file come back changed — the same path a terminal invocation takes, so
// there is exactly one implementation of "create a profile" and the panel
// cannot drift from it.
Column {
  id: root

  // Supplied by the panel rather than reached for, so this file has no opinion
  // about where it is mounted.
  property var profiles: []
  property string currentProfile: ""
  property string masterName: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family
  property bool cursorActive: false
  property int cursor: 0

  signal runEngine(string args)
  signal openSettings(string profile)
  signal cursorMoved(int index)

  // Which profile the remove confirmation is about. Empty means closed.
  property string pendingRemoval: ""
  property bool creating: false
  property bool createFromMaster: true

  spacing: Style.space(8)

  function isMaster(name) { return name === root.masterName }

  PanelSectionHeader {
    width: parent.width
    text: "PROFILES"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.profiles

    ProfileManageRow {
      required property var modelData
      required property int index
      width: root.width
      entry: modelData
      rowIndex: index
    }
  }

  PanelSeparator { foreground: root.foreground }

  // ---------------------------------------------------------------- create

  Item {
    width: parent.width
    implicitHeight: newButton.implicitHeight
    visible: !root.creating

    PanelActionButton {
      id: newButton
      anchors.left: parent.left
      iconText: "󰐕"
      tooltipText: "New profile"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: { root.creating = true; Qt.callLater(function () { nameField.forceActiveFocus() }) }
    }

    Text {
      anchors.left: newButton.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: newButton.verticalCenter
      textFormat: Text.PlainText
      text: "New profile"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: root.creating

    TextField {
      id: nameField
      width: parent.width
      placeholderText: "Name (letters, digits, - and _)"
      foreground: root.foreground
      accent: root.accent
      font.family: root.fontFamily
      // Enter creates; the engine refuses a bad name, so no validation here
      // that could disagree with it.
      onAccepted: root.submitCreate()
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Button {
        text: "Copy of " + (root.masterName === "" ? "master" : root.masterName)
        foreground: root.createFromMaster ? root.accent : root.dim
        fontFamily: root.fontFamily
        onClicked: root.createFromMaster = true
      }

      Button {
        text: "Clean"
        foreground: root.createFromMaster ? root.dim : root.accent
        fontFamily: root.fontFamily
        onClicked: root.createFromMaster = false
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: root.createFromMaster
        ? "Starts with everything the master can see, as a snapshot — later installs into master will not appear here on their own."
        : "Starts with nothing. You choose every app and plugin it may use."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      spacing: Style.space(6)

      Button {
        text: "Create"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.submitCreate()
      }

      Button {
        text: "Cancel"
        foreground: root.dim
        fontFamily: root.fontFamily
        onClicked: { root.creating = false; nameField.text = "" }
      }
    }
  }

  function submitCreate() {
    var name = String(nameField.text || "").trim()
    if (name === "") return
    root.runEngine("create " + name + (root.createFromMaster ? " --from-master" : " --clean"))
    nameField.text = ""
    root.creating = false
  }

  ConfirmDialog {
    id: removeDialog
    anchors.fill: parent
    opened: root.pendingRemoval !== ""
    // Named plainly: this deletes a saved desk, and its windows are the thing
    // a person will actually miss.
    message: "Remove the profile \"" + root.pendingRemoval + "\"?\n\nIts saved theme, bar and app list are deleted. Any windows still open on its workspaces are left where they are."
    confirmText: "Remove"
    cancelText: "Keep"
    foreground: root.foreground
    fontFamily: root.fontFamily
    onCanceled: root.pendingRemoval = ""
    onConfirmed: {
      root.runEngine("remove " + root.pendingRemoval)
      root.pendingRemoval = ""
    }
  }

  // One profile: name, what it is, and the actions that apply to it. Master
  // and the active profile lose the actions that would strand the user.
  component ProfileManageRow: CursorSurface {
    id: row
    property var entry: null
    property int rowIndex: 0

    readonly property string name: row.entry ? String(row.entry.id || "") : ""
    readonly property bool master: root.isMaster(row.name)
    readonly property bool active: row.name === root.currentProfile

    foreground: root.foreground
    accent: root.accent
    hasCursor: root.cursorActive && root.cursor === row.rowIndex
    current: row.active

    implicitHeight: rowBody.implicitHeight + Style.space(14)

    Item {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      implicitHeight: Math.max(labels.implicitHeight, actions.implicitHeight)

      Column {
        id: labels
        anchors.left: parent.left
        anchors.right: actions.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Row {
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            text: row.entry ? String(row.entry.icon || "󰆼") : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            textFormat: Text.PlainText
            text: row.entry ? String(row.entry.label || row.name) : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: row.active
          }

          Text {
            textFormat: Text.PlainText
            visible: row.master
            text: "master"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          textFormat: Text.PlainText
          width: labels.width
          text: row.entry ? String(row.entry.blurb || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        PanelActionButton {
          iconText: "󰒓"
          tooltipText: "Apps and plugins for " + row.name
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.openSettings(row.name)
          onHovered: function (h) { if (h) root.cursorMoved(row.rowIndex) }
        }

        PanelActionButton {
          // Hiding only affects the picker; the profile and its windows stay.
          iconText: (row.entry && row.entry.hidden) ? "󰛐" : "󰛑"
          tooltipText: (row.entry && row.entry.hidden) ? "Show in the picker" : "Hide from the picker"
          foreground: root.foreground
          fontFamily: root.fontFamily
          // Hiding the one you are in, or the master, leaves no way back.
          enabled: !row.master && !row.active
          onClicked: root.runEngine(((row.entry && row.entry.hidden) ? "show " : "hide ") + row.name)
          onHovered: function (h) { if (h) root.cursorMoved(row.rowIndex) }
        }

        PanelActionButton {
          iconText: "󰩹"
          tooltipText: row.master ? "The master profile cannot be removed"
                     : (row.active ? "Switch away before removing this profile" : "Remove " + row.name)
          foreground: root.foreground
          hoverColor: Color.urgent
          fontFamily: root.fontFamily
          enabled: !row.master && !row.active
          onClicked: root.pendingRemoval = row.name
          onHovered: function (h) { if (h) root.cursorMoved(row.rowIndex) }
        }
      }
    }

    HoverHandler {
      onHoveredChanged: if (hovered) root.cursorMoved(row.rowIndex)
    }
  }
}
