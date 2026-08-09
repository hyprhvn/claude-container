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

Run the container with the project directory mounted to the workspace and set the work dir:

```bash
podman run -it --rm \
    -w "$PWD" \
    -v "$PWD:$PWD:z" \
    -v "$HOME/.claude:$HOME/.claude:z" \
    -v "$HOME/.claude.json:$HOME/.claude.json:z" \
    -e "PATH=/sbin:/bin:$PATH" \
  hyprhvn/claude-container:latest
```

> [!NOTE]
>
> It might be a good idea to also mount other directories:
>
> - `~/.ssh`
> - `~/.config/git`
> 
> Probably best to mount these read-only though.
