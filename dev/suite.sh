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
#   T2  with the notch's suite.json, `create --clean` and switching into it
#       turn off none of the suite's plugins or the clones in use
#   T3  a profile saved before the notch (bar.id omarchy.bar) keeps the notch
#   T4  a pinned widget the profile lacks comes back where it was live
#   T5  with no suite.json, switching writes exactly what 1.3.0 wrote
#       (no clone in use there; T7 and T8 are the cases where one is)
#   T6  a suite.json of a later version still pins; version 0 does not
#   T7  a clone off now but in the target profile ends on, its source off
#   T8  with no notch, a clean profile leaves Face's lock on and Omarchy's off,
#       pinned or not, and the clone's switch says why it is locked

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ENGINE=$REPO/bin/omarchy-profile
# 1.3.0, the last version without suite pins. T5 holds the engine to it.
BASE=672a9d4

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

# The state lock is free and no journal is left: a detached switch is done.
settle() {
  local i lock="$H/.local/state/omarchy-profiles/.lock"
  for i in $(seq 1 150); do
    [[ ! -e $H/.local/state/omarchy-profiles/switch.json ]] &&
      flock -n "$lock" true 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

# switch_to [--engine <path>] <name> — switch and wait for the detached half.
switch_to() {
  local out
  out=$(run "$@" 2>&1) || { no "set ${*: -1} failed" "$out"; return 1; }
  settle || { no "the switch to ${*: -1} did not finish" "$(cat "$H/.local/state/omarchy-profiles/switch.log" 2>/dev/null)"; return 1; }
}

sj() { jq -c "$@" "$H/.config/omarchy/shell.json"; }
profile() { local f="$H/.config/omarchy/profiles/$1.json"; shift; jq -c "$@" "$f"; }
edit_profile() {
  local f="$H/.config/omarchy/profiles/$1.json"
  jq "$2" "$f" >"$f.new" && mv "$f.new" "$f"
}
# expect <description> <json> <jq test> — one check, on a value.
expect() {
  if jq -e "$3" <<<"$2" >/dev/null 2>&1; then ok "$1"; else no "$1" "$2"; fi
}

SUITE_PINNED='["graveklar.face","graveklar.face-lock","kalinewb.notch","kalinewb.notch-menu",
  "kalinewb.notch-notifications","kalinewb.notch-osd","kalinewb.oled-corners","kalinewb.profiles"]'
# Clones the fixture has in use. graveklar.background is the user's own; the
# notch's file does not name it.
IN_USE='["kalinewb.notch-menu","kalinewb.notch-osd","graveklar.face-lock","graveklar.background"]'

# plugin <id> <name> <kinds,...> <enabled> [clonedFrom] — one `plugin list` row.
plugin() {
  local fp=false cd=true
  [[ $1 == omarchy.* ]] && fp=true
  [[ $3 == bar ]] && cd=false
  jq -nc --arg id "$1" --arg n "$2" --arg k "$3" --argjson e "$4" --arg c "${5:-}" \
         --argjson fp "$fp" --argjson cd "$cd" \
    '{id: $id, name: $n, kinds: ($k | split(",")), enabled: $e, active: false,
      canDisable: $cd, firstParty: $fp, clonedFrom: $c}'
}

