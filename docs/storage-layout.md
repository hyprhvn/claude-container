# Unified Storage Layout

All of Claude Code's configuration, state, session history, auto-memory, plugins, and caches live in **one unified directory** on the host:

```text
$CC_DIR = ${CLAUDE_CONTAINER_DIR:-$HOME/.local/opt/claude-container}
```

The launcher bind-mounts that directory read-write as the container's
`/root/.claude`, plus `claude.json` as a file and the instruction/executable
trees as read-only submounts (see below). Everything Claude writes under
`/root/.claude` or `/root/.claude.json` therefore persists — including state
directories Claude grows on its own (`sessions/`, `tasks/`,
`shell-snapshots/`, …), which need **zero new mount code**.

## 1. Why One Directory Instead of XDG

Claude Code natively expects a single monolithic tree under `~/.claude` and
one `~/.claude.json` file. The previous XDG-based split decomposed that tree
into five host directories (`~/.config`, `~/.local/state`, `~/.cache`,
`~/.local/share`, `/run/user`), which turned out to be overly complicated:

- Anything Claude wrote outside the explicit mount list (`plugins/`,
  `sessions/`, `history.jsonl`, `tasks/`, `shell-snapshots/`, `backups/`, …)
  was ephemeral and vanished on every container run.
- Plugins, which have their own data directories, had no home at all.
- The split made skel seeding, synchronization, plugin imports, and skill
  handling needlessly complicated.

One directory per application is what the XDG spec itself recommends for
this case, and it is plugin-friendly: the whole tree persists as-is, and any
future state directory is covered by the parent mount automatically.

## 2. Mount Mapping Overview

| Host (`$CC_DIR/…`) | Target Inside Container | Mount Mode |
| --- | --- | --- |
| (whole directory) | `/root/.claude` | `rw,z` (parent) |
| `claude.json` | `/root/.claude.json` | `rw,z` |
| `rules/` `agents/` `hooks/` `themes/` `output-styles/` `workflows/` `commands/` | `/root/.claude/<same>` | `ro,z` (submounts) |
| `CLAUDE.md`, `settings.json`, `settings.local.json`, `keybindings.json`, `statusline.sh`, `skills/`, `agent-memory/`, `projects/`, `plugins/`, and any future state | same paths | `rw,z` (via parent) |
| `skills.conf` | — (host-read only) | — |
| `.skel-manifest.tsv` | — (host-read only) | — |
| `runtime/agent.sock` | `/root/.ssh/agent.sock` | `z` (dir mode `0700`, removed on exit) |

The `ro,z` submounts over the `rw` parent are deliberate: `rules/`, `agents/`,
`hooks/`, `themes/`, `output-styles/`, `workflows/`, and `commands/` hold
instructions and executables that sessions **load**. A container able to write
there could plant a rule, agent, or hook that the next session executes — the
nested mounts hide the write access, the more specific mount wins.

## 3. Directory Breakdown & Semantics

- **`claude.json` (`/root/.claude.json`):** API session tokens, OAuth
  credentials, project trust choices, and preferences. Initialized as `{}`
  if missing (it must exist as a file for the bind mount).
- **`CLAUDE.md` (`/root/.claude/CLAUDE.md`):** Global user instructions.
- **`settings.json` / `settings.local.json` (`/root/.claude/settings.json`):**
  Harness settings, permission allow/deny lists, model configuration, the
  statusline, and hook definitions.
- **`keybindings.json` (`/root/.claude/keybindings.json`):** Custom keybindings.
- **`statusline.sh` (`/root/.claude/statusline.sh`):** The statusline script
  (wired up by `settings.json`). Its OpenRouter pricing cache lives in
  `$HOME/.cache/claude-statusline` *inside the container* and is intentionally
  ephemeral (regenerable cache data).
- **`rules/` (`/root/.claude/rules/`):** Modular Markdown instruction rules,
  loaded ambiently.
- **`agents/` (`/root/.claude/agents/`):** Custom subagent declarations.
- **`hooks/` (`/root/.claude/hooks/`):** Hook scripts (see `hooks/README.md`
  in the seeded tree).
- **`themes/`, `output-styles/`, `workflows/`, `commands/`:** Custom themes,
  output formatters, workflow scripts, and slash commands.
- **`skills/` (`/root/.claude/skills/`):** User-authored global skills
  (`rw,z`); external skills are mounted on top of it `ro,z` per skill (see
  [Skills Management](skills.md)).
- **`skills.conf`:** Host-side list of external skill directories.
- **`agent-memory/` (`/root/.claude/agent-memory/`):** Persistent memory
  written by subagents with the `memory: user` frontmatter.
- **`projects/` (`/root/.claude/projects/`):** Per-project session
  transcripts, token checkpoints, and auto-memory (`MEMORY.md`).
- **`plugins/` (`/root/.claude/plugins/`):** Plugin data and marketplace
  state. Pre-created by the launcher; now persists like everything else.
- **`runtime/`:** Ephemeral, created `0700`, holds the `socat` SSH-agent
  forwarding socket (`agent.sock`), and is `rm -rf`'d by the launcher on
  exit.

## 4. Environment Variables

