# TODO — SSH agent forwarding

## Status & Findings

- [x] Does `chcon -t container_file_t` actually relabel a live Unix socket?
      **Yes.** `debug.sh` and `out.txt` show:
      `label: unconfined_u:object_r:user_tmp_t:s0 -> unconfined_u:object_r:container_file_t:s0`
      and `ls -lZ` shows `srwxrwxrwx. ... system_u:object_r:container_file_t:s0 ... agent.sock`.

- [x] Does `container_t` have `connectto` on `container_file_t:unix_stream_socket` once the socket is relabeled?
      **Finding:** In Linux SELinux policy, `connectto` permission on a stream socket is checked against the **peer process / server socket's security context** (`tclass=unix_stream_socket`), NOT the inode/filesystem label (`sock_file`).
      Because `socat` runs in `unconfined_t` on the host, its stream socket (`unix_stream_socket`) has type `unconfined_t`.
      `sesearch` policy query confirms:
      - `container_t` has full access to `container_file_t:sock_file` (filesystem node).
      - `container_t` has `connectto` **only** on `container_t:unix_stream_socket` (and daemon sockets like `sssd_t`, `gssproxy_t`), but **not** `unconfined_t:unix_stream_socket`.
      When `ssh-add` (in `container_t`) attempts to connect, the kernel checks:
      `allow container_t unconfined_t:unix_stream_socket connectto;` -> **DENIED** (as recorded in `denials.txt`).

- [x] Does the `:z` mount option disturb the `chcon`'d socket label?
      **No.** The socket file remains `system_u:object_r:container_file_t:s0`.

- [x] Test Option 2: `runcon -t container_t` for `socat` forwarder.
      **Failed & Ruled Out:**
      When `socat` was executed with `runcon -u system_u -r system_r -t container_t`:
      1. `socat` was denied `write` access to `/run/user/1000/claude-container/` (`user_tmp_t` directory), causing `bind(): Permission denied` (audit denial: `comm="socat" scontext=container_t tcontext=user_tmp_t tclass=dir { write }`).
      2. Even if the directory is relabeled, `socat` running in `container_t` would also be denied `connectto` upstream to GNOME Keyring's socket (`user_tmp_t:unix_stream_socket`).
      Therefore, running `socat` under `container_t` on the host is not viable without extensive host relabeling/privileges.

- [x] Apply Option 1: Load SELinux CIL policy module `container_ssh_forward.cil` on the host.
      - Generated `container_ssh_forward.cil`.
      - Installed on host with: `sudo semodule -i container_ssh_forward.cil`.
      - Verified policy active: `allow container_t unconfined_t:unix_stream_socket connectto;` appears in `sesearch`.
      - Verified inside container with `ssh-add -l`: **Success!** SSH keys are successfully listed with zero AVC denials.

## Resolution Options Summary

1. **Option 1 (SELinux Policy Module) — Implemented & Active:**
   - Policy module: `(allow container_t unconfined_t (unix_stream_socket (connectto)))`
   - Embedded directly into `scripts/run-claude`, which auto-detects and installs it if missing.
   - Verified inside container with `ssh-add -l`.

2. **Option 2 (runcon domain transition) — Infeasible & Ruled Out:**
   - Evaluated running `socat` under `container_t` directly on the host, but blocked by host directory access and upstream keyring connection restrictions. Option 1 was adopted instead.
