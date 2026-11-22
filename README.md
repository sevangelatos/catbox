# catbox

A [bubblewrap](https://github.com/containers/bubblewrap) sandbox launcher for coding agents. Drops you into an isolated environment with a read-only system, a clean home directory, and a dedicated workspace.

## Prerequisites

- **bubblewrap** (`bwrap`) — `sudo apt install bubblewrap`

## Usage

```bash
catbox [WORKSPACE] [--gpu] [--ro PATH]... [--rw PATH]... [--no-net] [--forward PORT]... [--docker] [--dry-run] [-- COMMAND...]
```

| Mode | Example | Description |
|------|---------|-------------|
| Interactive | `catbox` | Launch interactive bash in `~/.sandboxes/default` |
| Named workspace | `catbox myproject` | Launch in `~/.sandboxes/myproject` |
| Existing directory | `catbox /path/to/dir` | Launch in any existing directory |
| Run a command | `catbox -- python script.py` | Run a command in the default workspace |
| Run in named workspace | `catbox dev -- python script.py` | Run a command in `./sandboxes/dev` |
| GPU Support | `catbox --gpu` | Passthrough GPU devices (NVIDIA / DRM) |
| Extra paths | `catbox --ro ~/data --rw /srv/out` | Mount extra paths read-only / read-write at the same path |
| Isolated network | `catbox --no-net` | Sandbox only has its own empty loopback |
| Forward a host port | `catbox --forward 11434` | Reach only host `127.0.0.1:11434` (implies `--no-net`) |
| Docker | `catbox --docker -- docker ps` | Let the sandbox use the host docker daemon (see warning below) |
| Dry run | `catbox --dry-run` | Print the `bwrap` command without running it |

## Security Model

- **User namespace** — maps your UID/GID inside the sandbox
- **PID namespace** — isolated process tree
- **IPC namespace** — isolated inter-process communication
- **No capabilities** — all Linux capabilities dropped
- **Die with parent** — the sandbox is killed when catbox exits
- **Read-only system** — `/usr`, `/bin`, `/lib`, `/lib64`, `/etc`, `/sbin`, `/opt` are mounted read-only
- **Clean home** — `$HOME` is a tmpfs with only whitelisted paths bound in:
  - `.bashrc`, `.gitconfig`, `.profile` (files)
  - `.pi`, `.local`, `.npm`, `.opencode`, `.config/opencode`, `.cache/opencode` (directories)
- **Temporary directories** — `/tmp`, `/var/tmp`, `/run` are tmpfs
- **Network** — shared with the host by default; `--no-net` / `--forward` isolate it (see below)

## Workspaces

Without arguments, catbox uses `~/.sandboxes/default`. Pass a name to create or reuse a workspace under `~/.sandboxes/`. Pass an absolute or relative path to use an existing directory directly.

When using an existing directory, the absolute path is preserved inside the sandbox — the workspace appears at the same path inside and outside the sandbox. Named workspaces are mounted at `~/workspace`.

Workspace names must be alphanumeric (dashes and underscores allowed).

## Extra paths

`--ro PATH` and `--rw PATH` (both repeatable) mount additional host paths at the same absolute path inside the sandbox. Symlinks are resolved first. catbox exits with an error if a path:

- does not exist
- is `/` or contains/equals `$HOME`
- overlaps a system path already mounted (`/usr`, `/etc`, `/opt`, `/bin`, `/lib`, `/lib64`, `/sbin`, `/snap`, `/proc`, `/dev`, `/sys`), or equals/contains `/tmp`, `/var/tmp` or `/run`
- overlaps the workspace or another extra path

## Network isolation

`--no-net` runs the sandbox in its own network namespace with only an empty loopback. The host's `localhost` is **not** reachable, so a local model server would be cut off too.

`--forward PORT` (repeatable, implies `--no-net`) exposes selected host loopback ports inside the sandbox:

- `--forward 11434` — host `127.0.0.1:11434` appears as `127.0.0.1:11434` in the sandbox
- `--forward 8080:9000` — host `127.0.0.1:8080` appears as sandbox `127.0.0.1:9000`

Details:

- Needs `socat` on the host (`sudo apt install socat`).
- Forwarding goes through unix sockets in a temporary directory under `$XDG_RUNTIME_DIR`, mounted at `/run/catbox`. Only the listed ports are reachable.
- The sandbox port must be >= 1024 (the sandbox has no capabilities to bind lower ports).
- Forwarders are removed when catbox exits, including when it is killed.
- Without internet access, `npm`, `pip`, `git` over https and similar tools do not work.
- Anything listening on a forwarded port gets full access from the sandbox.

## Docker

`--docker` binds the docker daemon socket into the sandbox at `/run/catbox/docker.sock` and sets `DOCKER_HOST` to it. The socket is chosen as follows:

1. the rootless socket `$XDG_RUNTIME_DIR/docker.sock`, if it exists
2. otherwise the rootful `/var/run/docker.sock`

> **Warning:** the daemon runs outside the sandbox. Access to the rootful socket is root-equivalent on the host (`docker run -v /:/host ...`), so the sandbox protections do not hold. A rootless daemon limits this to your user, but containers can still mount your real `$HOME`. catbox prints a warning to stderr in both cases. `--docker` is meant for agents you trust not to attack the sandbox.

Details:

- Your user needs access to the socket (the `docker` group for the rootful daemon).
- `~/.docker` is not mounted, so registry credentials and contexts stay out of the sandbox.
- `docker run -v` paths are resolved by the host daemon. A named workspace is therefore mounted at its real host path (`~/.sandboxes/NAME`) instead of `~/workspace`, so `-v "$PWD:/w"` works.
- Incompatible with `--no-net`/`--forward` (containers have full network access) and with `--ro` (a container can mount the path read-write). catbox exits with an error.

## Environment

Inside the sandbox:

- `HOME` — your real home path (backed by tmpfs + selective binds)
- `USER` / `LOGNAME` — your real username
- `PATH` — includes `~/.local/bin` and the detected `pi-node` bin directory
- Working directory — the workspace (preserves absolute path for existing directories, `~/workspace` for named workspaces)

## Tests

```bash
tests/run.sh
```

The tests use `--dry-run`, so no sandbox is started.
