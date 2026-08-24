# CLAUDE.md

You are an expert systems administrator and dev-ops engineer.
Your task is to maintain and improve the containerized environment for running Claude Code in rootless Podman, including SSH agent forwarding, SELinux policy compatibility, modular XDG directory mounting, external skills management, and container testing.

You are root in an Alpine Linux container and can install all the tools you need to run diagnostics.

## Architecture, Storage & XDG Directory Layout

Claude Code container storage is divided into modular XDG base directories:
- **Config** (`$XDG_CONFIG_HOME/claude-container`): `CLAUDE.md`, `settings.json`, `rules/`, `themes/`, `output-styles/`, `agents/`, `workflows/`, `commands/`, `skills/`, `keybindings.json` mounted into `/root/.claude/...`.
- **State** (`$XDG_STATE_HOME/claude-container`): `claude.json` mounted to `/root/.claude.json` and `agent-memory/` mounted to `/root/.claude/agent-memory`.
- **Cache** (`$XDG_CACHE_HOME/claude-container`): `projects/` mounted to `/root/.claude/projects`.
- **Data** (`$XDG_DATA_HOME/claude-container`): `skills/` for external/imported skills.
- **Runtime** (`$XDG_RUNTIME_DIR/claude-container`): Live sockets and temporary files.

External skills are discoverable and mounted from:
1. `$CONFIG_DIR/skills.conf`
2. `CLAUDE_SKILLS_DIR` environment variable
3. `--skills-dir <DIR>` CLI flag

## CLI Argument Forwarding

- Container arguments are passed via `-C` / `--container-arg <ARG>` (e.g. `--privileged`).
- Claude arguments are passed following the workspace directory `[DIR] [CLAUDE_ARGS...]` or after `--`.

## Migration & Initialization

- `scripts/migrate-from-home` handles migrating legacy `~/.claude` and `~/.claude.json` configurations into the modular XDG layout with backup support (`--dry-run`, `--copy`, `--no-backup`).
- On initial rollout, `scripts/migrate-from-home` seeds starter files from `skel/` (global `CLAUDE.md`, container rule `rules/container.md`, baseline `claude.json`) non-destructively — existing files are never overwritten.
- `scripts/claude-container` automatically scaffolds empty XDG directories and an initial `{}` `claude.json` state if run on a clean environment.

## SSH Agent Forwarding & SELinux

- Host forwarder runs via `socat`, forwarding to the host's `$SSH_AUTH_SOCK` (e.g. GNOME Keyring / ssh-agent).
- The Unix socket file is created under `$XDG_RUNTIME_DIR/claude-container/agent.sock` and labeled `container_file_t`.
- To allow `container_t` to connect to `unconfined_t:unix_stream_socket`, `scripts/claude-container` checks for and installs the SELinux CIL policy `(allow container_t unconfined_t (unix_stream_socket (connectto)))` if missing.
- Inside the container, `$SSH_AUTH_SOCK` points to `/root/.ssh/agent.sock`.

## Testing & Diagnostics

- Detailed technical documentation is located in `docs/`:
  - `docs/architecture.md`: Overall containerization architecture and security model.
  - `docs/xdg-storage.md`: Complete XDG storage layout and mount mappings.
  - `docs/ssh-agent-forwarding.md`: SSH socket proxying and SELinux CIL policy.
  - `docs/skills.md`: External skills management and loading logic.
  - `docs/migration.md`: Legacy setup migration and fresh initialization.
  - `docs/mounting.md`: Host mounts, custom `-m` mounts, and Git forwarding.
  - `docs/testing.md`: Testing with Podman-in-Podman (PinP) and argument passthrough.
- `tests/test-pinp.sh` runs automated test suites for argument collection and PinP readiness.
- `debug.sh` provides host-side SELinux and socket diagnostics.
