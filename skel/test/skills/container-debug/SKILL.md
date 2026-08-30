---
name: container-debug
description: Set up and debug the containerized Claude Code environment — Podman-in-Podman, SSH agent forwarding, and SELinux. Use when asked to debug, test, or verify the container setup, SSH agent forwarding, socket labels, or SELinux denials.
---

# Container Debug

This skill debugs the container setup **from inside the Test container**
(`Containerfiles/Test`, image `claude-container:test`). In that environment
you *are* the "host" of a nested Podman-in-Podman setup, so everything is
observable and fixable in place — no host access needed.

## 1. Set up the test environment

```bash
./scripts/test-env
```

- The Test container must be started with a **selinuxfs bind mount**
  (e.g. `-v /sys/fs/selinux:/sys/fs/selinux:ro` — ro is sufficient, the
  image never writes selinuxfs): on an Enforcing host the `spc_t` domain
  is not allowed to mount selinuxfs itself (EPERM even `--privileged`),
  and without the bind `test-env` cannot detect SELinux at all.
  (`--privileged` is still required for the nested podman and the fixture.)
- It **hard-fails** (exit 1) if the host kernel has no SELinux — a
  container cannot enable it. Report that and stop; do not attempt label
  checks. Detection is via `/sys/fs/selinux/enforce` + `policy` directly,
  **not** `selinuxenabled` — the library's mount registry is unreliable in
  containers (observed: host Enforcing, yet "Disabled" behind a read-only
  bind).
- It is idempotent — rerun after changes. `./scripts/test-env --down` tears
  the fixture down.
- On success it builds the host-side fixture — a fixture `ssh-agent` (with a
  throwaway key) and a `socat` forwarder socket labeled `container_file_t` —
  and prints a status report plus a ready-to-run end-to-end command.

## 2. Run the decisive check

Execute the `podman run --entrypoint ssh-add ... -l` command printed in the
report. It starts a nested podman container connecting through the
forwarder — the same socket pipeline as production (container →
`container_file_t` socket → socat → agent).

**Domain caveat:** the nested container's domain follows the Test
container's domain. Observed: with the Test container in `spc_t` (rootless
launch, or `--privileged` — both the usual modes for this setup) the nested
container also runs in `spc_t`, so the check exercises the `spc_t → spc_t`
self-connect (allowed by the base policy — it passes without any preloaded
module). A `container_t` nested container only appears under a `container_t`
Test container, which this setup does not use. The *production* tuple
(container → host forwarder in `unconfined_t`) cannot be reproduced
in-container at all — no `unconfined_t` process exists inside the container;
that rule stays a host-side concern (the launcher's
`ensure_selinux_policy` on a real host).

- **The test key is listed** → the full SELinux/forwarding path works.
- **`Operation not permitted`** → SELinux denial; go to step 3.
- **`No such file or directory`** → forwarder not running; check
  `ps -eZ | grep socat`.
- **Nested podman fails to start** → storage issue; check
  `/etc/containers/storage.conf` (must be `driver = "vfs"`), and that the
  `full` image is available to the nested podman.
- **Nested podman fails with `netavark: iptables: No such file or
  directory`** → the image predates the `iptables` package (needed for
  nested bridge networking). The decisive check works around it with
  `--network none`; a full nested run that needs networking can pass
  `-C --network host` to the launcher instead.

## 3. Diagnose (on failure)

Check in this order:

1. **Policy rule** — SELinux checks socket **peer mediation**:
   `allow container_t <server_domain> (unix_stream_socket (connectto))`,
   where `<server_domain>` is the socat *process* domain (the Test
   container's domain, e.g. `spc_t`), **not** the socket file's label:
   ```bash
   cat /proc/self/attr/current   # the expected server domain
   ```
   Modules **cannot be verified from inside the Test container**: the
   image has no semodule/checkpolicy, and module names are not part of
   the merged kernel policy blob (`/sys/fs/selinux/policy`) — checkpolicy
   writes name+version only for module files, not the merged policy the
   kernel holds (`semodule -l` lists the on-disk policy store, not the
   blob). The ground truth is the decisive `ssh-add -l` check: a denial
   (`Operation not permitted`) means the rule is missing — load it on the
   host (rootful, from a **named file** so it can be listed/managed with
   `semodule`) and rerun:
   ```bash
   printf '%s' '(allow container_t spc_t (unix_stream_socket (connectto)))' \
     > /tmp/container_ssh_forward_spc_t.cil
   sudo semodule -i /tmp/container_ssh_forward_spc_t.cil
   ```
2. **Forwarder socket label** — must be type `container_file_t` (`:z` mount
   options do NOT relabel a live Unix socket). Coreutils `ls -lZ` is not
   built with SELinux support — use `getfilecon`. Files on the container
   rootfs are usually *created* already labeled `container_file_t` (and
   label writes are often refused there — `ENOTSUPP`), so check the type
   rather than forcing a relabel:
   ```bash
   getfilecon /var/test/claude-container/forward.sock
   ```
3. **Forwarder process** — socat must be listening:
   ```bash
   ps -eZ | grep socat
   ss -xlp | grep forward.sock
   ```
4. **Denials** — kernel AVC messages via selinuxfs (ro is enough; `dmesg`
   may be blocked by the host's `dmesg_restrict` even in a privileged
   container):
   ```bash
   cat /sys/fs/selinux/avc/messages | tail -20
   ```
   If `avc/messages` does not exist (host audit configuration), read the
   denials from the host's audit log/dmesg instead — from inside the
   container this step is simply unavailable.

## 4. Full nested run (optional, heavier)

To exercise the launcher end-to-end (its own forwarder, mounts, arg
collection), run the repository's launcher nested against the fixture agent:

```bash
SSH_AUTH_SOCK=/var/test/claude-container/agent.sock \
XDG_RUNTIME_DIR=/var/test/claude-container/runtime \
./scripts/claude-container <workspace> -p "Run ssh-add -l in a shell and reply with its exact output"
```

## What each signal means

| Symptom | Likely cause |
| --- | --- |
| `ssh-add -l` → `Operation not permitted` | missing `connectto` rule for the forwarder's server domain, or forwarder socket not `container_file_t` |
| `ssh-add -l` → `No such file or directory` | socat forwarder not running |
| nested podman never starts | storage driver not `vfs`, or `full` image not available |
| `test-env` fails "SELinux is not active" | host kernel without SELinux (cannot be fixed from inside) — or selinuxfs not mounted/visible: the `spc_t` domain may not mount it itself, so add the `-v /sys/fs/selinux:/sys/fs/selinux` bind |
| `test-env` NOTEs a module "cannot be verified" | expected in the Test image — modules are not verifiable in-container; run the decisive `ssh-add -l` check, which is the ground truth |

Full theory of the forwarding design: `docs/ssh-agent-forwarding.md`.
