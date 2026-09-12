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

chmod +x "$DEST/bin/omarchy-profile"

if command -v omarchy >/dev/null; then
  omarchy plugin validate "$DEST" || { echo "install.sh: plugin failed validation" >&2; exit 1; }
fi
echo "installed $ID -> $DEST"
