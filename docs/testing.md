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

## 3. Test Image (`Containerfiles/Test`)

`Containerfiles/Test` builds the image `docker.io/hyprhvn/claude-container:test`: the Full container plus the tools to run and debug the whole setup **from inside the container** (Podman-in-Podman, no host access needed):

- **PinP tooling:** `podman`, `fuse-overlayfs`, `shadow`
- **SELinux tooling:** `libselinux-utils` (`getfilecon`, `setfilecon`, `getenforce`, `selinuxenabled`, …) — note the Alpine gaps: no `chcon` and **no `semodule` binary** (the `semodule-utils` package ships only the `semodule_*` helpers, and the repo has no `checkpolicy` package). Consequences: `test-env` verifies socket labels with `getfilecon`/`setfilecon`, checks policy modules by scanning the `/sys/fs/selinux/policy` blob, and — since it cannot compile CIL — tells you to load missing modules on the host (rootful `semodule -i`). The behavioral end-to-end check remains the ground truth.

### 3.1 Setting Up the Environment (`scripts/test-env`)

Inside the Test container (launched from the repository), run. The
`selinuxfs` bind is **required** — on an Enforcing host the `spc_t` domain
cannot mount selinuxfs itself (EPERM even `--privileged`), and without it
`test-env` cannot detect SELinux at all. `:ro` is sufficient: the image
never writes selinuxfs (it cannot load policy modules; that is host-side):

```bash
podman run -it --rm --privileged \
    -v /sys/fs/selinux:/sys/fs/selinux:ro \
    -v "$PWD":/workspace:z -w /workspace \
    docker.io/hyprhvn/claude-container:test

# inside:
./scripts/test-env
```

`test-env` is the testing-environment setup and a **hard gate**:

1. **SELinux is required.** A container cannot enable the kernel security module — it inherits the host kernel's state. It detects SELinux from `/sys/fs/selinux` directly (enforce file + non-empty policy), **not** from `selinuxenabled` — the library's mount registry is unreliable in containers (observed: host Enforcing, yet "Disabled" behind a read-only bind). If no usable SELinux is found, `test-env` exits non-zero. (Permissive mode is accepted with a warning; denials simply won't be enforced.)
2. Uses `selinuxfs` for detection and module checks — it mounts it if the runtime didn't provide it, but in practice the runtime must supply the bind (see above).
3. Writes the nested `storage.conf` with the `vfs` driver.
4. Builds the host-side fixture: a **fixture `ssh-agent`** (stand-in for the host user's agent, e.g. GNOME Keyring, holding a throwaway key) plus a **`socat` forwarder socket** of type `container_file_t` — the same pipeline as the real launcher. It verifies the socket's type (and relabels only when the filesystem allows it — container rootfs storage often refuses `security.selinux` writes, though files there are created already labeled `container_file_t`).
5. Verifies the policy via socket **peer mediation**: the nested `container_t` connects to the forwarder, whose *server process* runs in the Test container's domain (e.g. `spc_t`), so it ensures `(allow container_t <that-domain> (unix_stream_socket (connectto)))` — and keeps the canonical `unconfined_t` rule (real hosts) in sync. This image cannot compile CIL, so a missing module produces a hard error pointing at the host-side `semodule -i` command. Modules are detected **by name**, so load them from named files (e.g. `container_ssh_forward[_<domain>].cil`) — a module installed via `semodule -i /dev/stdin` is invisible to the check.
6. Prints a status report including a ready-to-run `podman run ... ssh-add -l` command that is the decisive end-to-end check.

`./scripts/test-env --down` tears the fixture down.

### 3.2 Letting the Agent Debug Itself

The `container-debug` skill guides the agent through the full loop:
`test-env` → nested `./scripts/claude-container` run → label/policy/process
inspection → `ssh-add -l` end-to-end through the socat forwarder. It is
baked into the image at `/root/.claude/skills/container-debug/`.

**Caveat — the launcher shadows it.** When you start the Test container
through `scripts/claude-container` (rather than raw `podman run`), the
launcher bind-mounts the host's `$XDG_CONFIG_HOME/claude-container/skills/`
over `/root/.claude/skills/`, hiding the baked skill (and the baked
`CLAUDE.md`/`rules/`). A raw `podman run` has no such mount, so the skill is
visible there. To use it through the launcher, copy it into the workspace
first (`cp -r skel/test/skills/container-debug <workspace>/.claude/skills/`).
Ask for it directly:

```bash
# inside the Test container, after ./scripts/test-env:
claude -p "Use the container-debug skill to verify the SSH agent forwarding setup and report what you find."
```

## 4. Automated Test Suite (`tests/test-pinp.sh`)

The automated script [`tests/test-pinp.sh`](../tests/test-pinp.sh) validates:

- Option parsing for basic (`-h`, `-v`, `-q`), advanced (`-m`, `--skills-dir`, `-C/--container-arg`), and positional arguments.
- Verification that container arguments appear before the image name in `podman run`.
- Verification that Claude trailing arguments appear after the image name in `podman run`.
- Isolated XDG directory layout and external skills mounting from `skills.conf`.
