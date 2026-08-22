# Documentation Index

This directory contains comprehensive technical documentation for the `claude-container` architecture, storage partitioning, SELinux policies, testing, and operational workflows.

---

## Technical Guides

1. **[Architecture & Containerization Overview](architecture.md)**
   - High-level architecture and security boundaries.
   - Rootless Podman execution and user namespaces.
   - Base (`Containerfiles/Base`) and Full (`Containerfiles/Full`) image layers.
   - Build, push, and container lifecycles.

2. **[XDG Storage Specification & Directory Layout](xdg-storage.md)**
   - Modular breakdown of Claude Code's storage into standard XDG Base Directories:
     - **Config:** `~/.config/claude-container`
     - **State:** `~/.local/state/claude-container`
     - **Cache:** `~/.cache/claude-container`
     - **Data:** `~/.local/share/claude-container`
     - **Runtime:** `/run/user/$UID/claude-container`
   - Mapping rules to container `/root/.claude/...` target paths.
   - Mount modes (`rw,z`, `ro,z`).

3. **[SSH Agent Forwarding & SELinux Configuration](ssh-agent-forwarding.md)**
   - Socket forwarding pipeline using `socat`.
   - The SELinux peer mediation problem on Unix domain stream sockets (`unix_stream_socket connectto`).
   - Why `container_connect_any` and `runcon` do not solve Unix socket denials.
   - The Type Enforcement CIL policy module (`(allow container_t unconfined_t (unix_stream_socket (connectto)))`).
   - Host diagnostics via `debug.sh`.

4. **[External Skills Management](skills.md)**
   - Loading external skills from private repos and external directories.
   - Configuration methods: `skills.conf`, `CLAUDE_SKILLS_DIR` env var, and `--skills-dir` CLI flag.
   - Single-skill vs multi-skill bundle auto-detection.
   - GNU Stow symlink resolution.

5. **[Migration & Initialization Guide](migration.md)**
   - Migrating from monolithic `~/.claude` and `~/.claude.json` using `scripts/migrate-from-home`.
   - Dry-run preview mode (`--dry-run`), non-destructive copy mode (`--copy`), and automated backups.
   - Fresh installation and zero-config directory scaffolding.

6. **[Host Mounts & Git Forwarding](mounting.md)**
   - Custom bind mounts via `-m/--mount` syntax.
   - Read-only Git configuration forwarding (`.gitconfig` and `.config/git`).
   - GNU Stow symlink traversal with `add_dir_mounts`.
   - SELinux `:z` volume relabeling and the `$HOME` boundary safety restriction.

7. **[Testing & Podman-in-Podman (PinP)](testing.md)**
   - Container argument passthrough (`-C`, `--container-arg`).
   - Claude trailing arguments forwarding.
   - Podman-in-Podman (PinP) testing requirements and outer container setup.
   - Automated testing suite (`tests/test-pinp.sh`).
