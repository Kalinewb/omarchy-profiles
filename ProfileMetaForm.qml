import QtQuick
import qs.Commons
import qs.Ui

// What a profile is called and what it looks like in the list: its name, its
// icon, and the line under it.
//
// Two submits, not one, because they are two different things. The icon and the
// description are labels — `meta` writes them into the profile's own JSON and
// nothing else happens. The name is a key: a password hash, a face binding, an
// isolated store, a session record and the master entry in config.json are all
// filed under it, so changing it goes through `rename`, which authenticates
// first and moves every one of them. A single Save button would hide that
// difference behind one click and one password prompt.
Column {
  id: view

  // The panel, for its engine calls and its profile index. Nothing here holds
  // a second copy of either.
  property var panel: null

  readonly property color foreground: view.panel ? view.panel.foreground : Color.foreground
  readonly property color accent: view.panel ? view.panel.accent : Color.accent
  readonly property color dim: view.panel ? view.panel.dim : Qt.darker(Color.foreground, 1.55)
  readonly property string fontFamily: view.panel ? view.panel.fontFamily : Style.font.family

  readonly property string profile: view.panel ? String(view.panel.editProfile || "") : ""
  readonly property var entry: (view.panel && view.profile !== "") ? view.panel.entry(view.profile) : null
  readonly property bool protectedProfile: !!(view.entry && (view.entry.hasPassword || view.entry.locked))

  // The icon being chosen, held here rather than read back from the entry on
  // every repaint: the grid has to show a pick before it is saved, and the
  // index does not change until it is.
  property string icon: ""
  readonly property string newName: String(nameField.text || "").trim()

  // Sixteen, from the Material Design set the rest of this plugin already draws
  // from — desks, places and the kinds of work a desk is for, which is what a
  // profile tends to be named after. Anything else goes in the field below;
  // this is a shortcut, not the vocabulary.
  readonly property var glyphs: [
    "󰆼", "󰒓", "󰍹", "󰌢", "󰃖", "󰋜", "󰀄", "󰅩",
    "󰆍", "󰏘", "󰝚", "󰊗", "󰂽", "󰂓", "󰑣", "󰒘"
  ]

  spacing: Style.space(8)

  // Seeded when the page is opened, not bound: these are fields being typed
  // into, and a binding would overwrite a half-typed name every time the engine
  // rewrote the index.
  onProfileChanged: view.reload()
  Component.onCompleted: view.reload()

  function reload() {
    var e = view.entry
    nameField.text = view.profile
    descField.text = e ? String(e.blurb || "") : ""
    view.icon = e ? String(e.icon || "") : ""
    customIcon.text = ""
  }

  function submitRename() {
    var to = view.newName
    if (!view.panel || to === "" || to === view.profile) return
    view.panel.keepAlive()
    // Protected or not is the panel's call: it raises the prompt for one and
    // goes straight through for the other.
    view.panel.beginRename(view.profile, to)
  }

  function submitMeta() {
    if (!view.panel || view.profile === "") return
    view.panel.keepAlive()
    view.panel.submitMeta(view.profile, view.icon, String(descField.text || "").trim())
  }

  // ------------------------------------------------------------------ name

  PanelSectionHeader {
    width: parent.width
    text: "NAME"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  TextField {
    id: nameField
    width: parent.width
    placeholderText: "Name (letters, digits, - and _)"
    foreground: view.foreground
    accent: view.accent
    font.family: view.fontFamily
    // The engine refuses a bad or taken name and the refusal renders below;
    // nothing here decides what a legal name is.
    onAccepted: view.submitRename()
    onTextChanged: if (view.panel) view.panel.keepAlive()
  }

  Row {
    spacing: Style.space(6)

    Button {
      // Dim as well as inert while the name is unchanged: a button that
      // silently ignores a click reads as one that is broken.
      readonly property bool armed: view.newName !== "" && view.newName !== view.profile
      text: "Rename"
      bordered: true
      enabled: armed
      foreground: armed ? view.foreground : view.dim
      fontFamily: view.fontFamily
      fontSize: Style.font.caption
      onClicked: view.submitRename()
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: view.protectedProfile
        ? "Asks for this profile's password first"
        : "Its windows, its stores and its records all follow the name"
      color: view.dim
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  PanelSeparator { foreground: view.foreground }

  // ------------------------------------------------------------------ icon

  PanelSectionHeader {
    width: parent.width
    text: "ICON"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  Grid {
    width: parent.width
    columns: 8
    spacing: Style.space(4)

    Repeater {
      model: view.glyphs

      Button {
        required property var modelData
        text: String(modelData)
        bordered: true
        selected: view.icon === String(modelData)
        foreground: view.icon === String(modelData) ? view.accent : view.foreground
        fontFamily: view.fontFamily
        fontSize: Style.font.body
        onClicked: { if (view.panel) view.panel.keepAlive(); view.icon = String(modelData) }
      }
    }
  }

  TextField {
    id: customIcon
    width: parent.width
    // Nerd Font tables publish codepoints, not glyphs, so the number is what a
    // person copying one out of a cheat sheet actually has. The engine converts
    // it, so the CLI and this field agree about what "f0493" means.
    placeholderText: "Any other glyph, or a codepoint like f0493"
    foreground: view.foreground
    accent: view.accent
    font.family: view.fontFamily
    onAccepted: {
      var t = String(customIcon.text || "").trim()
      if (t === "") return
      view.icon = t
    }
    onTextChanged: if (view.panel) view.panel.keepAlive()
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Shown in the picker, in the list and on the bar while this profile is active."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  PanelSeparator { foreground: view.foreground }

  // ----------------------------------------------------------- description

  PanelSectionHeader {
    width: parent.width
    text: "DESCRIPTION"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  TextField {
    id: descField
    width: parent.width
    placeholderText: "One line: what this desk is for"
    foreground: view.foreground
    accent: view.accent
    font.family: view.fontFamily
    onAccepted: view.submitMeta()
    onTextChanged: if (view.panel) view.panel.keepAlive()
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: text !== ""
    text: view.panel ? String(view.panel.metaError || "") : ""
    color: Color.urgent
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Row {
    spacing: Style.space(6)

    Button {
      text: "Save"
      bordered: true
      foreground: view.foreground
      fontFamily: view.fontFamily
      fontSize: Style.font.caption
      onClicked: view.submitMeta()
    }

    Button {
      text: "Cancel"
      foreground: view.dim
      fontFamily: view.fontFamily
      fontSize: Style.font.caption
      onClicked: { if (view.panel) { view.panel.keepAlive(); view.panel.navBack() } }
    }
  }
}
