# Migration & Initialization Guide

This document describes how to migrate an existing monolithic Claude Code configuration (`~/.claude` and `~/.claude.json`) to the modular XDG layout used by `claude-container`, as well as how clean initialization works.

## 1. Migration Overview

Standard Claude Code installations store everything in `$HOME/.claude` and `$HOME/.claude.json`. `claude-container` provides a dedicated standalone utility, `scripts/migrate-from-home`, to relocate files into their corresponding XDG categories:

```
Legacy Layout                               XDG Target Layout
──────────────────────────────────────      ────────────────────────────────────────────────────
~/.claude.json                       ───►   ~/.local/state/claude-container/claude.json
~/.claude/agent-memory/              ───►   ~/.local/state/claude-container/agent-memory/
~/.claude/projects/                  ───►   ~/.cache/claude-container/projects/
~/.claude/CLAUDE.md                  ───►   ~/.config/claude-container/CLAUDE.md
~/.claude/settings.json              ───►   ~/.config/claude-container/settings.json
~/.claude/settings.local.json        ───►   ~/.config/claude-container/settings.local.json
~/.claude/keybindings.json           ───►   ~/.config/claude-container/keybindings.json
~/.claude/rules/                     ───►   ~/.config/claude-container/rules/
~/.claude/skills/                    ───►   ~/.config/claude-container/skills/
~/.claude/themes/                    ───►   ~/.config/claude-container/themes/
~/.claude/output-styles/             ───►   ~/.config/claude-container/output-styles/
~/.claude/agents/                    ───►   ~/.config/claude-container/agents/
~/.claude/workflows/                 ───►   ~/.config/claude-container/workflows/
~/.claude/commands/                  ───►   ~/.config/claude-container/commands/
```

## 2. Running `migrate-from-home`

### 2.1 Dry Run (Preview Changes)

To inspect the actions and target paths without modifying any files on disk, use `-n` or `--dry-run`:

```bash
./scripts/migrate-from-home --dry-run
```

### 2.2 Default Migration (Move with Automatic Backup)

Running without flags performs the migration:

1. Creates the complete XDG directory skeleton under `~/.config`, `~/.local/state`, `~/.cache`, and `~/.local/share`.
2. Creates an automatic timestamped backup at `~/.claude.backup.<YYYYMMDD_HHMMSS>/`.
3. Moves files and directories to their XDG targets.
4. Cleans up the empty legacy `~/.claude` directory if no unhandled files remain.

```bash
./scripts/migrate-from-home
```

### 2.3 Non-Destructive Copy Mode

If you prefer to retain the legacy files in place (for instance, to continue using non-containerized Claude Code concurrently), use `-c` or `--copy`:

```bash
./scripts/migrate-from-home --copy
```

### 2.4 Skipping Backups

To disable creating the backup directory before moving (useful in automated CI or test scripts):

```bash
./scripts/migrate-from-home --no-backup
```

## 3. Command-Line Reference

```
NAME
    migrate-from-home - Migrate legacy ~/.claude configuration to XDG Base Directories

SYNOPSIS
    migrate-from-home [-h | --help] [-n | --dry-run] [-c | --copy] [--no-backup]

OPTIONS
    -h, --help       Display help message and exit
    -n, --dry-run    Show what would be migrated without making changes
    -c, --copy       Copy files instead of moving them
    --no-backup      Do not create a timestamped backup before moving
```

## 4. Fresh Installation & Clean Initialization

If you have no legacy `~/.claude` or `~/.claude.json` on the system:

1. Running `./scripts/migrate-from-home` will detect that no legacy directory exists and initialize the fresh XDG skeleton with an initial `{}` state in `$STATE_DIR/claude.json`.
2. Alternatively, running `./scripts/claude-container` directly will automatically scaffold the directories and minimal files on its very first launch via `ensure_locations()`.
