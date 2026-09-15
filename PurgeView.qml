import QtQuick
import qs.Commons
import qs.Ui

// Removing the plugin: one question, one button.
//
// A full itemised manifest used to sit here before the "Remove everything"
// button — every store, every tier-3 file, every count from
// `purge --dry-run --json`. Nobody reads a delete manifest before pressing
// one button; they read it because there was no button to press without
// reading it. So the dry run still runs, silently, only to answer "are we
// on master" (a hard technical requirement — see below) and give one rough
// line of size. Everything it would have itemised is still exactly what
// gets removed; it is just not printed here as a precondition.
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
  readonly property bool busy: !!panel && panel.purgeBusy
  readonly property bool done: !!panel && panel.purgeNote === "Removed. The shell is restarting."

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(12)

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: view.outcome === ""
    text: "Checking…"
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    visible: view.outcome !== "" && view.outcome !== "ok"
    text: "Could not check what would be removed (" + view.outcome + ")."
    color: Color.urgent
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
  }

  // Off master the flow cannot continue by itself: removing puts the machine
  // back as master has it, and a switch restarts the shell — which would
  // take this screen with it mid-flow. So this switches, and the user opens
  // Remove again, once, rather than the whole confirmation depending on a
  // switch finishing invisibly underneath it.
  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: view.outcome === "ok" && !view.onMaster

    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Removing puts the machine back as " + (view.masterName === "" ? "the master profile" : view.masterName)
            + " has it, so it has to be the profile you are in first."
      color: view.dim
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
    }

    Button {
      width: parent.width
      text: "Switch to " + (view.masterName === "" ? "master" : view.masterName) + " first"
      bordered: true
      foreground: view.foreground
      fontFamily: view.fontFamily
      onClicked: {
        if (!view.panel) return
        view.panel.keepAlive()
        view.panel.purgeSwitchToMaster()
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(14)
    visible: view.outcome === "ok" && view.onMaster && !view.done

    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: {
        var n = view.m ? Number(view.m.windows_to_move || 0) : 0
        var base = "This removes every profile, their settings and the plugin itself — the machine goes back to plain Omarchy."
        return n > 0 ? base + " " + n + " window(s) currently open on another profile move back to " + view.masterName + " first." : base
      }
      color: view.dim
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      width: parent.width
      spacing: Style.space(10)

      Text {
        width: parent.width - keepSwitch.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Keep a copy of my profiles"
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }

      ToggleSwitch {
        id: keepSwitch
        anchors.verticalCenter: parent.verticalCenter
        checked: !!view.panel && view.panel.purgeKeepData
        foreground: view.foreground
        accent: view.accent
        onToggled: {
          if (!view.panel) return
          view.panel.keepAlive()
          view.panel.purgeKeepData = !view.panel.purgeKeepData
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: view.panel && view.panel.purgeKeepData
            ? "Saved to " + (view.panel.purgeExportDir === "" ? "~/omarchy-profiles-export" : view.panel.purgeExportDir) + " before anything is removed."
            : "Nothing is kept — this cannot be undone."
      color: view.dim
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
    }

    // Red and named for what it does — the one button on this screen that
    // cannot be undone (short of the copy this same click can also make).
    Button {
      width: parent.width
      enabled: !view.busy
      text: view.busy ? "Working…" : "Uninstall everything"
      bordered: true
      foreground: Color.urgent
      accent: Color.urgent
      fontFamily: view.fontFamily
      onClicked: {
        if (!view.panel) return
        view.panel.keepAlive()
        view.panel.purgeGo()
      }
    }
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
