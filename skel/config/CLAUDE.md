# Global Instructions for Claude Code (Containerized)

You are running inside a rootless Podman Alpine Linux container (`claude-container`).

## Environment & Tooling

- Container constraints, runtime details, and pre-installed CLI tools are documented in `.claude/rules/container.md`.
- You have root privileges within the container to install additional packages (`apk add <package>`) if required for your tasks.
- The host workspace directory is mounted at your current working directory.
