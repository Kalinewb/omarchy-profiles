#!/bin/bash

# The stdin rules, checked rather than remembered.
#
# A password that reaches an argument list is readable through
# /proc/<pid>/cmdline by every process on the machine — including the same-user
# process the gate exists to stop, and a root process's cmdline is world
# readable too. The rules are in the plan (plan-engine.md §4.2); this is the
# part of them a grep can hold:
#
#   1. every `openssl passwd` carries -stdin, so no password is ever positional
#   2. every pkexec call that carries a secret is fed by a pipe from bash's
#      builtin printf — not echo, not /usr/bin/printf, not a here-string
#   3. no secret-shaped variable appears inside audit, logger, warn, die or echo
#
# Run from the repo root: extras/check-secrets.sh

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

fail=0
report() { printf '%s\n' "$*" >&2; fail=1; }

files=(bin/omarchy-profile bin/omarchy-profile-auth bin/omarchy-profile-passwd)

# file:line:content -> content, so a comment is recognisable as one.
body() { local h=${1#*:}; printf '%s' "${h#*:}"; }
is_comment() { [[ $(body "$1") =~ ^[[:space:]]*# ]]; }

# 1. openssl passwd must always read the password from stdin.
while IFS= read -r hit; do
  [[ -n $hit ]] || continue
  is_comment "$hit" && continue
  [[ $hit == *-stdin* ]] && continue
  report "openssl passwd without -stdin: $hit"
done < <(grep -n 'openssl passwd' "${files[@]}")

# 2. a pkexec call carrying a secret must be fed by builtin printf through a
#    pipe. Any other producer either writes the secret to disk or forks a
#    program whose argv holds it.
while IFS= read -r hit; do
  [[ -n $hit ]] || continue
  line=$(body "$hit")
  is_comment "$hit" && continue
  [[ $line == *'pkexec'* ]] || continue
  # `||` is not a pipe. A call with no stdin at all is fine; one that is piped
  # into must be piped from the builtin.
  local_pipes=${line//||/}
  if [[ $local_pipes == *'|'* && $line != *'printf'*'|'*pkexec* ]]; then
    report "pkexec fed by something other than builtin printf: $hit"
  fi
  if [[ $line == *'/usr/bin/printf'* || $line == *'echo '*'|'*pkexec* ]]; then
    report "pkexec fed by a forked printf or echo: $hit"
  fi
  if [[ $line == *'<<<'* ]]; then
    report "pkexec fed by a here-string (which is a temp file): $hit"
  fi
done < <(grep -n 'pkexec' "${files[@]}")

# 3. a secret-shaped variable may never be an argument to anything that says
#    something out loud.
secretish='SECRET|OLD_SECRET|NEW_SECRET|HELPER_STDIN|secret|password|passwd|pw'
while IFS= read -r hit; do
  [[ -n $hit ]] || continue
  line=$(body "$hit")
  is_comment "$hit" && continue
  # `password status`, `$PASSWORDS/<p>` and the like are names, not values.
  [[ $line =~ \$\{?($secretish)[\}\"[:space:]] ]] || continue
  report "a secret-shaped variable inside a message: $hit"
done < <(grep -nE '(audit|logger|warn|die|echo)[[:space:]]+[^|]*\$\{?('"$secretish"')' "${files[@]}")

# 4. and nothing may pass one as an argument to a program.
while IFS= read -r hit; do
  [[ -n $hit ]] || continue
  report "a secret passed as an argument: $hit"
done < <(grep -nE '^[[:space:]]*[a-zA-Z0-9_/.-]+[[:space:]]+[^|#]*"\$(SECRET|OLD_SECRET|NEW_SECRET|HELPER_STDIN)"' "${files[@]}" |
         grep -v 'printf' | grep -v '^\s*#')

if ((fail)); then
  echo "check-secrets: FAILED" >&2
  exit 1
fi
echo "check-secrets: ok — no password reaches an argument list, a log or a temp file"
