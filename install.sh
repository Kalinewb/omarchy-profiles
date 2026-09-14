#!/bin/bash

# Sync this working tree into the live plugin directory.
#
# Development cannot happen in ~/.config/omarchy/plugins: that tree is watched
# recursively by inotifywait, and every write there triggers a GLOBAL shell
# reload — every panel, service and bar widget torn down and re-mounted. Editing
# in place makes the desktop flicker continuously, and running git there is
# worse, because .git churns on every command.
#
# So the repo lives outside it and this pushes a copy in. One write burst, one
# reload, instead of one per keystroke.

set -euo pipefail

ID="graveklar.profiles"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$ID"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$DEST"
rsync -a --delete \
  --exclude '.git' --exclude 'install.sh' --exclude '*.bak' --exclude '*.bak.*' \
  "$SRC/" "$DEST/"

chmod +x "$DEST/bin/omarchy-profile" \
         "$DEST/bin/omarchy-profile-auth" \
         "$DEST/bin/omarchy-profile-passwd"

# Nothing privileged happens here, deliberately.
#
# This script only syncs the working tree into the plugin directory, which is
# entirely the user's. The two root-owned helpers and the polkit actions are
# installed by Setup's `helpers`/`polkit` rows, through one pkexec call the
# engine owns — the same path a marketplace install takes, which never runs
# this file at all. Installing the policy here as well would mean the dev tree
# and Setup disagreeing about what is registered: every sync would push a copy
# of whatever this checkout happens to hold, including an old single-action
# policy, over the one Setup just installed and is checking against.

if command -v omarchy >/dev/null; then
  omarchy plugin validate "$DEST" || { echo "install.sh: plugin failed validation" >&2; exit 1; }
fi
echo "installed $ID -> $DEST"

# Restart the shell unless told not to.
#
# The plugin watcher's reload calls Qt.clearComponentCache() and re-instantiates
# the entry point, but it does NOT recompile the other QML types in the folder:
# an edit to ManageView.qml or SettingsView.qml keeps rendering the previously
# compiled version, and a brand-new .qml type is not resolvable at all. Both
# look exactly like "my change did nothing", which is a bad way to spend an
# afternoon. A restart is one visible blip and always tells the truth.
if [[ ${1:-} == --no-restart ]]; then
  echo "(shell not restarted — edits to any .qml but the entry point will render stale)"
elif command -v omarchy >/dev/null; then
  omarchy restart shell >/dev/null 2>&1 && echo "restarted the shell"
fi
