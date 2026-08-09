# claude-container

A containerized version of claude-code.

## Build

Build and push this with:

```bash
podman login -u hyprhvn docker.io
podman build -f Containerfile -t docker.io/hyprhvn/claude-container:latest
podman push docker.io/hyprhvn/claude-container:latest
```
