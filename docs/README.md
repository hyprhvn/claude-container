# Documentation Index

This directory contains comprehensive technical documentation for the `claude-container` architecture, storage partitioning, SELinux policies, testing, and operational workflows.

## Technical Guides

1. **[Architecture & Containerization Overview](architecture.md)**
   - High-level architecture and security boundaries.
   - Rootless Podman execution and user namespaces.
   - Base (`Containerfiles/Base`) and Full (`Containerfiles/Full`) image layers.
   - Build, push, and container lifecycles.
2. **[Unified Storage Layout](storage-layout.md)**
   - The single unified `claude-container` directory
     (`~/.local/opt/claude-container`, `CLAUDE_CONTAINER_DIR` override) and
     why one directory replaced the XDG split.
   - Mapping rules to container `/root/.claude/...` target paths.
   - Mount modes (`rw,z` parent, `ro,z` instruction/executable trees).
   - The `skel/` template set and provenance-tracked one-time seeding via
     `scripts/update-skel` (full reference).
3. **[SSH Agent Forwarding & SELinux Configuration](ssh-agent-forwarding.md)**
   - Socket forwarding pipeline using `socat`.
   - The SELinux peer mediation problem on Unix domain stream sockets (`unix_stream_socket connectto`).
   - Why `container_connect_any` and `runcon` do not solve Unix socket denials.
   - The Type Enforcement CIL policy module (`(allow container_t unconfined_t (unix_stream_socket (connectto)))`).
   - Container domains in practice (`container_t` vs `spc_t` for rootless/privileged launches) and the required rule per mode.
   - Two-level verification: live-host checks and the self-contained in-container test environment.
4. **[External Skills Management](skills.md)**
   - Loading external skills from private repos and external directories.
   - Configuration methods: `skills.conf`, `CLAUDE_SKILLS_DIR` env var, and `--skills-dir` CLI flag.
   - Single-skill vs multi-skill bundle auto-detection.
   - GNU Stow symlink resolution.
5. **[Host Mounts & Git Forwarding](mounting.md)**
   - Custom bind mounts via `-m/--mount` syntax.
   - Read-only Git configuration forwarding (`.gitconfig` and `.config/git`).
   - GNU Stow symlink traversal with `add_dir_mounts`.
   - SELinux `:z` volume relabeling and the `$HOME` boundary safety restriction.
6. **[Testing & Podman-in-Podman (PinP)](testing.md)**
   - Container argument passthrough (`-C`, `--container-arg`).
   - Claude trailing arguments forwarding.
   - Podman-in-Podman (PinP) testing requirements and outer container setup.
   - Test image (`Containerfiles/Test`) and the `scripts/test-env` fixture (SELinux hard gate, socket labels, decisive `ssh-add -l` check).
   - Automated testing suite (`tests/test-pinp.sh`).
