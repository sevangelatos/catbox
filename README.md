# catbox

A [bubblewrap](https://github.com/containers/bubblewrap) sandbox launcher for coding agents. Drops you into an isolated environment with a read-only system, a clean home directory, and a dedicated workspace.

## Prerequisites

- **bubblewrap** (`bwrap`) — `sudo apt install bubblewrap`

## Usage

```bash
catbox [WORKSPACE] [-- COMMAND...]
```

| Mode | Example | Description |
|------|---------|-------------|
| Interactive | `catbox` | Launch interactive bash in `~/.sandboxes/default` |
| Named workspace | `catbox myproject` | Launch in `~/.sandboxes/myproject` |
| Existing directory | `catbox /path/to/dir` | Launch in any existing directory |
| Run a command | `catbox -- python script.py` | Run a command in the default workspace |
| Run in named workspace | `catbox dev -- python script.py` | Run a command in `./sandboxes/dev` |

## Security Model

- **User namespace** — maps your UID/GID inside the sandbox
- **PID namespace** — isolated process tree
- **IPC namespace** — isolated inter-process communication
- **No capabilities** — all Linux capabilities dropped
- **Read-only system** — `/usr`, `/bin`, `/lib`, `/lib64`, `/etc`, `/sbin`, `/opt` are mounted read-only
- **Clean home** — `$HOME` is a tmpfs with only whitelisted paths bound in:
  - `.bashrc`, `.gitconfig`, `.profile` (files)
  - `.pi`, `.local`, `.npm` (directories)
- **Temporary directories** — `/tmp`, `/var/tmp`, `/run` are tmpfs
- **Network** — shared with the host

## Workspaces

Without arguments, catbox uses `~/.sandboxes/default`. Pass a name to create or reuse a workspace under `~/.sandboxes/`. Pass an absolute or relative path to use an existing directory directly.

Workspace names must be alphanumeric (dashes and underscores allowed).

## Environment

Inside the sandbox:

- `HOME` — your real home path (backed by tmpfs + selective binds)
- `USER` / `LOGNAME` — your real username
- `PATH` — includes `~/.local/bin` and the detected `pi-node` bin directory
- Working directory — `$HOME/workspace` (the sandboxed workspace)
