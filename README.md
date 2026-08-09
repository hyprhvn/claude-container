# claude-container

A containerized version of claude-code.

## Build

Build and push this with:

```bash
podman login -u hyprhvn docker.io
podman build -f Containerfile -t docker.io/hyprhvn/claude-container:latest
podman push docker.io/hyprhvn/claude-container:latest
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
