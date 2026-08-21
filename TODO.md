# TODO — Modular XDG Mounting & Skills Management

This document tracks work packages and status for splitting Claude Code container data into XDG Base Directories and enabling external skills support.

---

## Work Packages

### 1. Planning & Architecture
- [x] Analyze Claude directory layout (`code.claude.com/docs/en/claude-directory.md`) and XDG Base Directory specification.
- [x] Map files to `$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, `$XDG_STATE_HOME`, and `$XDG_CACHE_HOME`.
- [x] Design external skills mounting approach via `$CONFIG_DIR/skills.conf`, env var, and CLI arguments.
- [x] Write comprehensive architectural plan to `PLANNING.md`.

### 2. Standalone Migration Script (`scripts/migrate-from-home`)
- [x] Implement detection of legacy `$HOME/.claude` and `$HOME/.claude.json`.
- [x] Create timestamped backup of legacy files before moving/copying.
- [x] Create target XDG directory skeleton with minimal scaffolding.
- [x] Migrate files to respective XDG target directories:
  - `$HOME/.claude.json` -> `$STATE_DIR/claude.json`
  - `$HOME/.claude/agent-memory` -> `$STATE_DIR/agent-memory`
  - `$HOME/.claude/projects` -> `$CACHE_DIR/projects`
  - `$HOME/.claude/{CLAUDE.md,settings.json,keybindings.json,rules,skills,themes,output-styles,agents,workflows,commands}` -> `$CONFIG_DIR/`
- [x] Add flags for `--dry-run`, `--copy` (non-destructive), and `--no-backup`.

### 3. Modular Mounts & External Skills in Launcher Script (`scripts/claude-container`)
- [x] Ensure minimal directory scaffolding and `$STATE_DIR/claude.json` `{}` creation on startup.
- [x] Add support for `--skills-dir <path>` CLI option and `CLAUDE_SKILLS_DIR` env var.
- [x] Support `$CONFIG_DIR/skills.conf` for external skill directories/repositories.
- [x] Refactor `run_claude` / mount collection to directly mount modular paths:
  - `$STATE_DIR/claude.json` -> `/root/.claude.json:rw,z`
  - `$CACHE_DIR/projects` -> `/root/.claude/projects:rw,z`
  - `$STATE_DIR/agent-memory` -> `/root/.claude/agent-memory:rw,z`
  - `$CONFIG_DIR` components (`CLAUDE.md`, `settings.json`, `rules`, `skills`, `themes`, `output-styles`, `agents`, `workflows`, `commands`, `keybindings.json`) -> `/root/.claude/...`
  - External skills -> `/root/.claude/skills/<skill-name>`
- [x] Preserve existing custom mounts (`-m`) and SSH socket forwarding logic.

### 4. Verification & Testing
- [x] Test migration script in dry-run, copy, and move modes.
- [x] Test first-run initialization with clean environment variables.
- [x] Validate container startup and container mount generation across XDG locations.
- [x] Test external skill availability and symlink resolution.
- [x] Verify ShellCheck and static analysis on all shell scripts.

### 5. Documentation
- [x] Update `README.md` with XDG directory structure, migration guide, and external skills instructions.
- [x] Update `CLAUDE.md` to document the new architecture.
