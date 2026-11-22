#!/usr/bin/env bash
# Tests for catbox argument handling. Uses --dry-run, so no sandbox is started.
set -uo pipefail

CATBOX="$(cd "$(dirname "$0")/.." && pwd)/catbox"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ok NAME CONDITION-COMMAND...
ok() {
    local name="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $name"; fi
}

# run ARGS... : sets OUT (stdout), ERR (stderr), RC
run() {
    OUT="$("$CATBOX" "$@" 2>"$TMP/err")"; RC=$?
    ERR="$(<"$TMP/err")"
}

has()  { [[ "$OUT" == *"$1"* ]]; }
hasnt(){ [[ "$OUT" != *"$1"* ]]; }
errhas(){ [[ "$ERR" == *"$1"* ]]; }

# --- basics ---
run --dry-run "$TMP"
ok "dry-run succeeds" test $RC -eq 0
ok "dry-run prints bwrap" has "bwrap "
ok "dry-run has no banner" hasnt "Launching"
ok "die-with-parent" has "--die-with-parent"
ok "cap-drop ALL kept" has "--cap-drop ALL"
ok "default command is bash" has "/bin/bash"
ok "workspace bound at same path" has "--bind $TMP $TMP"
ok "network shared by default" has "--share-net"

run --dry-run "$TMP" -- echo hi
ok "command passed through" has "echo hi"
ok "no default bash with command" hasnt "/bin/bash"

run --dry-run "$TMP" -- ls -- --foo
ok "args after -- kept" has "-- --foo"

run --help
ok "help exits 0" test $RC -eq 0
ok "help shows usage" has "Usage: catbox"
run "$TMP" --help
ok "help works after other args" has "Usage: catbox"

run --bogus
ok "unknown option fails" test $RC -ne 0
ok "unknown option message" errhas "Unknown option: --bogus"

run --dry-run "bad name!"
ok "invalid workspace name fails" test $RC -ne 0

run --dry-run --gpu "$TMP"
ok "gpu flag accepted" test $RC -eq 0

run --dry-run newws_test-1
ok "named workspace mounted at ~/workspace" has "$HOME/workspace"
ok "dry-run does not create workspace" test ! -e "$HOME/.sandboxes/newws_test-1"

echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]
