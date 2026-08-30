# Architecture & Containerization Overview

`claude-container` encapsulates [Claude Code](https://claude.com/product/claude-code) within a rootless [Podman](https://podman.io/) container. This architecture guarantees strong isolation, reproducibility, strict SELinux compliance, and a single unified on-disk storage directory that persists everything Claude writes.

## 1. High-Level Architecture

The host runner (`scripts/claude-container`) acts as an orchestration and configuration engine that:

1. Resolves host paths and parses user arguments.
2. Scaffolds the unified `claude-container` directory on the host and seeds missing `skel/` templates.
3. Sets up dynamic mounts for Git identity, the unified Claude directory (read-write parent, read-only instruction/executable trees), and external skills.
4. Manages a host-side `socat` bridge for SSH agent forwarding across SELinux boundaries.
5. Launches Claude Code inside rootless Podman as an interactive container.

```
                      +-------------------------------------------------+
                      |                   Host System                   |
                      |                                                 |
  User Terminal ----> | scripts/claude-container                        |
                      |   |                                             |
                      |   +-- Unified storage directory:                |
                      |   |     ~/.local/opt/claude-container           |
                      |   |       (CLAUDE_CONTAINER_DIR override)       |
                      |   |                                             |
                      |   +-- SSH Agent Forwarder (socat):              |
                      |   |     $SSH_AUTH_SOCK -> $CC_DIR/runtime/...   |
                      |   |     (SELinux CIL module: container_ssh_fwd) |
                      |   |                                             |
                      |   v                                             |
                      | Rootless Podman (docker.io/hyprhvn/...:full)    |
                      +-----------------------+-------------------------+
                                              |
                                              | mounts (:ro,z / :rw,z)
                                              v
                      +-------------------------------------------------+
                      |              Container Environment              |
                      |                                                 |
                      |   Working Directory: /path/to/project           |
                      |   Target: /root/.claude/...                     |
                      |   Target: /root/.claude.json                    |
                      |   Target: /root/.ssh/agent.sock                 |
                      |   Target: /root/.gitconfig                      |
                      |                                                 |
                      |   Process: claude (Alpine Linux 3.24)           |
                      +-------------------------------------------------+
```

## 2. Security Boundaries & Rootless Podman

### Rootless Execution & User Namespaces

- **Host User Safety:** The container runs under rootless Podman using user namespaces (`userns`). Even though the in-container process runs as `root` (UID 0), it maps directly to the unprivileged host user's UID/GID.
- **Filesystem Isolation:** The container cannot modify host system files outside the explicitly mounted paths.

### SELinux Multi-Category Security (MCS) Confinement

- Containers run under the confined `container_t` domain with unique MCS categories (e.g., `s0:c286,c442`).
- All bind mounts are passed with SELinux volume relabeling options (`:z` or `ro,z`), relabeling mounted host files with the shared `container_file_t` type.
- **Home Directory Restriction:** The user's top-level `$HOME` directory cannot be passed as the working directory (`DIR`). Attempting to relabel `$HOME` with `:z` would break host desktop security labels and system stability. `scripts/claude-container` strictly forbids `$DIR == $HOME`.

## 3. Container Image Hierarchy

The container environment is split into two layers defined in `Containerfiles/`:

### Base Image (`Containerfiles/Base`)

- **Base OS:** Alpine Linux 3.24.
- **Package Repository:** Official Anthropic Alpine repository (`https://downloads.claude.ai/claude-code/apk/stable`) signed with Anthropic's RSA public key (`https://downloads.claude.ai/keys/claude-code.rsa.pub`).
- **Installed Package:** `claude-code`.
- **Working Directory:** `/workspace`.
- **Entrypoint:** `claude`.
- **Image Tag:** `docker.io/hyprhvn/claude-container:base`.

### Full Image (`Containerfiles/Full`)

- **Base Layer:** `docker.io/hyprhvn/claude-container:base`.
- **Developer Tooling:** Installs core Linux command-line utilities, compilers, and interpreters required by Claude Code agents:
  - Shell & POSIX: `bash`, `coreutils`, `findutils`, `grep`, `sed`, `gawk`, `procps`, `iproute2`.
  - Networking & Fetching: `curl`, `wget`.
  - Version Control & Auth: `git`, `git-lfs`, `openssh-client`.
  - Serialization: `jq`.
  - Development & Compilation: `build-base`, `musl-dev`, `python3`, `py3-pip`.
- **Image Tag:** `docker.io/hyprhvn/claude-container:full`.

## 4. Building & Publishing Images

Images are built using standard Podman commands:

```bash
# Authenticate to registry
podman login -u hyprhvn docker.io

# 1. Build & push Base image
podman build -f Containerfiles/Base -t docker.io/hyprhvn/claude-container:base
podman push docker.io/hyprhvn/claude-container:base

# 2. Build & push Full image
podman build -f Containerfiles/Full -t docker.io/hyprhvn/claude-container:full
podman push docker.io/hyprhvn/claude-container:full
```

## 5. Architectural Subsystems

For detailed documentation on specific subsystems, refer to:

- [Unified Storage Layout](storage-layout.md) — The single `claude-container` directory, mount mapping, and `update-skel` template management.
- [Host Mounts & Git Forwarding](mounting.md) — Unified directory mounts, `-m/--mount` syntax and precedence, GNU Stow resolution, and Git configuration.
- [SSH Agent Forwarding & SELinux](ssh-agent-forwarding.md) — Peer mediation, CIL policy, and socat architecture.
- [External Skills Management](skills.md) — `skills.conf`, environment variables, multi-skill bundles, and CLI flags.
