# Testing & Podman-in-Podman (PinP) Guide

This document explains how to test `claude-container`, verify CLI argument passthrough, and run automated integration tests nested inside a container (Podman-in-Podman / PinP).

## 1. CLI Argument Passthrough

The launcher script `scripts/claude-container` supports two distinct levels of argument forwarding:

```text
claude-container [-h] [-v | -q] [-m MOUNT]... [--skills-dir DIR]...
                 [-C | --container-arg ARG]...
                 [DIR] [CLAUDE_ARGS...]
```

### A. Container Runtime Arguments (`-C`, `--container-arg`)

Pass extra arguments directly to the underlying `podman run` invocation before the image name. This is useful for passing security flags, capabilities, device nodes, or custom runtime environment variables:

```bash
# Pass privileged flag or custom devices
./scripts/claude-container -C --privileged -C --device=/dev/fuse /workspace

# Pass custom environment variable
./scripts/claude-container -C -e -C "DEBUG=1" /workspace
```

### B. Claude Arguments (`CLAUDE_ARGS...`)

Any arguments provided **after** the positional workspace directory `DIR` (or after a literal `--` argument separator) are passed directly to the `claude` executable inside the container:

```bash
# View claude help message
./scripts/claude-container . --help

# Run non-interactive prompt mode
./scripts/claude-container /workspace -p "Summarize git diff"

# Configure claude settings
./scripts/claude-container /workspace config
```

## 2. Podman-in-Podman (PinP) Testing

When testing `claude-container` from inside another container (such as inside a CI/CD runner or containerized development environment), nested container execution requires specific configuration.

### Outer Container Requirements

1. **Privileged Mode & Device Access:**
   The outer container must be run with `--privileged` (or `--device /dev/fuse` and `--cap-add SYS_ADMIN`).

2. **Storage Driver:**
   Nested overlayfs requires either:
   - `driver = "vfs"` in `/etc/containers/storage.conf` (reliable and works everywhere in testing).
   - Or `driver = "overlay"` with `mount_program = "/usr/bin/fuse-overlayfs"`.

### Example Test Container Setup

To run a nested test container from the host:

```bash
# Start an outer privileged test container
podman run --rm -it --privileged \
    -v "$PWD:/test-workspace:z" \
    -w /test-workspace \
    alpine:3.20 sh

# Inside the outer container, install required packages:
apk add bash podman fuse-overlayfs shadow socat coreutils git

# Configure storage driver to vfs:
mkdir -p /etc/containers
cat <<'EOF' > /etc/containers/storage.conf
[storage]
driver = "vfs"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"
EOF

# Run test suite:
./tests/test-pinp.sh
```

## 3. Automated Test Suite (`tests/test-pinp.sh`)

The automated script [`tests/test-pinp.sh`](../tests/test-pinp.sh) validates:

- Option parsing for basic (`-h`, `-v`, `-q`), advanced (`-m`, `--skills-dir`, `-C/--container-arg`), and positional arguments.
- Verification that container arguments appear before the image name in `podman run`.
- Verification that Claude trailing arguments appear after the image name in `podman run`.
- Isolated XDG directory layout and external skills mounting from `skills.conf`.
