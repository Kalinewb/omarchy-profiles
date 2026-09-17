#!/bin/bash

# Do the pins in bin/omarchy-profile match the files they describe?
#
# A stale pin does not weaken anything — root refuses to install and says so —
# but it breaks Setup's password-helpers Fix for everyone on that commit, so it
# is caught here, before a sync or a release, rather than in the panel.
#
# Run from anywhere: extras/check-pins.sh

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

bad=0
check() {
  local var=$1 file=$2 want got
  want=$(grep -E "^$var=" bin/omarchy-profile | head -1 | cut -d= -f2)
  got=$(sha256sum -- "$file" | cut -d' ' -f1)
  if [[ $want != "$got" ]]; then
    echo "check-pins: $var is stale for $file — run extras/update-pins.sh" >&2
    bad=1
  fi
}
check PIN_AUTH bin/omarchy-profile-auth
check PIN_PASSWD bin/omarchy-profile-passwd
check PIN_POLICY polkit/no.kalinewb.profiles.policy

((bad)) && exit 1
echo "check-pins: ok — every pinned file matches"
