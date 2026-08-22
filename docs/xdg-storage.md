# XDG Storage Specification & Directory Layout

Claude Code natively expects all its configuration, session history, auto-memory, authentication tokens, and subagent data to reside in a monolithic directory structure under `~/.claude` and `~/.claude.json`.

`claude-container` decomposes this structure according to the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest). This separates user-authored configuration from transient session caches, state, and secrets.

## 1. Directory Mapping Overview

| Category | Default Host Path | Target Inside Container | Mount Mode | Contents & Purpose |
| --- | --- | --- | --- | --- |
| **State** | `~/.local/state/claude-container/claude.json` | `/root/.claude.json` | `rw,z` | OAuth session credentials, project trust decisions, and user preferences. |
| **State** | `~/.local/state/claude-container/agent-memory` | `/root/.claude/agent-memory` | `rw,z` | Persistent memory written by specialized subagents (`memory: user`). |
| **Cache** | `~/.cache/claude-container/projects` | `/root/.claude/projects` | `rw,z` | Project-specific session logs, topic index files, and auto-memory (`MEMORY.md`). |
| **Config (Files)** | `~/.config/claude-container/{CLAUDE.md,settings.json,...}` | `/root/.claude/{CLAUDE.md,settings.json,...}` | `rw,z` | User instructions, harness settings, local overrides, and keybindings. |
| **Config (Trees)** | `~/.config/claude-container/{rules,themes,output-styles,...}` | `/root/.claude/{rules,themes,output-styles,...}` | `ro,z` | User-defined rules, custom UI themes, output formatters, subagents, workflows, commands. |
| **Config (Skills)** | `~/.config/claude-container/skills` | `/root/.claude/skills` | `rw,z` | User-authored global skills. |
| **Data** | `~/.local/share/claude-container/skills` | `/root/.claude/skills/<skill-name>` | `ro,z` | External and imported skill packages. |
| **Runtime** | `/run/user/$UID/claude-container` | `/root/.ssh/agent.sock` | `z` | Ephemeral `socat` forwarding socket for host SSH authentication (permissions `0700`). |

## 2. Environment Variables & Overrides

Host paths honor standard XDG environment variables. If not defined, fallback defaults are used:

- `XDG_CONFIG_HOME`: Defaults to `$HOME/.config`.
- `XDG_STATE_HOME`: Defaults to `$HOME/.local/state`.
- `XDG_CACHE_HOME`: Defaults to `$HOME/.cache`.
- `XDG_DATA_HOME`: Defaults to `$HOME/.local/share`.
- `XDG_RUNTIME_DIR`: Defaults to `/run/user/$UID`.

The host path variables constructed in `scripts/claude-container` are:

```bash
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-container"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-container"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-container"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-container"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/claude-container"
```

## 3. Directory Breakdown & Semantics

### 3.1 State (`$XDG_STATE_HOME/claude-container`)

State directories store machine-local state that must persist across container restarts, but should not be committed to dotfile repositories.

- **`claude.json` (`/root/.claude.json`):** Holds API session tokens, OAuth refresh credentials, project trust choices, and telemetry IDs. Initialized automatically as `{}` if missing.
- **`agent-memory/` (`/root/.claude/agent-memory/`):** Persistent memory directories written by custom subagents defined with the `memory: user` frontmatter attribute.

### 3.2 Cache (`$XDG_CACHE_HOME/claude-container`)

Contains non-essential, regenerable or history-based runtime artifacts:

- **`projects/` (`/root/.claude/projects/`):** Per-project directory containing session conversation history transcripts, token counter checkpoints, and auto-generated memory files (`MEMORY.md`).

### 3.3 Config (`$XDG_CONFIG_HOME/claude-container`)

Stores user-authored, version-controllable configuration files:

- **`CLAUDE.md` (`/root/.claude/CLAUDE.md`):** Global user instructions.
- **`settings.json` / `settings.local.json` (`/root/.claude/settings.json`):** Harness settings, permission allowlists/denylists, model configuration, and tool hooks. Mounted `rw,z` to allow Claude Code to update settings when directed.
- **`keybindings.json` (`/root/.claude/keybindings.json`):** Custom keybindings.
- **`rules/` (`/root/.claude/rules/`):** Modular Markdown instruction rule files.
- **`themes/` (`/root/.claude/themes/`):** Custom color themes.
- **`output-styles/` (`/root/.claude/output-styles/`):** Custom output formatting templates.
- **`agents/` (`/root/.claude/agents/`):** Custom subagent Markdown declarations.
- **`workflows/` (`/root/.claude/workflows/`):** Custom workflow automation scripts.
- **`commands/` (`/root/.claude/commands/`):** Custom user slash commands.
- **`skills/` (`/root/.claude/skills/`):** Local user skills. Mounted `rw,z`.
- **`skills.conf`:** Configuration file listing external skill directory paths (see [Skills Management](skills.md)).

### 3.4 Data (`$XDG_DATA_HOME/claude-container`)

Stores imported or shared data files:

- **`skills/`:** Repository storage for third-party or externally synced skill bundles.

### 3.5 Runtime (`$XDG_RUNTIME_DIR/claude-container`)

Stores runtime ephemeral IPC resources.

- Created with `chmod 0700`.
- Holds the temporary Unix domain socket `agent.sock` created by `socat`.
- Cleaned up automatically on script termination via Bash `trap cleanup EXIT`.

## 4. Scaffold & Initialization Logic

When `scripts/claude-container` runs, `ensure_locations()` automatically checks and scaffolds the required directory structure:

```bash
ensure_locations() {
    mkdir -p "$CONFIG_DIR"/{rules,skills,themes,output-styles,agents,workflows,commands}
    mkdir -p "$DATA_DIR/skills"
    mkdir -p "$STATE_DIR/agent-memory"
    mkdir -p "$CACHE_DIR/projects"
    mkdir -p "$RUNTIME_DIR"
    chmod 0700 "$RUNTIME_DIR" 2>/dev/null || true

    # Ensure minimal claude.json exists so podman can bind-mount it as a file
    if [[ ! -f "$STATE_DIR/claude.json" ]]; then
        echo "{}" >"$STATE_DIR/claude.json"
    fi
}
```

This guarantees that first-time users can immediately launch `claude-container` without manual setup.
