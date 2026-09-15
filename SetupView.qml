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

  readonly property int fixableCount: {
    var n = 0
    for (var i = 0; i < view.rows.length; i++) {
      var r = view.rows[i]
      if (r && r.fixable && (r.state === "needs_action" || r.state === "broken")) n++
    }
    return n
  }
  readonly property bool queueRunning: !!panel && panel.fixingAll

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(8)

  function toneFor(state) {
    if (state === "ok") return "good"
    if (state === "needs_action" || state === "broken") return "bad"
    if (state === "absent") return "dim"
    return "unknown"
  }

  // helpers and polkit are the two rows a fix cannot finish by itself —
  // both go through the one owner-authorised install call, which raises a
  // system password dialog this panel never draws and cannot detect. Left
  // as a plain "Fixing…" the whole screen looked stalled for however long
  // that dialog sat unanswered, with nothing telling you to go look for it.
  readonly property bool waitingOnPrompt: !!panel
    && (panel.pendingSetup === "helpers" || panel.pendingSetup === "polkit")

  // One button, two jobs depending on where the machine is: something left
  // to set up shows Install and does them one at a time (clicking each
  // row's own Fix in turn is the same calls, just slower to ask for, and
  // stops at the first failure rather than guessing whether the rest are
  // worth trying); nothing left shows Uninstall, opening the same
  // confirmation the Manage row does rather than removing anything from a
  // single click here. A lone remaining row relies on its own Fix — this
  // slot is for "everything" in either direction, not "the one thing".
  Button {
    width: parent.width
    visible: view.fixableCount !== 1
    enabled: !view.queueRunning
    text: view.fixableCount > 1
          ? (!view.queueRunning ? ("Install (" + view.fixableCount + ")")
             : view.waitingOnPrompt ? "Waiting for your password… (check behind this window)"
             : ("Installing… " + view.fixableCount + " left"))
          : "Uninstall"
    bordered: true
    foreground: view.waitingOnPrompt ? Color.accent : view.foreground
    fontFamily: view.fontFamily
    onClicked: {
      if (!view.panel) return
      view.panel.keepAlive()
      if (view.fixableCount > 1) view.panel.runFixAll()
      else view.panel.openPurge()
    }
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

        // No terminal anywhere: a fix that needs root raises it through
        // polkit's own agent, not a terminal this panel would have to open.
        // helpers and polkit share that one owner-authorised call, and this
        // panel has no way to know a system dialog is up — only that the
        // call is taking longer than the ones that never raise one.
        Button {
          id: fixButton
          anchors.verticalCenter: parent.verticalCenter
          visible: row.fixable && (row.state === "needs_action" || row.state === "broken")
          enabled: !!view.panel && view.panel.pendingSetup === "" && !view.queueRunning
          text: !row.running ? "Fix"
                : (row.rowId === "helpers" || row.rowId === "polkit")
                  ? "Check for a password prompt…"
                  : ("Fixing… " + (view.panel ? view.panel.setupElapsed : 0) + "s")
          bordered: true
          foreground: (row.running && (row.rowId === "helpers" || row.rowId === "polkit")) ? Color.accent : view.foreground
          fontFamily: view.fontFamily
          fontSize: Style.font.caption
          onClicked: {
            if (!view.panel) return
            view.panel.keepAlive()
            view.panel.runFix(row.rowId)
          }
        }

        // Fix's own result is a colour change on a row someone may already
        // have scrolled past — say it plainly for a few seconds instead.
        Text {
          textFormat: Text.PlainText
          visible: !!view.panel && view.panel.lastFixedRow === row.rowId
          anchors.verticalCenter: parent.verticalCenter
          text: "✓ Fixed"
          color: Color.good
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
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
