# claude-container

A containerized version of claude-code with rootless Podman, strict SELinux compatibility, SSH agent forwarding, a single unified storage directory that persists everything, and external skills support.

> [!important]
>
> This project uses Podman and strict SELinux confinement (`:z` labels).
> Because the user's `$HOME` root directory cannot be relabeled as `container_t`, running directly inside `$HOME` as the workspace target (`DIR`) is prohibited.

## Documentation

Comprehensive documentation for all subsystems is available in the [`docs/`](docs/README.md) directory:

- [Architecture & Containerization Overview](docs/architecture.md)
- [Unified Storage Layout](docs/storage-layout.md)
- [SSH Agent Forwarding & SELinux Policy](docs/ssh-agent-forwarding.md)
- [External Skills Management](docs/skills.md)
- [Host Mounts & Git Configuration Forwarding](docs/mounting.md)
- [Testing & Podman-in-Podman (PinP)](docs/testing.md)

## Build

Build and push the OCI images with:

Run all builds from the repository root (the build context, needed by `Containerfiles/Test`):

```bash
# log in to docker hub
podman login -u hyprhvn docker.io
# build the base container
podman build -f Containerfiles/Base -t docker.io/hyprhvn/claude-container:base .
podman push docker.io/hyprhvn/claude-container:base
# build the full dev container
podman build -f Containerfiles/Full -t docker.io/hyprhvn/claude-container:full .
podman push docker.io/hyprhvn/claude-container:full
# build the test/self-debug container (PinP + SELinux tooling)
podman build -f Containerfiles/Test -t docker.io/hyprhvn/claude-container:test .
podman push docker.io/hyprhvn/claude-container:test
```

## Directory Layout

All of Claude Code's files and state live in **one directory** on the host:

```text
$CC_DIR = ${CLAUDE_CONTAINER_DIR:-$HOME/.local/opt/claude-container}
```

It is mounted read-write as the container's `/root/.claude`, so **everything** Claude writes persists — config, `claude.json`, session history, auto-memory, plugins, and any state directory Claude grows later. The instruction/executable trees (`rules/`, `agents/`, `hooks/`, `themes/`, `output-styles/`, `workflows/`, `commands/`) are re-mounted read-only on top, so a container cannot plant instructions or executables for the next session. Full spec: [Unified Storage Layout](docs/storage-layout.md).

| Host (`$CC_DIR/…`)   | Container               | Mode   |
| -------------------- | ----------------------- | ------ |
| (whole directory)    | `/root/.claude`         | `rw,z` |
| `claude.json`        | `/root/.claude.json`    | `rw,z` |
| the `ro` trees¹      | `/root/.claude/<same>`  | `ro,z` |
| `runtime/agent.sock` | `/root/.ssh/agent.sock` | `z`    |

¹ `rules/`, `agents/`, `hooks/`, `themes/`, `output-styles/`,
`workflows/`, `commands/`

## Setup

The launcher scaffolds the unified directory structure and a minimal
`claude.json` automatically on first run. The starter templates (global
instructions `CLAUDE.md`, `settings.json` with statusline + `SessionStart`
hook wiring, container rule `rules/container.md`, `hooks/`,
`statusline.sh`) are seeded by a **one-time install step**, run once from a
repository checkout:

```bash
/path/to/claude-container/scripts/update-skel --seed
```

Seeding is provenance-tracked (see [Unified Storage
Layout](docs/storage-layout.md)); the launcher itself neither seeds nor
migrates anything.

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
   Add directory paths (one per line) to `$CC_DIR/skills.conf`
   (`~/.local/opt/claude-container/skills.conf` by default):

   ```text
   # ~/.local/opt/claude-container/skills.conf
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

The launcher is self-contained: copy `scripts/claude-container` into a
directory on your `$PATH` (e.g. `~/.local/bin/`). It only needs the unified
directory (created automatically) — no other files.

`scripts/update-skel` is run from the repository (or anywhere it sits next
to `skel/`; set `CLAUDE_CONTAINER_SKEL` to point at the templates if you
move it). It is the one-time setup, and the later template refresh:

```bash
# one-time: seed the starter templates into the unified directory
/path/to/claude-container/scripts/update-skel --seed

# later, when the repository's skel/ changes: refresh the templates
/path/to/claude-container/scripts/update-skel --update
```
