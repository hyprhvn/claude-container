# claude-container

A containerized version of claude-code.

## Build

Build and push this with:

```bash
podman login -u hyprhvn docker.io
# build the base container
podman build -f Containerfiles/Base -t docker.io/hyprhvn/claude-container:base
podman push docker.io/hyprhvn/claude-container:base
# build the full dev container
podman build -f Containerfiles/Full -t docker.io/hyprhvn/claude-container:full
podman push docker.io/hyprhvn/claude-container:full
```

## Use

The recommended way to run Claude in the container is using the `scripts/run-claude` launcher script, which manages SSH agent forwarding, git config propagation, XDG directory structures, and workspace mounting automatically:

```bash
# Run in the current directory:
./scripts/run-claude

# Or run in a specific project directory:
./scripts/run-claude /path/to/project

# Mount additional paths if needed:
./scripts/run-claude -m /host/path:/container/path
```

You can also copy or symlink `scripts/run-claude` into your `~/.local/bin/` to make `run-claude` available in your `$PATH`.

### Manual Podman Command

Alternatively, run the container directly with `podman`:

```bash
podman run -it --rm \
    -w "$PWD" \
    -v "$PWD:$PWD:z" \
    -v "$HOME/.claude:/root/.claude:z" \
    -v "$HOME/.claude.json:/root/.claude.json:z" \
    -v "$HOME/.ssh/known_hosts:/etc/ssh/ssh_known_hosts:ro,z" \
    -v "$HOME/.config/git:/root/.config/git:ro,z" \
  docker.io/hyprhvn/claude-container:full
```
