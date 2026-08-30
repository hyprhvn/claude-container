# CLAUDE.md

Your task is to maintain and improve the containerized environment for running Claude Code in rootless Podman, including SSH agent forwarding, SELinux policy compatibility, the unified storage directory, external skills management, and container testing.

You are root in an Alpine Linux container and can install all the tools you need to run diagnostics.

## Architecture, Storage & Directory Layout

All Claude Code storage lives in one unified directory on the host:

- **Unified dir** (`$CC_DIR = ${CLAUDE_CONTAINER_DIR:-$HOME/.local/opt/claude-container}`): everything — `CLAUDE.md`, `settings.json`, `rules/`, `hooks/`, `themes/`, `output-styles/`, `agents/`, `workflows/`, `commands/`, `skills/`, `agent-memory/`, `projects/`, `plugins/`, `claude.json`, and any future state — mounted `rw,z` at `/root/.claude` (plus `claude.json` at `/root/.claude.json`). Nothing Claude writes is ephemeral.
- **Read-only trees**: `rules/`, `agents/`, `hooks/`, `themes/`, `output-styles/`, `workflows/`, `commands/` are re-mounted `ro,z` on top, so a container cannot plant instructions or executables for the next session.
- **Runtime** (`$CC_DIR/runtime`): live sockets and temporary files, mode `0700`, removed on exit.

External skills are discoverable and mounted from:

1. `$CC_DIR/skills.conf`
2. `CLAUDE_SKILLS_DIR` environment variable
3. `--skills-dir <DIR>` CLI flag

## CLI Argument Forwarding

- Container arguments are passed via `-C` / `--container-arg <ARG>` (e.g. `--privileged`).
- Claude arguments are passed following the workspace directory `[DIR] [CLAUDE_ARGS...]` or after `--`.

## Initialization & Skel Templates

- `scripts/claude-container` is self-contained (installed by copying it into `$PATH`): it scaffolds the unified directory and an initial `{}` `claude.json` if run on a clean environment. It does not seed templates and has no legacy-layout logic.
- `scripts/update-skel` seeds/refreshes the starter files from `skel/` with provenance tracking (`$CC_DIR/.skel-manifest.tsv`): `--seed` (copy-missing-only, the default — run once at install time), `--update` (refresh when the skel changed), `--force [PATH]` (re-baseline, with `.bak` sidecars). User-modified files are never touched; installed files are never deleted.

## SSH Agent Forwarding & SELinux

- Host forwarder runs via `socat`, forwarding to the host's `$SSH_AUTH_SOCK` (e.g. GNOME Keyring / ssh-agent).
- The Unix socket file is created under `$CC_DIR/runtime/agent.sock` and labeled `container_file_t`.
- To allow `container_t` to connect to `unconfined_t:unix_stream_socket`, `scripts/claude-container` checks for and installs the SELinux CIL policy `(allow container_t unconfined_t (unix_stream_socket (connectto)))` if missing.
- Inside the container, `$SSH_AUTH_SOCK` points to `/root/.ssh/agent.sock`.

## Testing & Diagnostics

- Detailed technical documentation is located in `docs/`:
  - `docs/architecture.md`: Overall containerization architecture and security model.
  - `docs/storage-layout.md`: Unified storage layout, mount mappings, and `update-skel` template management.
  - `docs/ssh-agent-forwarding.md`: SSH socket proxying and SELinux CIL policy.
  - `docs/skills.md`: External skills management and loading logic.
  - `docs/mounting.md`: Host mounts, custom `-m` mounts, and Git forwarding.
  - `docs/testing.md`: Testing with Podman-in-Podman (PinP) and argument passthrough.
- `tests/test-pinp.sh` runs automated test suites for one-time seeding, `update-skel` semantics, unified mounts, argument collection, and PinP readiness.
- `Containerfiles/Test` (image `:test`) bundles PinP + SELinux tooling and the `container-debug` skill; `scripts/test-env` (SELinux + a selinuxfs bind mount required — the `spc_t` domain cannot mount selinuxfs itself) sets up the nested fixture (ssh-agent + socat forwarder + policy checks) so the agent can debug the setup itself.
