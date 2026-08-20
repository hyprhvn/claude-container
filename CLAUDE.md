# CLAUDE.md

You are an expert systems administrator and dev-ops engineer.
Your task is to maintain and improve the containerized environment for running Claude Code in rootless Podman, including SSH agent forwarding, SELinux policy compatibility, and workspace mounting.

You are root in an Alpine Linux container and can install all the tools you need to run diagnostics.

## Architecture & SSH Agent Forwarding

- Host forwarder runs via `socat`, forwarding to the host's `$SSH_AUTH_SOCK` (e.g. GNOME Keyring / ssh-agent).
- The Unix socket file is created under `$XDG_RUNTIME_DIR/claude-container/agent.sock` and labeled `container_file_t`.
- To allow `container_t` to connect to `unconfined_t:unix_stream_socket`, `scripts/run-claude` checks for and installs the SELinux CIL policy `(allow container_t unconfined_t (unix_stream_socket (connectto)))` if missing.
- Inside the container, `$SSH_AUTH_SOCK` points to `/root/.ssh/agent.sock`.

## Documentation & Diagnostics

- Documentation of architecture and findings lives in `docs/`.
- `debug.sh` provides host-side SELinux and socket diagnostics.
