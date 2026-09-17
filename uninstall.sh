#!/bin/bash

# Take this plugin off the machine, from a checkout.
#
# Everything is in the engine — `purge` moves the windows, puts the isolated
# files back as master's, un-hides every application, deletes the managed keys
# file and the line that requires it, deletes the stored passwords and
# removes the plugin itself, in an order where each step is placed by what would
# break if it ran later (plan-engine.md §9.2). None of that is repeated here,
# because a second implementation of it is a second thing to get wrong.
#
#   ./uninstall.sh --dry-run --json    what would go, and nothing else
#   ./uninstall.sh --export <dir>      copy every store out first
#   ./uninstall.sh --yes               do it
#
# The panel's Manage → "Remove Profiles from this machine" runs exactly the same
# verb. This file exists for the install that never had a panel.

set -uo pipefail

exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bin/omarchy-profile" purge "$@"
