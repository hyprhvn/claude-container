# SSH agent forwarding into the container

## Symptom

Inside the container, `ssh-add -l` fails:

```console
$ ssh-add -l
Error connecting to agent: Permission denied
```

On the host the same agent lists keys normally (GNOME Keyring owns `SSH_AUTH_SOCK`).

## Facts (evidence from `out.txt`)

- SELinux is **Enforcing** on the host.
- `container_connect_any` is **on**, but it governs TCP/UDP *ports* (`tcp_socket` / `udp_socket`), not Unix-domain sockets. It is irrelevant to the denial below.
- GNOME Keyring's agent socket is `/run/user/1000/gcr/ssh`, labeled `user_tmp_t`.
- The socat forwarder socket `/run/user/1000/claude-container/agent.sock` is labeled `container_file_t` via explicit `chcon`.
- When socat runs as `unconfined_t`, the audit log shows `container_t` processes (`ssh-add`, `ssh`) denied `connectto` on that socket:

  ```
  avc: denied { connectto } ...
      scontext=system_u:system_r:container_t:s0:c286,c442
      tcontext=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023
      tclass=unix_stream_socket
  ```

## Root cause

The blocker is **SELinux socket peer mediation**, not path lookup or network namespaces.

- A pathname (filesystem-bound) Unix socket is reached through VFS path lookup. The container reaches `/root/.ssh/agent.sock` via the bind mount.
- While `chcon -t container_file_t` successfully changes the socket inode's filesystem label (`sock_file`), Unix domain stream sockets require a second SELinux check: **`unix_stream_socket { connectto }`**.
- Under Linux SELinux policy, `connectto` is evaluated between the client domain (`container_t`) and the **server socket's creator / peer process context** (`unconfined_t` when socat runs directly in the host user session).
- `container_t` policy allows connecting only to peer sockets in `container_t` (and specific system daemons), not `unconfined_t`.

---

## Resolution Strategies

### Option 1: SELinux Policy Module (`container_ssh_forward`)

Install a targeted local SELinux Type Enforcement (TE) policy module granting container processes permission to connect to `unconfined_t` stream sockets.

**Policy definition (`container_ssh_forward.te`):**
```te
module container_ssh_forward 1.0;

require {
    type container_t;
    type unconfined_t;
    class unix_stream_socket connectto;
}

# Allow container processes to connect to stream sockets created by unconfined host processes
allow container_t unconfined_t:unix_stream_socket connectto;
```

**CIL syntax (`container_ssh_forward.cil`):**
```cil
(allow container_t unconfined_t (unix_stream_socket (connectto)))
```

**Installation (requires host sudo once):**
```bash
sudo semodule -i container_ssh_forward.cil
```

- **Pros:** Cleanest architecture. Forwarder runs simply on host; no domain transition or privilege elevation in the launcher script; preserves container isolation.
- **Cons:** Requires `sudo` on host once to load the policy module.

---

### Option 2: Domain Transition for Forwarder Process (`runcon`) — *Evaluated & Infeasible*

Attempting to run `socat` on the host within `container_t` via `runcon` fails because:
1. `socat` cannot create/bind the socket in `$XDG_RUNTIME_DIR/claude-container` (`user_tmp_t` dir) due to SELinux denying `container_t` write permission on host `user_tmp_t` directories (`bind(): Permission denied`).
2. Even if the directory is relabeled, `socat` in `container_t` would be denied connecting upstream to the GNOME Keyring socket (`user_tmp_t:unix_stream_socket`).

Therefore, **Option 1 (SELinux Policy Module)** is the correct and necessary solution.

---

## Recommended Fix (Option 1)

A CIL policy module `container_ssh_forward.cil` is provided in the repository root:

```cil
(allow container_t unconfined_t (unix_stream_socket (connectto)))
```

The launcher script `scripts/run-claude` automatically checks whether SELinux is active and if this rule is missing via `sesearch` / `semodule`. If the policy is not loaded, it prompts for installation (`sudo semodule -i ...`) on launch. It can also be loaded manually on the host:
```bash
sudo semodule -i container_ssh_forward.cil
```

### Verification & Results

Once loaded, the active SELinux policy allows container domains to connect to host forwarder sockets:
```
allow container_t unconfined_t:unix_stream_socket connectto;
```

Inside the container:
```console
$ ssh-add -l
# lists host SSH keys without error or denial
```
All AVC `connectto` denials are resolved.