- `CLAUDE_CONTAINER_DIR` — override the unified directory (default
  `$HOME/.local/opt/claude-container`). All three scripts honor it.
- `CLAUDE_CONTAINER_SKEL` — override the skel template directory used by
  `update-skel` (default: the repository's `skel/`, resolved relative to the
  script location).
- `CLAUDE_SKILLS_DIR` — colon-separated external skill directories (see
  [Skills Management](skills.md)).

The host's git configuration is still read from the standard XDG locations
(`~/.gitconfig`, `${XDG_CONFIG_HOME:-~/.config}/git`) — that is the *host's*
git, not claude-container's storage.

## 5. Template Skeleton (`skel/`) & Seeding

The repository ships starter files under `skel/`, mirroring `$CC_DIR`
directly:

```text
skel/
├── CLAUDE.md                # Starter global instructions referencing rules/container.md
├── claude.json              # Baseline config state "{}"
├── settings.json            # statusline + SessionStart hook wiring (no credentials)
├── statusline.sh            # user@host, dir(git-branch), model, ctx %, tokens, est. cost
├── rules/
│   └── container.md         # Ambiently loaded container environment & available tools
├── hooks/
│   ├── README.md            # Hook authoring guide (paths, wiring, writable locations)
│   └── session-start.sh     # Trivial SessionStart starter hook
└── test/                    # Test-image-only assets (never seeded)
```

### 5.1 Installation (one-time)

Run `scripts/update-skel --seed` from a repository checkout once during
setup. It creates `$CC_DIR` if needed, copies the missing templates, and
writes the provenance manifest. It is idempotent and never overwrites
existing files. The launcher does **not** seed — it is installed by copying
a single self-contained script into a `$PATH` directory, where no `skel/` is
available, and only scaffolds the directory structure (see §6).

When the repository's `skel/` changes later, re-run
`update-skel --update` to refresh the templates, or `--force [PATH]` to
re-baseline deliberately.

### 5.2 `scripts/update-skel` reference

```text
update-skel [-h | --help] [-n | --dry-run] [--seed | --update]
            [--force [SKEL_REL_PATH]]...
```

- **`--seed` (default):** copy files that do not exist yet. Prints only
  actions taken — **silent in steady state**, so it is idempotent and safe
  to run any number of times.
- **`--update`:** as `--seed`, plus refresh tracked files whose skel template
  changed (the recorded hash no longer matches the current skel). Reports
  skips, conflicts, and a summary.
- **`--force [PATH]`:** repeatable. `PATH` is a skel-relative path (e.g.
  `settings.json`); a bare `--force` forces all tracked files. Existing
  destinations are backed up to `<dest>.bak.<YYYYMMDD_HHMMSS>` first.
  Destructive by design.
- **`-n / --dry-run`:** report the actions without changing anything.

**Provenance model.** Every seeded/updated file is recorded in
`$CC_DIR/.skel-manifest.tsv` (`rel<TAB>sha256`, sorted, written atomically
only when changed). A file is template-managed **only** while it is in the
manifest and unmodified — there is deliberately no "adopt if the hash
matches" heuristic. User-modified, untracked, and stow-style symlinked
files are never touched; symlinked destinations lose their manifest entry.
Installed files are **never deleted**, even when the skel stops providing
them (`--update` reports "No longer in skel, left in place").

**Per-file semantics.**

1. forced → back up the existing destination, copy, re-baseline the hash
   (symlink destinations are never replaced — reported instead).
2. destination is a symlink (stow) → skip, drop the manifest entry.
3. destination missing → copy, record the hash ("seeded").
4. destination exists, hash matches the manifest (untouched):
   - skel unchanged → no-op (steady state, silent);
   - skel changed → `--update` copies and re-baselines ("updated"),
     `--seed` reports "Skel changed, run --update".
5. destination modified or untracked → user-managed: skip and report.

**Recovery.** A lost manifest makes every file untracked → `--seed`/
`--update` skip everything (safe: nothing is clobbered). Recover by
re-baselining the files you know are templates with `--force` (`.bak`
sidecars are created), or by deleting the tree and re-seeding. There is no
`flock` (dependency constraint); the atomic manifest `mv` plus idempotent
copies mean the worst case under concurrent runs is a lost manifest entry —
the file is then misclassified as user-managed and skipped, never
clobbered.

## 6. Scaffold Logic

When `scripts/claude-container` runs, `ensure_locations()` scaffolds the
structure if missing:

```bash
ensure_locations() {
    mkdir -p "$CC_DIR"
    mkdir -p "$CC_DIR"/{skills,plugins,rules,agents,hooks,themes,output-styles,workflows,commands}

    mkdir -p "$RUNTIME_DIR"
    chmod 0700 "$RUNTIME_DIR" 2>/dev/null || true

    # Ensure minimal claude.json exists so podman can bind-mount it as a file
    if [[ ! -f "$CC_DIR/claude.json" ]]; then
        echo "{}" >"$CC_DIR/claude.json"
    fi
}
```

That is the launcher's entire initialization: no seeding, no legacy-layout
detection. A container started before the one-time `update-skel --seed`
still works — it simply lacks the starter templates until then.
