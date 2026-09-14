import QtQuick
import qs.Commons
import qs.Ui

// Setup: one row per thing that has to be true before profiles work.
//
// It renders whatever `setup status --json` returns and knows nothing about
// which rows exist. That is deliberate: rows land with the phase that makes
// them true, and a later phase adding one — helpers, polkit, the reload probe —
// must not need a line changed here.
//
// The tone table is the contract's (plan-merged.md §2 rule 5): ok is good,
// needs_action and broken are bad, absent is dim, and anything else at all —
// including a state string this file has never heard of — renders as unknown.
// Unknown is never rendered as healthy, because a fact nobody could determine
// and a fact that is fine must not look the same.
Column {
  id: view

  property var panel: null

  readonly property color foreground: panel ? panel.foreground : Color.foreground
  readonly property color dim: panel ? panel.dim : Color.muted
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property var rows: (panel && panel.setupRows) ? panel.setupRows : []
  readonly property string outcome: panel ? panel.setupOutcome : ""

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(8)

  function toneFor(state) {
    if (state === "ok") return "good"
    if (state === "needs_action" || state === "broken") return "bad"
    if (state === "absent") return "dim"
    return "unknown"
  }

  // Three things this can be showing, and they must never be confused: an
  // answer, no answer yet, and an engine that could not answer at all.
  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: view.rows.length === 0
    wrapMode: Text.WordWrap
    text: {
      if (!view.panel) return ""
      if (view.outcome === "") return "Checking…"
      if (view.outcome === "ok") return "Setup answered, but sent no rows."
      return "Setup could not be read (" + view.outcome + ")."
    }
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
  }

  Repeater {
    model: view.rows

    Item {
      id: row
      required property var modelData

      readonly property string state: String(modelData.state || "")
      readonly property string tone: view.toneFor(row.state)
      readonly property bool fixable: !!modelData.fixable
      readonly property string rowId: String(modelData.id || "")
      readonly property bool running: !!view.panel && view.panel.pendingSetup === row.rowId

      width: view.width
      implicitHeight: rowContent.implicitHeight + Style.space(12)

      Row {
        id: rowContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: "●"
          color: row.tone === "good" ? view.foreground
                 : row.tone === "bad" ? Color.urgent
                 : view.dim
          opacity: row.tone === "dim" ? 0.5 : 1
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: rowContent.width - rowContent.spacing * 2 - 2 * Style.space(6)
                 - Style.space(12) - (fixButton.visible ? fixButton.width + rowContent.spacing : 0)
          spacing: 0

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: String(row.modelData.label || row.rowId)
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: text !== ""
            // The detail is the engine's own sentence, and it is the whole
            // explanation. An undeterminable row says so before anything else:
            // its detail explains why, not what is wrong.
            text: {
              var d = String(row.modelData.detail || "")
              if (row.tone === "unknown")
                return d !== "" ? "Could not be determined — " + d : "Could not be determined."
              return d !== "" ? d : row.state
            }
            color: view.dim
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // No terminal anywhere, and no pkexec either: a fix that needs root is
        // the engine's to raise, through polkit's own agent. None of the rows
        // that exist yet do, so the key glyph arrives with the ones that will.
        Button {
          id: fixButton
          anchors.verticalCenter: parent.verticalCenter
          visible: row.fixable && (row.state === "needs_action" || row.state === "broken")
          enabled: !!view.panel && view.panel.pendingSetup === ""
          text: row.running
                ? ("Fixing… " + (view.panel ? view.panel.setupElapsed : 0) + "s")
                : "Fix"
          bordered: true
          foreground: view.foreground
          fontFamily: view.fontFamily
          fontSize: Style.font.caption
          onClicked: {
            if (!view.panel) return
            view.panel.keepAlive()
            view.panel.runFix(row.rowId)
          }
        }
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: !!view.panel && view.panel.setupError !== ""
    wrapMode: Text.WordWrap
    text: view.panel ? view.panel.setupError : ""
    color: Color.urgent
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }
}
