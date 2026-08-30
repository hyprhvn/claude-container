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
    alpine:3.24 sh

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

- **PinP tooling:** `podman`, `fuse-overlayfs`, `shadow`, `iptables` (nested netavark needs it for bridge networking; `--network none` containers skip it)
- **SELinux tooling:** `libselinux-utils` (`getfilecon`, `setfilecon`, `getenforce`, `selinuxenabled`, …) — note the Alpine gaps: no `chcon` and **no `semodule` binary** (the `semodule-utils` package ships only the `semodule_*` helpers, and the repo has no `checkpolicy` package). Consequences: `test-env` verifies socket labels with `getfilecon`/`setfilecon`, and — since it cannot compile CIL **and** module names are not stored in the merged kernel policy blob (`/sys/fs/selinux/policy` holds the merged `POLICY_KERN`; checkpolicy writes name+version only for module files) — it cannot verify policy modules at all; it prints the host-side `semodule -i` command instead. The behavioral end-to-end check remains the ground truth.

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
2. Uses `selinuxfs` for detection — it mounts it if the runtime didn't provide it, but in practice the runtime must supply the bind (see above).
3. Writes the nested `storage.conf` with the `vfs` driver.
4. Builds the host-side fixture: a **fixture `ssh-agent`** (stand-in for the host user's agent, e.g. GNOME Keyring, holding a throwaway key) plus a **`socat` forwarder socket** of type `container_file_t` — the same pipeline as the real launcher. It verifies the socket's type (and relabels only when the filesystem allows it — container rootfs storage often refuses `security.selinux` writes, though files there are created already labeled `container_file_t`).
5. Verifies the policy via socket **peer mediation**: the nested container connects to the forwarder, whose *server process* runs in the Test container's domain (e.g. `spc_t`), so the exercised rule is `(allow <nested-domain> <that-domain> (unix_stream_socket (connectto)))`. Observed: with the Test container in `spc_t` (rootless or `--privileged` launch — the usual modes) the nested container is also `spc_t`, so the check exercises the base-policy-allowed `spc_t → spc_t` self-connect; the production tuple (container → host forwarder in `unconfined_t`) cannot be reproduced in-container and remains a host-side concern. The modules are **not verifiable from inside the image** (no semodule/checkpolicy, and module names are not stored in the merged kernel policy blob that `/sys/fs/selinux/policy` holds — checkpolicy writes name+version only for module files), so `test-env` prints a NOTE with the host-side install command instead of gating; the decisive `ssh-add -l` check is the ground truth. Load modules on the host from **named files** (e.g. `container_ssh_forward[_<domain>].cil`) so they can be listed and managed with `semodule`.
6. Prints a status report including a ready-to-run `podman run ... ssh-add -l` command that is the decisive end-to-end check.

`./scripts/test-env --down` tears the fixture down.

**Gotchas** (from the in-container verification runs):

- **First run pulls the image** — the decisive check's nested `podman run`
  pulls `docker.io/hyprhvn/claude-container:full` into the nested vfs
  storage the first time; plan for a multi-minute pull.
- **The image's `ENTRYPOINT` is `claude`** — the decisive command therefore
  overrides it with `--entrypoint ssh-add` (the report prints the full
  command ready to run).
- **The fixture lives in `/var/test/claude-container/`** (override with
  `CLAUDE_TEST_DIR`), deliberately *not* in the launcher's
  `$CC_DIR/runtime` — the nested launcher cleans up its own runtime
  directory on exit, which would kill the fixture.
- **`:z` does not relabel a live Unix socket** — the explicit
  `chcon`/`setfilecon` to `container_file_t` is what grants access.
- **Diagnostics inside the image:** `dmesg` is usually blocked by the
  host's `dmesg_restrict` (even `--privileged`); coreutils `ls -lZ` is not
  built with SELinux support — use `getfilecon`. Read denials from
  `/sys/fs/selinux/avc/messages` (may not exist, depending on host audit
  configuration — then the host's audit log is the only source).

### 3.2 Letting the Agent Debug Itself

The `container-debug` skill guides the agent through the full loop:
`test-env` → nested `./scripts/claude-container` run → label/policy/process
inspection → `ssh-add -l` end-to-end through the socat forwarder. It is
baked into the image at `/root/.claude/skills/container-debug/`.

**Caveat — the launcher shadows it.** When you start the Test container
through `scripts/claude-container` (rather than raw `podman run`), the
launcher bind-mounts the host's unified directory (`$CC_DIR`) read-write
over `/root/.claude/`, hiding everything baked into the image
(`CLAUDE.md`, `rules/`, the container-debug skill). A raw `podman run` has
no such mount, so the skill is visible there. To use it through the
launcher, copy it into the workspace first
(`cp -r skel/test/skills/container-debug <workspace>/.claude/skills/`).
Ask for it directly:

```bash
# inside the Test container, after ./scripts/test-env:
claude -p "Use the container-debug skill to verify the SSH agent forwarding setup and report what you find."
```

## 4. Automated Test Suite (`tests/test-pinp.sh`)

The automated script [`tests/test-pinp.sh`](../tests/test-pinp.sh) runs
entirely against a temporary `CLAUDE_CONTAINER_DIR` and a fake `$HOME`
(no Podman required for the storage tests) and validates:

- **Syntax:** `bash -n` for all three scripts, plus `shellcheck` when
  available.
- **One-time seeding:** `update-skel --seed` on a clean environment seeds
  the full `skel/` set (including `settings.json`, `statusline.sh`,
  `hooks/`) and writes `.skel-manifest.tsv`; `skel/test/` is never seeded.
- **Non-destructive re-seeding:** an existing user file survives a
  re-run.
- **`update-skel` semantics:** manifest hash correctness; idempotent,
  silent re-seed; modified destinations survive `--seed`/`--update`;
  skel-template refresh via a temporary `CLAUDE_CONTAINER_SKEL` copy
  (`--seed` refuses, `--update` refreshes); `--force <path>` restores and
  leaves a `.bak` sidecar; bare `--force` forces all tracked files; stow
  symlinks are never replaced and lose their manifest entry; `--dry-run`
  leaves the tree byte-identical.
- **Unified mounts:** after the one-time install-time seed, a mock
  `podman` run on a clean `CLAUDE_CONTAINER_DIR` captures the `rw,z` parent
  mount, the `claude.json` file mount, all seven `ro,z`
  instruction/executable tree submounts, and per-skill `ro,z` mounts from
  `skills.conf`.
- **Argument passthrough:** container arguments (`-C`) before the image
  name, Claude trailing arguments after it, `-m` custom mounts, `-w`
  workspace, and the literal `--` separator.
- **`test-env` sanity:** syntax, `--help`, the baked `container-debug`
  skill, and the SELinux hard-fail contract.