# This machine, in small: the notch is the bar, its companions and Face's lock
# stand in for the built-ins, and the wallpaper is the user's own clone.
# notch-notifications is pinned by the notch but not installed here.
notch_world() {
  {
    plugin omarchy.bar Bar bar false
    plugin omarchy.clock Clock bar-widget true
    plugin omarchy.audio Audio bar-widget true
    plugin omarchy.menu "Omarchy menu" menu,bar-widget false
    plugin omarchy.osd "On-screen display" panel false
    plugin omarchy.lock "Lock Screen" service false
    plugin omarchy.background Background service false
    plugin kalinewb.notch Notch bar true
    plugin kalinewb.notch-menu "Omarchy menu (notch)" menu,bar-widget true omarchy.menu
    plugin kalinewb.notch-osd "On-screen display (notch)" panel,service true omarchy.osd
    plugin graveklar.face "Face ID" bar-widget,service true
    plugin graveklar.face-lock "Lock Screen (Face ID)" service true omarchy.lock
    plugin kalinewb.oled-corners "OLED Corners" service true
    plugin kalinewb.profiles Profiles bar-widget true
    plugin graveklar.background "My Background" service true omarchy.background
    plugin io.github.sirjul1337.lock-explorer "Lock Screen Explorer" service,overlay false omarchy.lock
    plugin graveklar.bar "My Bar" bar false omarchy.bar
    plugin harshith.system-monitor "System monitor" bar-widget true
    plugin ming.keybindings Keybindings service true
  } | jq -s . >"$ROOT/plugins.json"
  cat >"$H/.config/omarchy/shell.json" <<'EOF'
{ "version": 1,
  "bar": { "id": "kalinewb.notch", "position": "top", "notch": { "radius": 18, "glow": true },
           "layout": { "left": [],
                       "center": [ { "id": "omarchy.clock", "format": "HH:mm" }, { "id": "kalinewb.notch-menu" } ],
                       "right": [ { "id": "harshith.system-monitor" }, { "id": "graveklar.face" },
                                  { "id": "kalinewb.profiles" }, { "id": "omarchy.audio" } ] } },
  "disabledPlugins": [ "omarchy.background", "omarchy.menu", "omarchy.osd", "omarchy.lock" ],
  "plugins": [ { "id": "graveklar.background" }, { "id": "kalinewb.notch-osd" }, { "id": "kalinewb.oled-corners" },
               { "id": "graveklar.face-lock" }, { "id": "ming.keybindings" } ],
  "idle": { "screensaver": 150, "lock": 300 } }
EOF
}

# suite_file [<json>] — the notch's suite.json, version 1 unless given.
suite_file() {
  mkdir -p "$H/.config/omarchy/plugins/kalinewb.notch"
  printf '%s\n' "${1:-$(jq -nc --argjson p "$SUITE_PINNED" '{version: 1, bar: "kalinewb.notch", pinned: $p}')}" \
    >"$H/.config/omarchy/plugins/kalinewb.notch/suite.json"
}

