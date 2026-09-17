#!/bin/bash

# Rewrite the SHA-256 pins in bin/omarchy-profile's SYSTEM_INSTALL from the
# files they describe. Run after changing either helper or the polkit policy.
#
# The pins are what make the root install safe to run from a user-writable
# checkout: root installs only bytes that hash to these values. So they must
# be committed together with the files, in the same commit.
#
# Run from anywhere: extras/update-pins.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

sum() { sha256sum -- "$1" | cut -d' ' -f1; }
auth=$(sum bin/omarchy-profile-auth)
passwd=$(sum bin/omarchy-profile-passwd)
policy=$(sum polkit/no.kalinewb.profiles.policy)

sed -i -E \
  -e "s/^PIN_AUTH=.*/PIN_AUTH=$auth/" \
  -e "s/^PIN_PASSWD=.*/PIN_PASSWD=$passwd/" \
  -e "s/^PIN_POLICY=.*/PIN_POLICY=$policy/" \
  bin/omarchy-profile

echo "pins updated:"
grep -E '^PIN_(AUTH|PASSWD|POLICY)=' bin/omarchy-profile
