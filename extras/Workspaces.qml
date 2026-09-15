import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Workspace indicators, offset by the active profile.
//
// Cloned from omarchy.workspaces. The stock widget hardcodes which workspaces
// it will consider to 1..10 (`if (id > 0 && id <= 10)`). Profiles give each
// activity its own block of ten real workspaces — personal 1..10, work 11..20,
// dev 21..30 — so under the stock filter every profile except personal would
// show an empty bar and never highlight the focused workspace.
//
// Hyprland has no app grouping, so workspaces are the only layer available for
// separating one activity's fullscreen apps from another's. This widget is what
// keeps that mechanism from leaking into the bar: the buttons stay labelled
// 1..0 in every profile, and only the id they target and compare against moves.
//
// The offset comes from the profile engine's state file, the single place
// "which profile am I in" is recorded.
BarWidget {
  id: root
  moduleName: "kalinewb.workspaces"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/omarchy-profiles/current.json"

  // 0 until the state file says otherwise, so a machine that has never applied
  // a profile behaves exactly like the stock widget.
  property int offset: 0
  readonly property int span: 10

  function parseState(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      var next = parsed ? Number(parsed.ws_offset) : 0
      root.offset = isFinite(next) && next >= 0 ? next : 0
    } catch (e) {
      // Keep the last known offset. A half-written file would otherwise strand
      // the bar on another profile's block, which reads as every indicator
      // going dark at once.
      console.warn("kalinewb.workspaces", "Ignoring bad state file", root.statePath, e)
    }
  }

  // What a button prints: the position within the profile, never the real id.
  function labelFor(id) {
    var n = id - root.offset
    return n === 10 ? "0" : String(n)
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // Real ids: always the first five of this profile's block, plus any further
  // workspace in the block that currently holds windows.
  function workspaceIds() {
    var ids = []
    for (var n = 1; n <= 5; n++) ids.push(root.offset + n)

    var lower = root.offset + 1
    var upper = root.offset + root.span
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id >= lower && id <= upper && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseState(text())
    onLoadFailed: root.offset = 0
  }

  // watchChanges cannot announce a file created under a directory that did not
  // exist when the watch began — the state of a machine that has never applied
  // a profile. Poll until it reads once, then let the watcher take over.
  // Bound to offset === 0 so it disables itself for every profile but personal,
  // whose offset genuinely is 0 and which needs no correction anyway.
  Timer {
    interval: 2000
    repeat: true
    running: root.offset === 0
    triggeredOnStart: true
    onTriggered: stateFile.reload()
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: focused ? "\uDB85\uDCFB" : root.labelFor(modelData)
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
