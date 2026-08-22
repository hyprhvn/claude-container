# claude-container

A containerized version of claude-code with rootless Podman, strict SELinux compatibility, SSH agent forwarding, modular XDG directory layout, and external skills support.

> [!important]
>
> This project uses Podman and strict SELinux confinement (`:z` labels).
> Because the user's `$HOME` root directory cannot be relabeled as `container_t`, running directly inside `$HOME` as the workspace target (`DIR`) is prohibited.

## Documentation

Comprehensive documentation for all subsystems is available in the [`docs/`](docs/README.md) directory:

- [Architecture & Containerization Overview](docs/architecture.md)
- [XDG Storage Specification & Directory Layout](docs/xdg-storage.md)
- [SSH Agent Forwarding & SELinux Policy](docs/ssh-agent-forwarding.md)
- [External Skills Management](docs/skills.md)
- [Migration & Initialization Guide](docs/migration.md)
- [Host Mounts & Git Configuration Forwarding](docs/mounting.md)
- [Testing & Podman-in-Podman (PinP)](docs/testing.md)

## Build

Build and push the OCI images with:

```bash
# log in to docker hub
podman login -u hyprhvn docker.io
# build the base container
podman build -f Containerfiles/Base -t docker.io/hyprhvn/claude-container:base
podman push docker.io/hyprhvn/claude-container:base
# build the full dev container
podman build -f Containerfiles/Full -t docker.io/hyprhvn/claude-container:full
podman push docker.io/hyprhvn/claude-container:full
```

## Directory Architecture & XDG Specification

Claude Code files and state are partitioned according to the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest).
Default locations can be overwritten using the `XDG_` env vars from the spec.

The directories are mounted directly to the locations Claude expects in the container:

| Category    | Default Host Path                 | Contents                                                                                                                                 |
| ----------- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **Config**  | `~/.config/claude-container`      | `CLAUDE.md`, `settings.json`, `rules/`, `themes/`, `output-styles/`, `agents/`, `workflows/`, `commands/`, `skills/`, `keybindings.json` |
| **State**   | `~/.local/state/claude-container` | `claude.json` (OAuth/trust/preferences), `agent-memory/`                                                                                 |
| **Cache**   | `~/.cache/claude-container`       | `projects/` (Session history & auto-memory indices/topics)                                                                               |
| **Data**    | `~/.local/share/claude-container` | External & imported skills data (`skills/`)                                                                                              |
| **Runtime** | `/run/user/$UID/claude-container` | SSH socket forwarder (`/root/.ssh/agent.sock` -- `mode=0700`)                                                                            |

## Setup & Migration

### Migrating Existing `~/.claude` Configuration

If you have an existing legacy `~/.claude` directory or `~/.claude.json` file, run the migration script:

```bash
# Preview what will be moved/created without modifying files
./scripts/migrate-from-home --dry-run

# Run migration (creates an automatic timestamped backup in ~/.claude.backup.<timestamp>)
./scripts/migrate-from-home

# Or copy instead of moving
./scripts/migrate-from-home --copy
```

If starting fresh without existing configuration, running `scripts/migrate-from-home` or launching `scripts/claude-container` automatically scaffolds the minimal required directory structure and a valid initial `claude.json`.

## Usage

Run Claude Code in the current workspace:

```bash
# Run in the current directory:
./scripts/claude-container

# Run in a specific project directory:
./scripts/claude-container /path/to/project

# Mount additional custom paths:
./scripts/claude-container -m /host/path:/container/path

# Pass additional container runtime flags:
./scripts/claude-container -C --privileged -C --device=/dev/fuse /workspace

# Pass arguments directly to claude inside the container:
./scripts/claude-container /workspace --help
./scripts/claude-container . -p "explain this codebase"
```

### External Skills Management

You can import skills from external repositories or private folders without modifying submodules:

1. **Config File (`skills.conf`):**
   Add directory paths (one per line) to `${XDG_CONFIG_HOME:-~/.config}/claude-container/skills.conf`:

   ```text
   # ~/.config/claude-container/skills.conf
   /home/user/src/my-private-skills
   ```

2. **Environment Variable:**
   Set `CLAUDE_SKILLS_DIR` to colon-separated paths:

   ```bash
   export CLAUDE_SKILLS_DIR="/path/to/skills-repo:/another/path/skills"
   ```

3. **Command Line Flag:**
   Pass one or more `--skills-dir` arguments:

   ```bash
   ./scripts/claude-container --skills-dir /path/to/skills-repo
   ```

## Install

Place `scripts/claude-container` and `scripts/migrate-from-home` in a directory on your `$PATH` (e.g. `~/.local/bin/`).
