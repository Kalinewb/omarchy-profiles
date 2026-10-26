#!/bin/bash

# Check the engine against a throwaway home, never the real one.
#
#   ./dev/suite.sh
#
# Every case runs the real bin/omarchy-profile with HOME and every XDG
# directory inside one mktemp -d. PATH holds a few stubs and a short list of
# real tools and nothing else, so a command the list leaves out is "not found"
# instead of reaching the live desktop: no compositor, no shell restart, no
# notification. `omarchy plugin list --json` reads a fixture the case writes.
# The test refuses to run a case whose HOME is outside its sandbox.
#
#   T1  `setup status` and `capabilities` create no file

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ENGINE=$REPO/bin/omarchy-profile

TOP=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-profiles-suite.XXXXXX") || exit 1
trap 'rm -rf "$TOP"' EXIT

# The real tools the engine may use. Everything else is a stub or absent.
TOOLS=(bash sh env jq flock mktemp mv cp rm mkdir rmdir find sed awk gawk grep sort
       uniq comm cut head tail paste tr stat date id seq sleep basename dirname
       readlink realpath ln cat diff cmp wc touch chmod sha256sum tee xargs ls
       timeout kill true false du sync expr pwd)

# A case passes when every check in it does; the totals count cases.
passed=0; failed=0; bad=0
begin() { bad=0; echo "${BOLD}$1${RESET}  ${DIM}$2${RESET}"; }
ok() { echo "  ${GREEN}ok${RESET}    $1"; }
no() { echo "  ${RED}FAIL${RESET}  $1"; [[ -n ${2:-} ]] && printf '        %s\n' "${2:0:400}"; bad=1; }
end() { if ((bad)); then failed=$((failed + 1)); else passed=$((passed + 1)); fi; echo; }

# sandbox <name> — a fresh root; sets ROOT and H (its home).
sandbox() {
  ROOT="$TOP/$1"; H="$ROOT/home"
  mkdir -p "$ROOT"/{stubs,tools,tmp,run,share} "$H/.config/omarchy/plugins" \
           "$H/.local/state" "$H/.local/share" "$H/.cache"
  local t p
  for t in "${TOOLS[@]}"; do
    p=$(type -P "$t") && ln -s "$p" "$ROOT/tools/$t"
  done
  # Every call is logged, so a case can say what was asked of the desktop.
  cat >"$ROOT/stubs/omarchy" <<'EOF'
#!/bin/bash
printf 'omarchy %s\n' "$*" >>"$SANDBOX/calls"
[[ ${1:-} == plugin && ${2:-} == list ]] && cat "$SANDBOX/plugins.json"
exit 0
EOF
  cat >"$ROOT/stubs/omarchy-shell" <<'EOF'
#!/bin/bash
printf 'omarchy-shell %s\n' "$*" >>"$SANDBOX/calls"
[[ ${1:-} == notifications && ${2:-} == isDnd ]] && echo off
exit 0
EOF
  printf '#!/bin/bash\necho "[]"\n' >"$ROOT/stubs/omarchy-plugin-catalog"
  chmod +x "$ROOT"/stubs/*
  echo '[]' >"$ROOT/plugins.json"
}

# run [--engine <path>] <args...> — the engine, inside the current sandbox.
run() {
  local engine=$ENGINE
  [[ ${1:-} == --engine ]] && { engine=$2; shift 2; }
  case $H in "$ROOT"/*) ;; *) echo "suite: HOME '$H' is outside the sandbox, refusing" >&2; exit 2 ;; esac
  case $ROOT in "$TOP"/*) ;; *) echo "suite: sandbox '$ROOT' is outside $TOP, refusing" >&2; exit 2 ;; esac
  env -i HOME="$H" USER="${USER:-suite}" LANG=C.UTF-8 \
    XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" \
    XDG_DATA_HOME="$H/.local/share" XDG_CACHE_HOME="$H/.cache" \
    XDG_RUNTIME_DIR="$ROOT/run" XDG_DATA_DIRS="$ROOT/share" TMPDIR="$ROOT/tmp" \
    OMARCHY_PATH=/usr/share/omarchy SANDBOX="$ROOT" PATH="$ROOT/stubs:$ROOT/tools" \
    bash "$engine" "$@"
}

# Every path under the sandbox's home and scratch dirs, for a before/after diff.
tree_of() { find "$H" "$ROOT/run" "$ROOT/tmp" -mindepth 1 -printf '%P\n' 2>/dev/null | sort; }

# ------------------------------------------------------------------- T1
begin T1 "status queries are read-only"
sandbox t1
before=$(tree_of)
out=$(run setup status --json 2>/dev/null); rc=$?
caps=$(run capabilities --json 2>/dev/null)
after=$(tree_of)
created=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
if [[ -z $created ]]; then ok "setup status and capabilities created nothing"
else no "they created files" "$(printf '%s ' $created)"; fi
if ((rc == 0)) && jq -e 'type == "array" and length > 0' <<<"$out" >/dev/null 2>&1 &&
   jq -e 'has("passwords")' <<<"$caps" >/dev/null 2>&1; then
  ok "both still answer in JSON on a machine with no config"
else no "no JSON answer (setup rc $rc)" "$out"; fi
end

if ((failed)); then echo "${RED}$passed passed, $failed failed${RESET}"; exit 1; fi
echo "${GREEN}$passed passed, 0 failed${RESET}"
