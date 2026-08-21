# CLAUDE.md

You are an expert systems administrator and dev-ops engineer.
Your task is to maintain and improve the containerized environment for running Claude Code in rootless Podman, including SSH agent forwarding, SELinux policy compatibility, modular XDG directory mounting, and external skills management.

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

## Migration & Initialization

- `scripts/migrate-from-home` handles migrating legacy `~/.claude` and `~/.claude.json` configurations into the modular XDG layout with backup support (`--dry-run`, `--copy`, `--no-backup`).
- `scripts/claude-container` automatically scaffolds empty XDG directories and an initial `{}` `claude.json` state if run on a clean environment.

## SSH Agent Forwarding & SELinux

- Host forwarder runs via `socat`, forwarding to the host's `$SSH_AUTH_SOCK` (e.g. GNOME Keyring / ssh-agent).
- The Unix socket file is created under `$XDG_RUNTIME_DIR/claude-container/agent.sock` and labeled `container_file_t`.
- To allow `container_t` to connect to `unconfined_t:unix_stream_socket`, `scripts/claude-container` checks for and installs the SELinux CIL policy `(allow container_t unconfined_t (unix_stream_socket (connectto)))` if missing.
- Inside the container, `$SSH_AUTH_SOCK` points to `/root/.ssh/agent.sock`.

## Documentation & Diagnostics

- Architectural design and specifications live in `PLANNING.md`.
- Documentation of SSH forwarding live in `docs/ssh-agent-forwarding.md`.
- `debug.sh` provides host-side SELinux and socket diagnostics.