# Stock Omarchy with Profiles and two add-ons, and no notch. Two clones are
# installed and not in use: a lock explorer and a bar.
stock_world() {
  {
    plugin omarchy.bar Bar bar true
    plugin omarchy.clock Clock bar-widget true
    plugin omarchy.audio Audio bar-widget true
    plugin omarchy.workspaces Workspaces bar-widget true
    plugin omarchy.lock "Lock Screen" service true
    plugin omarchy.background Background service true
    plugin kalinewb.profiles Profiles bar-widget true
    plugin harshith.system-monitor "System monitor" bar-widget true
    plugin ming.keybindings Keybindings service true
    plugin io.github.sirjul1337.lock-explorer "Lock Screen Explorer" service,overlay false omarchy.lock
    plugin alice.bar "My Bar" bar false omarchy.bar
  } | jq -s . >"$ROOT/plugins.json"
  cat >"$H/.config/omarchy/shell.json" <<'EOF'
{ "version": 1,
  "bar": { "layout": { "left": [ { "id": "omarchy.workspaces" } ],
                       "center": [ { "id": "omarchy.clock" } ],
                       "right": [ { "id": "harshith.system-monitor" }, { "id": "kalinewb.profiles" },
                                  { "id": "omarchy.audio" } ] } },
  "disabledPlugins": [ "omarchy.notifications" ],
  "plugins": [ { "id": "ming.keybindings" } ],
  "idle": { "screensaver": 150, "lock": 300 } }
EOF
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

# ------------------------------------------------------------------- T2
begin T2 "the notch's plugins survive a clean profile"
sandbox t2; notch_world; suite_file
run init >/dev/null 2>&1
run create x --clean >/dev/null 2>&1
off=$(profile x '.plugins.disabled')
expect "the clean profile turns none of the 8 pinned ids or the clones in use off" "$(jq -nc \
  --argjson off "$off" --argjson p "$SUITE_PINNED" --argjson c "$IN_USE" '$off - ($off - $p - $c)')" '. == []'
expect "and still turns the other add-ons off" "$off" \
  'index("harshith.system-monitor") != null and index("ming.keybindings") != null'
before=$(sj '{bar, d: (.disabledPlugins | sort), plugins}')
if switch_to set x; then
  d=$(sj '.disabledPlugins')
  expect "after switching in, disabledPlugins holds none of them" "$(jq -nc \
    --argjson d "$d" --argjson p "$SUITE_PINNED" --argjson c "$IN_USE" '$d - ($d - $p - $c)')" '. == []'
  expect "while the other add-ons are off" "$d" 'index("harshith.system-monitor") != null'
  expect "and every built-in a clone stands in for is off" "$d" \
    'index("omarchy.menu") and index("omarchy.osd") and index("omarchy.lock") and index("omarchy.background")'
  expect "the notch is still the bar" "$(sj '.bar.id')" '. == "kalinewb.notch"'
  shared=$(jq -c 'map({key: .id, value: [.pinned, .shared, .sharedFor]}) | from_entries' \
             "$H/.local/state/omarchy-profiles/plugins.json")
  expect "the Settings list shows suite plugins and clones in use as locked, and why" "$shared" \
    '.["graveklar.face"] == [true, "suite", ""] and .["kalinewb.notch-menu"] == [true, "suite", "Omarchy menu"]
     and .["graveklar.background"] == [true, "clone", "Background"]
     and .["harshith.system-monitor"] == [false, "", ""]
     and .["io.github.sirjul1337.lock-explorer"] == [false, "", ""]'
  if switch_to set master; then
    expect "switching back gives the same bar, plugins and disabled set" \
      "$(jq -nc --argjson a "$before" --argjson b "$(sj '{bar, d: (.disabledPlugins | sort), plugins}')" '$a == $b')" '. == true'
  fi
fi
end

# ------------------------------------------------------------------- T3
begin T3 "a profile saved before the notch keeps the notch"
sandbox t3; notch_world; suite_file
run init >/dev/null 2>&1
run create old --from-master >/dev/null 2>&1
edit_profile old '.bar = {id: "omarchy.bar", layout: {left: [{id: "omarchy.workspaces"}],
                         center: [{id: "omarchy.clock"}], right: [{id: "omarchy.audio"}]}}'
if switch_to set old; then
  expect "bar.id is still kalinewb.notch" "$(sj '.bar.id')" '. == "kalinewb.notch"'
  expect "and its notch block is untouched" "$(sj '.bar.notch')" '. == {radius: 18, glow: true}'
  expect "and so is its layout" "$(sj '.bar.layout.center | map(.id)')" '. == ["omarchy.clock", "kalinewb.notch-menu"]'
fi
# Without the notch's file the profile's bar applies, as it always has.
sandbox t3-no-suite; notch_world
run init >/dev/null 2>&1
run create old --from-master >/dev/null 2>&1
edit_profile old '.bar = {id: "omarchy.bar", layout: {left: [], center: [{id: "omarchy.clock"}], right: []}}'
if switch_to set old; then
  expect "control: without suite.json the saved bar applies" "$(sj '.bar.id')" '. == "omarchy.bar"'
fi
end

# ------------------------------------------------------------------- T4
begin T4 "a pinned widget goes back where it was"
sandbox t4; notch_world; suite_file
run init >/dev/null 2>&1
run create lean --from-master >/dev/null 2>&1
edit_profile lean '.bar.layout.center |= map(select(.id != "kalinewb.notch-menu"))
                   | .plugins.disabled -= ["omarchy.menu"]'
