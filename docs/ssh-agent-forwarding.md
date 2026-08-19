# SSH agent forwarding into the container does not work

## Symptom

Inside the container, git auth over SSH fails even though the host agent is
healthy:

```console
$ ssh-add -l
Error connecting to agent: Permission denied

$ ssh -T git@github.com
git@github.com: Permission denied (publickey)
```

On the host, the same agent lists keys normally:

```console
$ echo "$SSH_AUTH_SOCK"
/run/user/1000/gcr/ssh
$ ssh-add -l
256 SHA256:... fynn@laptop (ED25519)
...
```

## Root cause

A Unix domain socket is resolved by `connect()` inside the **local network
namespace**. A socket created in one network namespace cannot be reached from
another, even if the socket's filesystem entry is visible there.

`scripts/run-claude` forwards the agent with this pattern:

1. `create_ssh_sock()` runs `socat` **on the host**, listening on
   `$RUNTIME_DIR/agent.sock` (the host's `/run/user/1000/claude-container/agent.sock`).
2. That socket file is bind-mounted into the container at `/root/.ssh/agent.sock`.
3. The container runs with `NetworkMode: pasta`, i.e. its **own** network
   namespace.

The bind-mount only gives the container the filesystem entry. The socket itself
still lives in the host's network namespace, so the container process can never
connect to it. The `socat` listener is unreachable from inside the container.

## Evidence

`podman inspect` shows the mount and the isolated network mode:

```
NetworkMode: 'pasta'
Mount: /run/user/1000/claude-container/agent.sock -> /root/.ssh/agent.sock
```

Inside the container there is no listening socket, confirming the listener is
in a different namespace:

```console
$ ss -xl
Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port
(empty)

$ grep agent.sock /proc/net/unix
(no match)
```

## Fix

Run the container with `--net=host` so it shares the host network namespace and
can reach host-side sockets:

```bash
podman run -it --rm --net=host \
    ...
```

Once the network namespace is shared, the `socat` forwarding layer becomes
unnecessary — the agent socket can be mounted straight to where `SSH_AUTH_SOCK`
points:

```bash
-v "$SSH_AUTH_SOCK:/root/.ssh/agent.sock:z" \
-e "SSH_AUTH_SOCK=/root/.ssh/agent.sock"
```

## Caveats

- `--net=host` disallows `-p` port publishing in podman. Fine for a CLI agent
  such as claude-code, but anything needing to publish a port must instead use
  a TCP forward rather than a Unix socket.
- The peer-credential check is a non-issue here: the container's root maps to
  the host user (`uid_map` `0 -> 1000`), matching the agent's uid, so the agent
  accepts the connection once the namespace barrier is removed.

## Related

- GNOME Keyring owns `SSH_AUTH_SOCK` (`/run/user/1000/gcr/ssh`) in the desktop
  session, overriding a user `ssh-agent` started in `.bash_profile`. That is a
  separate concern from the namespace barrier documented here.