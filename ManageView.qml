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
  // The panel owns the confirmation dialog; a Column cannot host one.
  signal confirmRemove(string profile)
  signal openOverview()
  // The panel owns the password prompt for the same reason, and it is the only
  // thing that ever holds a typed secret.
  signal passwordAction(string profile, string mode)
  signal createProfile(string name, bool fromMaster)

  // Which row has its password controls open. One at a time: they are a second
  // line of buttons, and two open at once reads as one row's controls belonging
  // to the other.
  property string passwordRow: ""
  // What the engine said about the last create attempt, if anything.
  property string createError: ""

  // How many profiles the picker currently offers. Hiding the last one is
  // refused, so the button is disabled rather than failing after the click.
  property int visibleCount: 0

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

  // The way to the overview. Here rather than in the picker, because "what is
  // everything holding open" is a housekeeping question, and this is the
  // housekeeping screen.
  CursorSurface {
    id: overviewRow
    width: parent.width
    property bool hovered: false
    foreground: root.foreground
    accent: root.accent
    hasCursor: overviewRow.hovered
    implicitHeight: overviewBody.implicitHeight + Style.space(14)

    Row {
      id: overviewBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: "󰓠"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: "What is open"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    HoverHandler { onHoveredChanged: overviewRow.hovered = hovered }
    TapHandler { onTapped: root.openOverview() }
  }

  PanelSeparator { foreground: root.foreground }

  // ---------------------------------------------------------------- create

  // A row, not an icon with a caption beside it: the whole strip is the target,
  // and it hovers like the profile rows above so it reads as one more row in
  // the same list rather than a stray button.
  CursorSurface {
    id: newRow
    width: parent.width
    visible: !root.creating

    foreground: root.foreground
    accent: root.accent
    hasCursor: newRow.hovered

    property bool hovered: false

    implicitHeight: newRowBody.implicitHeight + Style.space(14)

    Row {
      id: newRowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: "󰐕"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: "New profile"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    HoverHandler {
      onHoveredChanged: newRow.hovered = hovered
    }

    TapHandler {
      onTapped: {
        root.creating = true
        Qt.callLater(function () { nameField.forceActiveFocus() })
      }
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

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      visible: root.createError !== ""
      text: root.createError
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
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
        ? "A snapshot of the master: the same apps, plugins and plugin data — already signed in to Spotify, same dock. Later installs into master will not appear here on their own."
        : "Starts with nothing: no apps, only Omarchy's own plugins, and every plugin makes fresh state — signed out, default dock."
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
    // Through the panel's ask(), not runEngine(): creating can be refused with
    // `stale_password` — a hash left behind by a deleted profile of this name —
    // and a fire-and-forget call has no way to hear that.
    root.createProfile(name, root.createFromMaster)
    nameField.text = ""
    root.creating = false
  }

  // NOTE: the remove confirmation is NOT here. A Column child may not use
  // anchors — QML refuses it — and an unanchored ConfirmDialog was laid out as
  // an ordinary row, so it took the whole panel and showed as a blank page.
  // The panel hosts the dialog instead and drives it through `confirmRemove`.

  // One profile: name, what it is, and the actions that apply to it. Master
  // and the active profile lose the actions that would strand the user.
  component ProfileManageRow: CursorSurface {
    id: row
    property var entry: null
    property int rowIndex: 0

    readonly property string name: row.entry ? String(row.entry.id || "") : ""
    // From the index entry, not a name comparison: the flag travels with the
    // row, so it cannot desync from a masterName that arrived late or empty.
    readonly property bool master: !!(row.entry && row.entry.master)
    readonly property bool active: row.name === root.currentProfile
    // Visible now and the only one left: hiding it would empty the picker.
    readonly property bool hideWouldEmpty: !(row.entry && row.entry.hidden) && root.visibleCount <= 1
    readonly property bool locked: !!(row.entry && row.entry.locked)
    readonly property bool hasPassword: !!(row.entry && row.entry.hasPassword)
    // The engine's three states, computed from the same two facts it uses:
    // a hash in the root store, and `locked` in the profile's own JSON.
    readonly property string passwordState: row.hasPassword ? "set"
                                            : (row.locked ? "locked_no_password" : "none")
    readonly property string identity: row.entry ? String(row.entry.identity || "") : ""
    readonly property bool passwordOpen: root.passwordRow === row.name

    foreground: root.foreground
    accent: root.accent
    hasCursor: root.cursorActive && root.cursor === row.rowIndex
    current: row.active

    implicitHeight: stack.implicitHeight + Style.space(14)

    // The row and, under it, whatever the key button opened. One column so the
    // row grows rather than the controls drawing over the next profile.
    Column {
      id: stack
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(6)

    Item {
      id: rowBody
      width: stack.width
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
            // The master is marked by colour alone. A "master" tag beside the
            // name said the same thing twice and crowded the row.
            color: row.master ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: row.active
          }
        }

        Text {
          textFormat: Text.PlainText
          width: labels.width
          visible: text !== ""
          // What this profile asks for, stated on the row. Enrolment is
          // deliberately not here: the face plugin owns the camera and the
          // model store, and two plugins competing for one IR sensor is a bug
          // in waiting.
          text: {
            if (row.passwordState === "locked_no_password")
              return "Locked without a password — set one"
            if (!row.hasPassword) return ""
            return row.identity !== "" ? "Password set · opens for " + row.identity : "Password set"
          }
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
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

        // Bigger than the 22x22 default. Four of these sit side by side with a
        // 2px gap, and at the default size the gaps are a meaningful share of
        // the strip: aiming for the gear and landing on nothing is easy, and
        // reads as the button ignoring the mouse rather than as a miss.
        // The row is taller than this already in every real case, so nothing
        // moves; only the area that answers grows.
        readonly property real actionSize: Style.space(28)

        // Master carries neither of these: it cannot be removed, and it sees
        // every app and plugin by definition, so there is nothing behind the
        // gear. Hidden rather than disabled — a greyed button invites a click
        // and then explains why it was pointless.
        PanelActionButton {
          visible: !row.master
          iconText: "󰒓"
          tooltipText: "Apps and plugins for " + row.name
          foreground: root.foreground
          size: actions.actionSize
          fontFamily: root.fontFamily
          onClicked: root.openSettings(row.name)
          onHovered: function (h) { if (h) root.cursorMoved(row.rowIndex) }
        }

        // Master can be protected too: it is the profile that sees everything,
        // so it is the one most worth gating.
        //
        // A key, not a toggle. Protecting a profile means giving it a password,
        // which is a thing to type, not a switch to flip — and taking one off
        // has to be answered for, which a toggle cannot ask.
        PanelActionButton {
          iconText: row.hasPassword ? "󰌾" : "󰌿"
          tooltipText: row.passwordState === "set"
            ? (row.identity !== ""
               ? row.name + " opens for its password, or for " + row.identity
               : "Change or remove the password on " + row.name)
            : row.passwordState === "locked_no_password"
              ? row.name + " is locked without a password of its own — set one"
              : "Give " + row.name + " a password of its own"
          foreground: row.passwordState === "none" ? root.foreground : root.accent
          size: actions.actionSize
          fontFamily: root.fontFamily
          onClicked: root.passwordRow = row.passwordOpen ? "" : row.name
          onHovered: function (h) { if (h) root.cursorMoved(row.rowIndex) }
        }

        PanelActionButton {
          // Hiding only affects the picker; the profile and its windows stay.
          // Master may be hidden like any other — the single rule is that the
          // picker can never be emptied, so the last visible one is stuck.
          iconText: (row.entry && row.entry.hidden) ? "󰛐" : "󰛑"
          tooltipText: (row.entry && row.entry.hidden)
            ? "Show in the picker"
            : (row.hideWouldEmpty
               ? "The only profile in the picker — make another visible first"
               : "Hide from the picker")
          foreground: root.foreground
          size: actions.actionSize
          fontFamily: root.fontFamily
          enabled: (row.entry && row.entry.hidden) ? true : !row.hideWouldEmpty
          onClicked: root.runEngine(((row.entry && row.entry.hidden) ? "show " : "hide ") + row.name)
          onHovered: function (h) { if (h) root.cursorMoved(row.rowIndex) }
        }

        PanelActionButton {
          visible: !row.master
          iconText: "󰩹"
          tooltipText: row.active ? "Switch away before removing this profile" : "Remove " + row.name
          foreground: root.foreground
          hoverColor: Color.urgent
          size: actions.actionSize
          fontFamily: root.fontFamily
          enabled: !row.active
          onClicked: root.confirmRemove(row.name)
          onHovered: function (h) { if (h) root.cursorMoved(row.rowIndex) }
        }
      }
    }

    // What the key button opens: the password itself, and nothing else.
    //
    // Each of these hands the profile back to the panel, which raises the
    // prompt. Setting and resetting also raise polkit's own dialog for the
    // owner — this panel never collects the owner's password, and could not
    // do anything useful with it if it did.
    Column {
      width: stack.width
      visible: row.passwordOpen
      spacing: Style.space(4)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        text: row.passwordState === "set"
          ? "Anyone entering " + row.name + " is asked for this password. Your own password is not asked for and does not open it."
          : row.passwordState === "locked_no_password"
            ? "Locked before passwords existed, so it asks the machine owner every time — and that is the one lock a settings edit can still switch off. Give it a password of its own."
            : "A password is asked for when this profile is entered. It is kept where a program running as you cannot read it, and it is not your machine password."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        spacing: Style.space(6)

        Button {
          visible: row.passwordState !== "set"
          text: "Set a password"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: root.passwordAction(row.name, "set")
        }

        Button {
          visible: row.passwordState === "set"
          text: "Change"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: root.passwordAction(row.name, "change")
        }

        Button {
          visible: row.passwordState === "set"
          text: "Remove password"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: root.passwordAction(row.name, "clear")
        }

        Button {
          visible: row.passwordState === "set"
          text: "Reset as owner"
          bordered: true
          foreground: root.dim
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: root.passwordAction(row.name, "reset")
        }
      }
    }
    }

    HoverHandler {
      onHoveredChanged: if (hovered) root.cursorMoved(row.rowIndex)
    }
  }
}
