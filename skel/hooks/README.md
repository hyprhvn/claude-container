# Hook Scripts

`hooks/` is the host-side home for Claude Code hook scripts. It is mounted
**read-only** at `/root/.claude/hooks` inside the container (part of the
`ro,z` instruction/executable trees, so a container cannot modify its own
hooks between sessions).

Hook *definitions* live in `settings.json` (sibling of this directory). The
`command` paths there must be **container-absolute** paths, e.g.:

```json
{
	"hooks": {
		"SessionStart": [
			{
				"hooks": [
					{
						"type": "command",
						"command": "/root/.claude/hooks/session-start.sh"
					}
				]
			}
		]
	}
}
```

## Rules for hook scripts

- Scripts must be executable (`755`) — Claude Code runs them directly.
- Scripts live on the host at `<CLAUDE_CONTAINER_DIR>/hooks/` (default
  `~/.local/opt/claude-container/hooks/`) and are only mounted, never
  seeded per-file, so `update-skel` treats modified files as user-managed.
- A hook's `stdout` is what Claude Code sees (e.g. `SessionStart` output is
  injected into the session context); exit non-zero and emit `stderr` to
  signal failure.

## Where a stateful hook can write

Everything Claude writes must live on a `rw` mount, or it vanishes on
container exit. Writable locations inside the container:

- the workspace directory (`DIR`)
- `/root/.claude.json`
- `/root/.claude/{skills,agent-memory,projects,plugins}/`
- `/root/.claude/settings.json`, `/root/.claude/settings.local.json`,
  `/root/.claude/keybindings.json`, `/root/.claude/CLAUDE.md`,
  `/root/.claude/statusline.sh`
- anything else under `/root/.claude/` (new state directories included)

Everything else under `/root/.claude/` — in particular `hooks/` itself, and
`rules/`, `agents/`, `themes/`, `output-styles/`, `workflows/`, `commands/`
— is read-only.

## Caveats

- **Stow:** `hooks/` is mounted as one unit; file-level symlinks inside it
  are *not* resolved (unlike the git-config and skills mounts, which
  resolve entry by entry). Put real files in this directory.
- **Fast iteration:** to test a hook without touching the real one, mount
  a scratch directory over it — a later `-v` for the same target wins and
  hides the `ro` hooks tree for that run:

  ```bash
  claude-container -m "$PWD/dev-hooks:/root/.claude/hooks:z"
  ```
