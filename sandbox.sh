#!/usr/bin/env bash
set -euo pipefail

# --- Cleanup trap for shopt ---
cleanup() { shopt -u nullglob 2>/dev/null; }
trap cleanup EXIT

# --- Help ---
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: sandbox.sh [WORKSPACE] [-- COMMAND...]

Launch a bubblewrap sandbox for a coding agent.

Arguments:
  WORKSPACE        Existing directory to use as workspace, or name of a
                   new workspace under ./sandboxes/ (default: default)
  --               Optional separator before command args
  COMMAND          Command to run inside the sandbox

Examples:
  sandbox.sh                              # Use ./sandboxes/default
  sandbox.sh myproject                    # Use ./sandboxes/myproject
  sandbox.sh /path/to/existing/dir        # Use /path/to/existing/dir
  sandbox.sh dev -- python script.py
EOF
    exit 0
fi

# --- Configuration ---
WORKSPACE_INPUT="${1:-default}"
shift 2>/dev/null || true

# If input is an existing directory, use it directly.
# Otherwise, treat it as a workspace name under ./sandboxes/
if [[ -d "$WORKSPACE_INPUT" ]]; then
    HOST_WORKSPACE_PATH="$(realpath "$WORKSPACE_INPUT")"
else
    if ! [[ "$WORKSPACE_INPUT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Workspace name must be alphanumeric (dashes and underscores allowed)."
        exit 1
    fi
    BASE_WORKSPACE_DIR="$(pwd)/sandboxes"
    HOST_WORKSPACE_PATH="$BASE_WORKSPACE_DIR/$WORKSPACE_INPUT"
fi

REAL_USER="$USER"
REAL_HOME="$HOME"
REAL_UID=$(id -u)
REAL_GID=$(id -g)

# --- Detect pi-node directory (for node, npm, pi binaries) ---
PI_NODE_BIN=
shopt -s nullglob
for dir in "$REAL_HOME"/.local/share/pi-node/node-*/bin; do
    [ -d "$dir" ] && PI_NODE_BIN="$dir" && break
done

# --- Prerequisites ---
if ! command -v bwrap &> /dev/null; then
    echo "Error: bubblewrap (bwrap) is not installed."
    echo "Install with: sudo apt install bubblewrap"
    exit 1
fi

# --- Create workspace directory if not already exists ---
mkdir -p "$HOST_WORKSPACE_PATH"

echo "🚀 Launching coding agent sandbox..."
echo "👤  User: $REAL_USER (UID=$REAL_UID, GID=$REAL_GID)"
echo "📂  Workspace: $HOST_WORKSPACE_PATH"
echo "🔒  System: RO  |  Home: whitelist-only  |  Namespaces: user+pid+ipc"
echo "--------------------------------------------------"

# --- Build conditional arguments ---
SNAP_ARG=()
[[ -d /snap ]] && SNAP_ARG=(--ro-bind /snap /snap)

BASHRC_ARG=()
[[ -f "$REAL_HOME/.bashrc" ]] && BASHRC_ARG=(--bind "$REAL_HOME/.bashrc" "$REAL_HOME/.bashrc")

# Build the bwrap command as an array
BWRAP_ARGS=(
    --unshare-user
    --uid "$REAL_UID"
    --gid "$REAL_GID"
    --cap-drop ALL
    --unshare-pid
    --unshare-ipc

    --ro-bind /usr /usr
    --ro-bind /bin /bin
    --ro-bind /lib /lib
    --ro-bind /lib64 /lib64
    --ro-bind /etc /etc
    --ro-bind /sbin /sbin
    --ro-bind /opt /opt
    "${SNAP_ARG[@]}"

    --tmpfs /tmp
    --tmpfs /var/tmp
    --tmpfs /run
    --proc /proc
    --dev /dev

    --tmpfs "$REAL_HOME"
    --bind "$REAL_HOME/.local" "$REAL_HOME/.local"
    --bind "$REAL_HOME/.npm" "$REAL_HOME/.npm"
    --bind "$REAL_HOME/.gitconfig" "$REAL_HOME/.gitconfig"
    "${BASHRC_ARG[@]}"
    --bind "$REAL_HOME/.profile" "$REAL_HOME/.profile"
    --bind "$REAL_HOME/.pi" "$REAL_HOME/.pi"
    --bind "$HOST_WORKSPACE_PATH" "$REAL_HOME/workspace"

    --share-net
    --setenv HOME "$REAL_HOME"
    --setenv USER "$REAL_USER"
    --setenv LOGNAME "$REAL_USER"
    --setenv PATH "$REAL_HOME/.local/bin${PI_NODE_BIN:+:$PI_NODE_BIN}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    --chdir "$REAL_HOME/workspace"
)

exec bwrap "${BWRAP_ARGS[@]}" /bin/bash "$@"