expect "the profile lacks both menus" "$(profile lean '[.bar.layout[][] | .id] + .plugins.disabled')" \
  'index("kalinewb.notch-menu") == null and index("omarchy.menu") == null'
if switch_to set lean; then
  expect "kalinewb.notch-menu is back in the centre, in its place" "$(sj '.bar.layout.center | map(.id)')" \
    '. == ["omarchy.clock", "kalinewb.notch-menu"]'
  expect "not on the right" "$(sj '.bar.layout.right | map(.id)')" 'index("kalinewb.notch-menu") == null'
  expect "omarchy.menu is off" "$(sj '.disabledPlugins')" 'index("omarchy.menu") != null'
  expect "kalinewb.notch-menu is not" "$(sj '.disabledPlugins')" 'index("kalinewb.notch-menu") == null'
fi
end

# ------------------------------------------------------------------- T5
begin T5 "with no notch, switching writes what 1.3.0 wrote"
base_engine="$TOP/base/bin/omarchy-profile"
mkdir -p "${base_engine%/*}"
if ! git -C "$REPO" show "$BASE:bin/omarchy-profile" >"$base_engine" 2>/dev/null; then
  no "1.3.0 ($BASE) is not in this checkout, so there is nothing to compare with"
else
  # The same steps in two sandboxes, one per engine.
  for who in new base; do
    sandbox "t5-$who"; stock_world
    e=$ENGINE; [[ $who == base ]] && e=$base_engine
    run --engine "$e" init >/dev/null 2>&1
    run --engine "$e" create c --clean >/dev/null 2>&1
    cp "$H/.config/omarchy/profiles/c.json" "$ROOT/c.json"
    switch_to --engine "$e" set c && cp "$H/.config/omarchy/shell.json" "$ROOT/1-clean.json"
    run --engine "$e" create f --from-master >/dev/null 2>&1
    # A pinned widget missing from the profile: put back on the right, as ever.
    edit_profile f '.bar.layout.right |= map(select(.id != "kalinewb.profiles"))'
    switch_to --engine "$e" set master && cp "$H/.config/omarchy/shell.json" "$ROOT/2-master.json"
    switch_to --engine "$e" set f && cp "$H/.config/omarchy/shell.json" "$ROOT/3-from-master.json"
  done
  for f in c.json 1-clean.json 2-master.json 3-from-master.json; do
    if [[ -s $TOP/t5-new/$f ]] && cmp -s "$TOP/t5-new/$f" "$TOP/t5-base/$f"; then
      ok "$f is byte-identical"
    else
      no "$f differs from 1.3.0's" "$(diff <(jq -S . "$TOP/t5-base/$f" 2>&1) <(jq -S . "$TOP/t5-new/$f" 2>&1) | head -20)"
    fi
  done
  expect "and the widget did go back on the right" "$(jq -c '.bar.layout.right | map(.id)' "$TOP/t5-new/3-from-master.json")" \
    '.[0] == "kalinewb.profiles"'
fi
end

# ------------------------------------------------------------------- T6
begin T6 "the reader takes later versions and ignores broken ones"
for v in 2 0 '"1"'; do
  sandbox "t6-$v"; notch_world
  suite_file "$(jq -nc --argjson v "$v" --argjson p "$SUITE_PINNED" \
    '{version: $v, bar: "kalinewb.notch", pinned: $p, companions: {menu: "omarchy.menu"}, signedBy: "someone"}')"
  run init >/dev/null 2>&1
  run create x --clean >/dev/null 2>&1
  off=$(profile x '.plugins.disabled')
  if [[ $v == 2 ]]; then
    expect "version 2 with unknown fields still pins Face and OLED Corners" "$off" \
      'index("graveklar.face") == null and index("kalinewb.oled-corners") == null'
  else
    expect "version $v is not a suite file: Face and OLED Corners are not pinned" "$off" \
      'index("graveklar.face") != null and index("kalinewb.oled-corners") != null'
  fi
