# Architectural Plan: Modular XDG-Compliant Storage & Skill Management for Containerized Claude Code

## Context
Currently, `scripts/claude-container` mounts the monolithic `$HOME/.claude` and `$HOME/.claude.json` directly into `/root/.claude` and `/root/.claude.json`. This causes user-authored configuration, session logs, auto-memory caches, subagent state, and credentials to mingle inside a single non-standard directory in `$HOME`.

This plan transitions `claude-container` to adhere to the **[XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest)** and the **[Claude Directory Specification](https://code.claude.com/docs/en/claude-directory.md)** by:
1. Deconstructing `$HOME/.claude` and `$HOME/.claude.json` into semantic XDG categories (`$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, `$XDG_STATE_HOME`, `$XDG_CACHE_HOME`).
2. Directly mounting these modular directories to the `/root/.claude/...` target paths expected by Claude inside the container.
3. Supporting external private/custom skill repositories without hardcoded submodules.
4. Providing a standalone one-time migration and initialization script (`scripts/migrate-from-home` / `scripts/init-claude`) to scaffold minimal required directories/files and migrate existing data.

---

## 1. File Classification & XDG Base Directory Mapping

Based on the XDG specification semantics and Claude Code's directory design:

| Path / File | Type & Semantics | Target XDG Base Directory | Host Location (`$XDG_.../claude-container`) | Container Target | Mount Mode |
|---|---|---|---|---|---|
| `CLAUDE.md` | User-authored global prompt instructions | `$XDG_CONFIG_HOME` (`~/.config`) | `$CONFIG_DIR/CLAUDE.md` | `/root/.claude/CLAUDE.md` | `ro,z` (or `rw,z`) |
| `settings.json` | User configuration (permissions, hooks, model) | `$XDG_CONFIG_HOME` (`~/.config`) | `$CONFIG_DIR/settings.json` | `/root/.claude/settings.json` | `rw,z` |
| `keybindings.json` | User keybinding definitions | `$XDG_CONFIG_HOME` (`~/.config`) | `$CONFIG_DIR/keybindings.json` | `/root/.claude/keybindings.json` | `ro,z` |
| `themes/` | User custom UI theme definitions | `$XDG_CONFIG_HOME` (`~/.config`) | `$CONFIG_DIR/themes` | `/root/.claude/themes` | `ro,z` |
| `rules/` | User global topic rules (`.md`) | `$XDG_CONFIG_HOME` (`~/.config`) | `$CONFIG_DIR/rules` | `/root/.claude/rules` | `ro,z` |
| `output-styles/` | Custom prompt output styles | `$XDG_CONFIG_HOME` (`~/.config`) | `$CONFIG_DIR/output-styles` | `/root/.claude/output-styles` | `ro,z` |
| `commands/` | Legacy user single-file commands | `$XDG_CONFIG_HOME` (`~/.config`) | `$CONFIG_DIR/commands` | `/root/.claude/commands` | `ro,z` |
| `agents/` | User subagent definitions (`.md`) | `$XDG_CONFIG_HOME` (`~/.config`) | `$CONFIG_DIR/agents` | `/root/.claude/agents` | `ro,z` |
| `workflows/` | User workflow scripts (`.js`) | `$XDG_CONFIG_HOME` (`~/.config`) | `$CONFIG_DIR/workflows` | `/root/.claude/workflows` | `ro,z` |
| `skills/` (Builtin/Local) | User-authored skills | `$XDG_CONFIG_HOME` (`~/.config`) | `$CONFIG_DIR/skills` | `/root/.claude/skills` | `rw,z` |
| **External Skills** | Imported / external skills repos/dirs | `$XDG_DATA_HOME` (`~/.local/share`) | `$DATA_DIR/skills` or configured path | `/root/.claude/skills/<name>` | `ro,z` |
| `.claude.json` | State: OAuth tokens, trust decisions, preferences | `$XDG_STATE_HOME` (`~/.local/state`) | `$STATE_DIR/claude.json` | `/root/.claude.json` | `rw,z` |
| `agent-memory/` | Subagent persistent memory (`memory: user`) | `$XDG_STATE_HOME` (`~/.local/state`) | `$STATE_DIR/agent-memory` | `/root/.claude/agent-memory` | `rw,z` |
| `projects/` | Main auto memory (`MEMORY.md`, topic files) & session history | `$XDG_CACHE_HOME` (`~/.cache`) | `$CACHE_DIR/projects` | `/root/.claude/projects` | `rw,z` |
| Temporary runtime sockets | Live IPC / SSH sockets | `$XDG_RUNTIME_DIR` (`/run/user/$UID`) | `$RUNTIME_DIR/agent.sock` | `/root/.ssh/agent.sock` | `z` |

---

## 2. External Skills Management Strategy

### Problem
The user has a private repository of custom skills that should not be a hardcoded submodule in this repository, but must be easily consumable and mountable across machines.

### Implementation
1. **Configurable Skill Sources via `$CONFIG_DIR/skills.conf`:**
   - Allows users to list local directories, environment variables, or optional external repo paths:
     ```bash
     # Example $CONFIG_DIR/skills.conf
     /home/fynn/Desktop/my-private-skills
     ```
   - Also supports an environment variable `CLAUDE_SKILLS_DIR` and CLI argument `--skills-dir <path>`.
2. **Mount Assembly in `claude-container`:**
   - The launcher reads `$CONFIG_DIR/skills.conf` and any extra CLI/env skill directories.
   - For each configured path (or each skill subfolder within it), `add_mount` mounts it under `/root/.claude/skills/<skill-name>`.
   - Symlink resolution (`resolve_host_path`) is applied so GNU Stow or symlinked repositories work cleanly.

---

## 3. Initialization & Minimal Required Scaffold

### Minimal Requirements
To allow Claude Code in the container to run without errors on a clean machine:
- Ensure `$STATE_DIR/claude.json` exists as `{}` if not present.
- Create directory structure:
  - `$CONFIG_DIR` (`skills/`, `rules/`, `themes/`, `agents/`, `workflows/`, `output-styles/`)
  - `$DATA_DIR` (`skills/`)
  - `$STATE_DIR` (`agent-memory/`)
  - `$CACHE_DIR` (`projects/`)
  - `$RUNTIME_DIR` (mode `0700`)

---

## 4. Standalone Migration Script (`scripts/migrate-from-home`)

A dedicated one-time setup/migration script:
1. Detects legacy `$HOME/.claude` and `$HOME/.claude.json`.
2. Creates the target XDG directories.
3. Safely moves / copies existing contents:
   - `$HOME/.claude.json` -> `$STATE_DIR/claude.json`
   - `$HOME/.claude/projects` -> `$CACHE_DIR/projects`
   - `$HOME/.claude/agent-memory` -> `$STATE_DIR/agent-memory`
   - `$HOME/.claude/{settings.json,CLAUDE.md,keybindings.json,rules,skills,themes,output-styles,agents,workflows,commands}` -> `$CONFIG_DIR/`
4. Creates a timestamped backup before moving, or supports non-destructive copy mode.

---

## 5. Modifications to `scripts/claude-container`

1. Update directory variable definitions and ensure permissions.
2. Replace monolithic mounts (`-v "$HOME/.claude:/root/.claude:z" -v "$HOME/.claude.json:/root/.claude.json:z"`) with modular mounts:
   - Mount `$STATE_DIR/claude.json` to `/root/.claude.json:rw,z`.
   - Mount `$CACHE_DIR/projects` to `/root/.claude/projects:rw,z`.
   - Mount `$STATE_DIR/agent-memory` to `/root/.claude/agent-memory:rw,z`.
   - Mount `$CONFIG_DIR` subtrees (`CLAUDE.md`, `settings.json`, `rules`, `skills`, `themes`, etc.) to `/root/.claude/...`.
   - Mount external skills from `$CONFIG_DIR/skills.conf` / `$DATA_DIR/skills`.
3. Retain working directory `$DIR` and SSH forwarding socket mounts.

---

## 6. Verification & Testing Steps
1. Run initialization/migration on clean and existing setups.
2. Run `scripts/claude-container` and verify container mounts via Podman inspection / inside container shell.
3. Test session creation and auto-memory saving to verify `$CACHE_DIR/projects` updates.
4. Test external skill availability via `/skill-name` inside Claude.
5. Verify SELinux labeling (`:z`) functions correctly across all modular bind mounts.
