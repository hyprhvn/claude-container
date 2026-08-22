# SSH Agent Forwarding & SELinux Configuration

This document explains how host SSH agent forwarding is accomplished in `claude-container`, the SELinux permission challenges encountered with Unix domain stream sockets, and the Type Enforcement (CIL) policy solution.

## 1. Overview & Architecture

When authenticating against remote Git repositories (e.g., GitHub, GitLab) via SSH inside the container, Claude Code needs access to the host's active SSH agent keys (such as GNOME Keyring, `ssh-agent`, or 1Password).

The forwarding pipeline consists of:

1. **Host Socket Bridge (`socat`):** `scripts/claude-container` starts a background `socat` process forwarding connections from a temporary Unix socket to the host's `$SSH_AUTH_SOCK`:

   ```bash
   socat "UNIX-LISTEN:$RUNTIME_DIR/agent.sock,mode=777,fork" "UNIX-CLIENT:$SSH_AUTH_SOCK" &
   ```

2. **SELinux Inode Relabeling:** The temporary socket `/run/user/$UID/claude-container/agent.sock` is relabeled to `container_file_t`:

   ```bash
   chcon -t container_file_t "$RUNTIME_DIR/agent.sock"
   ```

3. **Container Bind Mount & Environment:** The socket and known hosts file are mounted into the container:
   - `-v "$HOME/.ssh/known_hosts:/etc/ssh/ssh_known_hosts:ro,z"`
   - `-v "$RUNTIME_DIR/agent.sock:/root/.ssh/agent.sock:z"`
   - `-e "SSH_AUTH_SOCK=/root/.ssh/agent.sock"`

## 2. The SELinux Socket Peer Mediation Problem

On SELinux-enforcing hosts (such as Fedora, RHEL, or CentOS), connecting to the forwarded socket inside the container initially fails:

```console
$ ssh-add -l
Error connecting to agent: Permission denied
```

### Root Cause Analysis

The failure is caused by **SELinux socket peer mediation**, not file path lookup or network namespaces:

1. **Filesystem Inode Access:** The container process running under `container_t` can access the filesystem socket inode (`sock_file`) because it was relabeled to `container_file_t`.
2. **Stream Socket Peer Access:** Connecting to a Unix domain stream socket requires a secondary kernel check:

   ```
   allow <client_domain> <server_domain>:unix_stream_socket { connectto };
   ```

3. When `socat` runs under the host user session, its process domain is `unconfined_t`. Therefore, when `ssh` or `ssh-add` (running in `container_t` inside Podman) attempts to connect, the kernel evaluates:

   ```
   allow container_t unconfined_t:unix_stream_socket { connectto };
   ```

4. By default, standard container SELinux policy allows `container_t` to connect only to peer sockets owned by `container_t` or selected system daemons (e.g., `sssd_t`), denying connections to `unconfined_t`.

This results in an AVC denial in `/var/log/audit/audit.log`:

```
type=AVC msg=audit(...): avc: denied { connectto } for pid=... comm="ssh-add"
    path="/run/user/1000/claude-container/agent.sock"
    scontext=system_u:system_r:container_t:s0:c286,c442
    tcontext=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023
    tclass=unix_stream_socket permissive=0
```

> **Note on `container_connect_any`:** The SELinux boolean `container_connect_any` only governs network TCP/UDP sockets (`tcp_socket` / `udp_socket`). It has no effect on Unix domain sockets (`unix_stream_socket`).

## 3. Evaluated Solutions & Why Option 1 Was Chosen

### Option 2 (Ruled Out): Transitioning `socat` to `container_t` (`runcon`)

Running `socat` on the host in `container_t` was evaluated and rejected:

- `socat` failed to bind to `$RUNTIME_DIR` (`user_tmp_t`), returning `bind(): Permission denied`.
- Even if `$RUNTIME_DIR` was relabeled, `socat` in `container_t` was denied connecting upstream to GNOME Keyring (`user_tmp_t:unix_stream_socket`).

### Option 1 (Adopted): Targeted CIL Policy Module

The cleanest, most robust solution is to install a minimal Common Intermediate Language (CIL) SELinux policy module granting `container_t` the `connectto` permission on `unconfined_t` stream sockets.

**CIL Policy Definition (`container_ssh_forward.cil`):**

```cil
(allow container_t unconfined_t (unix_stream_socket (connectto)))
```

## 4. Automated Policy Installation in `scripts/claude-container`

`scripts/claude-container` includes `ensure_selinux_policy()` which automates this check on startup:

1. Tests if SELinux is active via `selinuxenabled`.
2. Uses `sesearch` or `semodule` to verify if `(allow container_t unconfined_t (unix_stream_socket (connectto)))` is already loaded.
3. If missing, creates a temporary CIL file inside `$RUNTIME_DIR` and installs it using `sudo` or `doas`:

   ```bash
   semodule -i "$module_file"
   ```

### Manual Installation

If running on a system without passwordless sudo, the module can be installed manually once:

```bash
echo '(allow container_t unconfined_t (unix_stream_socket (connectto)))' | sudo semodule -i /dev/stdin
```

## 5. Verification & Diagnostics

Use the host diagnostic script `debug.sh` while the container is running to inspect SELinux contexts, socket labels, and policy rules:

```bash
./debug.sh
```

Inside the container, test SSH agent access:

```console
$ ssh-add -l
2048 SHA256:... user@hostname (RSA)
```

SSH operations (including `git push` and `git fetch` over SSH) will function without permission errors.
