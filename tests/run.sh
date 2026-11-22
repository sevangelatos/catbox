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

# --- extra paths ---
mkdir -p "$TMP/ws" "$TMP/ro" "$TMP/rw" "$TMP/rw/inner"
rm -rf "$TMP/rw/inner"
ln -s "$TMP/ro" "$TMP/rolink"

run --dry-run "$TMP/ws" --ro "$TMP/ro" --rw "$TMP/rw"
ok "ro mount" has "--ro-bind $TMP/ro $TMP/ro"
ok "rw mount" has "--bind $TMP/rw $TMP/rw"

run --dry-run "$TMP/ws" --ro "$TMP/rolink"
ok "symlink resolved" has "--ro-bind $TMP/ro $TMP/ro"

run --dry-run "$TMP/ws" --ro "$TMP/nope"
ok "missing path fails" test $RC -ne 0
ok "missing path message" errhas "does not exist"

run --dry-run "$TMP/ws" --ro
ok "missing value fails" test $RC -ne 0
run --dry-run "$TMP/ws" --ro -- true
ok "-- is not a path" test $RC -ne 0

run --dry-run "$TMP/ws" --ro /
ok "root fails" test $RC -ne 0
run --dry-run "$TMP/ws" --rw "$HOME"
ok "HOME fails" test $RC -ne 0
run --dry-run "$TMP/ws" --rw "$(dirname "$HOME")"
ok "parent of HOME fails" test $RC -ne 0
run --dry-run "$TMP/ws" --ro /usr/share
ok "inside system path fails" test $RC -ne 0
run --dry-run "$TMP/ws" --ro /tmp
ok "/tmp fails" test $RC -ne 0
run --dry-run "$TMP/ws" --ro /var
ok "parent of /var/tmp fails" test $RC -ne 0
run --dry-run "$TMP/ws" --ro "$TMP/ws"
ok "workspace overlap fails" test $RC -ne 0
run --dry-run "$TMP/ws" --ro "$TMP/ro" --rw "$TMP/rolink"
ok "duplicate extra path fails" test $RC -ne 0

# --- network ---
run --dry-run "$TMP/ws" --no-net
ok "no-net unshares net" has "--unshare-net"
ok "no-net drops share-net" hasnt "--share-net"
ok "no-net has no run dir" hasnt "/run/catbox"

run --dry-run "$TMP/ws" --forward 11434 -- echo hi
ok "forward implies unshare-net" has "--unshare-net"
ok "forward binds run dir" has "/run/catbox"
ok "forward uses init script" has "/bin/bash /run/catbox/init.sh echo hi"

run --dry-run "$TMP/ws" --forward 8080:9090 --forward 3000
ok "remap accepted" test $RC -eq 0

for bad in abc 0 65536 1:2:3 :80 80: -1; do
    run --dry-run "$TMP/ws" --forward "$bad"
    ok "invalid forward '$bad' fails" test $RC -ne 0
done
run --dry-run "$TMP/ws" --forward 8080:80
ok "privileged sandbox port fails" test $RC -ne 0
run --dry-run "$TMP/ws" --forward 80:8080
ok "privileged host port allowed" test $RC -eq 0
run --dry-run "$TMP/ws" --forward
ok "forward without value fails" test $RC -ne 0
run --dry-run "$TMP/ws" --forward 80:9090 --forward 81:9090
ok "duplicate sandbox port fails" test $RC -ne 0

echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]
