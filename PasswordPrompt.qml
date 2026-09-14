import QtQuick
import qs.Commons
import qs.Ui

// The password prompt, for entering a profile and for managing its password.
//
// An anchored overlay like the confirmations, and for the same reason: a Column
// child may not use anchors, and an unanchored dialog is laid out as an
// ordinary row that takes the whole panel and renders as a blank page.
//
// State lives on the panel (passwordFor, passwordMode, …) because more than one
// thing drives it: a row's key button, the picker, a `remove` confirmation, and
// `promptUnlock` from outside the panel entirely. This file is the face of that
// state and holds none of its own except what has been typed.
//
// The password goes to the engine over stdin. It is never put in an argument
// list, so it never appears in /proc/<pid>/cmdline, which every process on this
// machine can read.
Item {
  id: view

  property var panel: null

  readonly property string profile: panel ? panel.passwordFor : ""
  readonly property string mode: panel ? panel.passwordMode : ""
  readonly property string error: panel ? panel.passwordError : ""
  readonly property int retryIn: panel ? panel.passwordRetryIn : 0
  readonly property bool faceTrying: panel ? panel.faceTrying : false
  readonly property string identity: {
    if (!panel || view.profile === "") return ""
    var e = panel.entry(view.profile)
    return e ? String(e.identity || "") : ""
  }

  readonly property color foreground: panel ? panel.foreground : Color.foreground
  readonly property color dim: panel ? panel.dim : Color.muted
  readonly property color accent: panel ? panel.accent : Color.accent
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family

  // Which fields this mode needs. "Current" is the password the profile has
  // now; "new" and its confirmation are what it is being given.
  readonly property bool wantsCurrent: view.mode === "enter" || view.mode === "change"
                                       || view.mode === "clear" || view.mode === "remove"
                                       || view.mode === "rename"
  readonly property bool wantsNew: view.mode === "set" || view.mode === "reset" || view.mode === "change"
  // Every mode except entering one can be answered by the machine owner
  // instead, through polkit's own dialog — which this panel never draws and
  // never collects anything for.
  readonly property bool ownerAlternative: view.mode === "clear" || view.mode === "remove" || view.mode === "rename"

  readonly property bool locked: view.retryIn > 0

  visible: view.profile !== ""

  function reset() {
    currentField.text = ""
    newField.text = ""
    confirmField.text = ""
  }

  function title() {
    switch (view.mode) {
    case "enter": return "Open " + (panel ? panel.label(view.profile) : view.profile)
    case "set": return "Set a password for " + (panel ? panel.label(view.profile) : view.profile)
    case "reset": return "Reset the password for " + (panel ? panel.label(view.profile) : view.profile)
    case "change": return "Change the password for " + (panel ? panel.label(view.profile) : view.profile)
    case "clear": return "Remove the password from " + (panel ? panel.label(view.profile) : view.profile)
    case "remove": return "Remove " + (panel ? panel.label(view.profile) : view.profile)
    case "rename": return "Rename " + (panel ? panel.label(view.profile) : view.profile)
    }
    return ""
  }

  function caption() {
    if (view.locked)
      return "Too many attempts. The next one can be tried in " + view.retryIn + "s."
    if (view.faceTrying)
      return "Looking for " + view.identity + " — or type the password"
    switch (view.mode) {
    case "enter": return "This profile asks for its own password, not the machine's."
    case "set": return "Your password is asked for once, to authorise it. The profile's own password is the one typed here."
    case "reset": return "For a password nobody remembers. Your own password authorises it."
    case "change": return "The current password, then the new one."
    case "clear": return "After this the profile opens with no prompt."
    case "remove": return "Its windows move to the master only after this is answered."
    case "rename": return "The password and any bound face follow the new name."
    }
    return ""
  }

  function ready() {
    if (view.locked) return false
    if (view.wantsNew) {
      if (newField.text === "") return false
      if (newField.text !== confirmField.text) return false
    }
    if (view.mode === "enter") return currentField.text !== ""
    return true
  }

  function submit() {
    if (!panel || !view.ready()) return
    if (view.mode === "enter") {
      panel.submitPassword(view.profile, currentField.text)
    } else if (view.mode === "change") {
      panel.submitManage("change", view.profile, currentField.text + "\n" + newField.text)
    } else if (view.wantsNew) {
      panel.submitManage(view.mode, view.profile, newField.text)
    } else {
      panel.submitManage(view.mode, view.profile, currentField.text)
    }
    view.reset()
  }

  // Empty stdin is what asks the engine to raise the owner's prompt instead.
  function submitAsOwner() {
    if (!panel) return
    panel.submitManage(view.mode, view.profile, "")
    view.reset()
  }

  function cancel() {
    if (panel) panel.cancelPassword()
    view.reset()
  }

  // Escape, Enter and the arrow keys are handled here while this is open; the
  // panel's own key catcher is inert meanwhile, so Enter cannot switch a
  // profile behind the prompt.
  function handleKey(event) {
    if (view.profile === "") return false
    if (event.key === Qt.Key_Escape) { view.cancel(); return true }
    return false
  }

  onProfileChanged: {
    view.reset()
    if (view.profile !== "")
      Qt.callLater(function () {
        if (view.wantsCurrent) currentField.forceActiveFocus()
        else newField.forceActiveFocus()
      })
  }

  // Counts the lockout down rather than sitting on a sleeping helper: the
  // engine refuses immediately and says how long is left, so the field can say
  // so too. A wrong password and a lockout must never read alike.
  Timer {
    interval: 1000
    repeat: true
    running: view.retryIn > 0
    onTriggered: if (panel) panel.passwordRetryIn = Math.max(0, panel.passwordRetryIn - 1)
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.7)

    MouseArea { anchors.fill: parent; onClicked: view.cancel() }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(24), Style.space(330))
      height: card.contentTopInset + card.contentBottomInset + body.implicitHeight
      anchors.centerIn: parent
      color: Color.background
      borderSpec: Border.flat(view.accent, Style.normalBorderWidth)
      padding: Style.space(16)
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: body
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: view.title()
          color: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.title
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: text !== ""
          text: view.caption()
          color: view.faceTrying ? view.accent : view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        TextField {
          id: currentField
          width: parent.width
          visible: view.wantsCurrent
          password: true
          readOnly: view.locked
          placeholderText: view.mode === "change" ? "Current password" : "Password"
          foreground: view.foreground
          accent: view.accent
          font.family: view.fontFamily
          onAccepted: view.submit()
        }

        TextField {
          id: newField
          width: parent.width
          visible: view.wantsNew
          password: true
          placeholderText: "New password"
          foreground: view.foreground
          accent: view.accent
          font.family: view.fontFamily
          onAccepted: confirmField.forceActiveFocus()
        }

        TextField {
          id: confirmField
          width: parent.width
          visible: view.wantsNew
          password: true
          placeholderText: "New password again"
          foreground: view.foreground
          accent: view.accent
          font.family: view.fontFamily
          onAccepted: view.submit()
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: text !== ""
          text: {
            if (view.wantsNew && confirmField.text !== "" && newField.text !== confirmField.text)
              return "The two do not match"
            return view.error
          }
          color: Color.urgent
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Row {
          spacing: Style.space(6)

          Button {
            text: view.locked ? ("Wait " + view.retryIn + "s")
                  : view.mode === "remove" ? "Remove"
                  : view.mode === "enter" ? "Open"
                  : "Save"
            bordered: true
            enabled: view.ready()
            foreground: view.foreground
            fontFamily: view.fontFamily
            fontSize: Style.font.caption
            onClicked: view.submit()
          }

          Button {
            text: "Cancel"
            bordered: true
            foreground: view.dim
            fontFamily: view.fontFamily
            fontSize: Style.font.caption
            onClicked: view.cancel()
          }
        }

        // Not a second password field: this sends no password at all, and the
        // empty stdin is what makes the engine ask polkit to draw the owner's
        // own dialog.
        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: view.ownerAlternative
          text: "Authorise as owner instead"
          color: view.accent
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: view.submitAsOwner()
          }
        }
      }
    }
  }
}
