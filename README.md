# claude-container

A containerized version of claude-code.

## Build

Build and push the OCI images with:

```bash
# log in to docker hub
podman login -u hyprhvn docker.io
# build the base container
podman build -f Containerfiles/Base -t docker.io/hyprhvn/claude-container:base
podman push docker.io/hyprhvn/claude-container:base
# build the full dev container
podman build -f Containerfiles/Full -t docker.io/hyprhvn/claude-container:full
podman push docker.io/hyprhvn/claude-container:full
```

## Use

The recommended way to run Claude in the container is using the `claude-container` script, which manages SSH agent forwarding, git config propagation, XDG directory structures, and workspace mounting automatically:

```bash
# Run in the current directory:
./scripts/run-claude

# Or run in a specific project directory:
./scripts/run-claude /path/to/project

# Mount additional paths if needed:
./scripts/run-claude -m /host/path:/container/path
```

## Install

Put the `scripts/claude-container` launcher script in a directory on your `$PATH` and run the containerized agent with `run-claude`.
You can display the help messge with `run-claude -h`.

When running without arguments, the working directory is mounted into the container.

> [!important]
>
> This script uses Podman and strict SELinux confinement.
> Because the home directory cannot be relabeled as `container_t`, running the script form there will fail.

Additional directories can be made available via `--mount` flags.

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

## Prerequisites

You need a `~/.claude` directory and a `~/.claude.json` file.