done
end

# ------------------------------------------------------------------- T7
begin T7 "a clone in the target profile ends on, its source off"
sandbox t7; stock_world
jq --argjson c "$(plugin alice.clock "My Clock" bar-widget false omarchy.clock)" '. + [$c]' \
  "$ROOT/plugins.json" >"$ROOT/p.json" && mv "$ROOT/p.json" "$ROOT/plugins.json"
run init >/dev/null 2>&1
run create x --from-master >/dev/null 2>&1
# Its own clock instead of the stock one, and a stale capture that lists it off.
edit_profile x '.bar.layout.center = [{id: "alice.clock"}] | .plugins.disabled += ["alice.clock"]'
expect "the live layout lacks the clone" "$(sj '[.bar.layout[][] | .id]')" 'index("alice.clock") == null'
if switch_to set x; then
  expect "alice.clock is in the bar" "$(sj '.bar.layout.center | map(.id)')" '. == ["alice.clock"]'
  expect "and not disabled" "$(sj '.disabledPlugins')" 'index("alice.clock") == null'
  expect "omarchy.clock is off" "$(sj '.disabledPlugins')" 'index("omarchy.clock") != null'
fi
end

# ------------------------------------------------------------------- T8
begin T8 "no notch: one lock screen, Face's"
sandbox t8; stock_world
jq --argjson c "$(plugin graveklar.face-lock "Lock Screen (Face ID)" service true omarchy.lock)" \
   '. + [$c] | map(if .id == "omarchy.lock" then .enabled = false else . end)' \
  "$ROOT/plugins.json" >"$ROOT/p.json" && mv "$ROOT/p.json" "$ROOT/plugins.json"
jq '.plugins += [{id: "graveklar.face-lock"}] | .disabledPlugins += ["omarchy.lock"]' \
  "$H/.config/omarchy/shell.json" >"$ROOT/s.json" && mv "$ROOT/s.json" "$H/.config/omarchy/shell.json"
run init >/dev/null 2>&1
run create c --clean >/dev/null 2>&1
expect "the clean profile does not turn Face's lock off" "$(profile c '.plugins.disabled')" \
  'index("graveklar.face-lock") == null and index("ming.keybindings") != null'
if switch_to set c; then
  expect "after switching in, omarchy.lock is off and Face's lock is on" \
    "$(sj '{d: .disabledPlugins, p: [.plugins[].id]}')" \
    '(.d | index("omarchy.lock")) != null and (.d | index("graveklar.face-lock")) == null
     and (.p | index("graveklar.face-lock")) != null'
  expect "Settings locks Face's lock and says what it stands in for" \
    "$(jq -c '.[] | select(.id == "graveklar.face-lock") | [.pinned, .shared, .sharedFor]' \
         "$H/.local/state/omarchy-profiles/plugins.json")" '. == [true, "clone", "Lock Screen"]'
  out=$(run plugin c disable graveklar.face-lock 2>&1); rc=$?
  expect "and switching it off in a profile is refused" "$(jq -nc --argjson rc "$rc" --arg o "$out" '{rc: $rc, o: $o}')" \
    '.rc != 0 and (.o | test("stands in for omarchy.lock"))'
fi
# Pinned by the user, the same: before, the clean profile left both locks on.
switch_to set master >/dev/null
run shared add graveklar.face-lock >/dev/null 2>&1
run create d --clean >/dev/null 2>&1
if switch_to set d; then
  expect "pinned in Profiles, a clean profile still keeps omarchy.lock off" "$(sj '.disabledPlugins')" \
    'index("omarchy.lock") != null and index("graveklar.face-lock") == null'
fi
end

if ((failed)); then echo "${RED}$passed passed, $failed failed${RESET}"; exit 1; fi
echo "${GREEN}$passed passed, 0 failed${RESET}"
