# External Skills Management

Claude Code supports custom capabilities called [skills](https://code.claude.com/docs/en/skills). In `claude-container`, skills can be loaded both from local user storage and from external repositories, private workspaces, or symlinked packages.

---

## 1. Skill Storage Hierarchy

Skills are loaded into the container at `/root/.claude/skills` from multiple sources:

```
+-------------------------------------------------------------------------+
| Host Sources                                                            |
|                                                                         |
| 1. Local User Skills:                                                   |
|    ~/.config/claude-container/skills/           -> (rw,z)               |
|                                                                         |
| 2. External Skills Config File:                                         |
|    ~/.config/claude-container/skills.conf       -> (ro,z per skill)     |
|                                                                         |
| 3. Environment Variable:                                                |
|    CLAUDE_SKILLS_DIR=/path/a:/path/b            -> (ro,z per skill)     |
|                                                                         |
| 4. CLI Arguments:                                                       |
|    --skills-dir /path/to/skills                 -> (ro,z per skill)     |
+------------------------------------+------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
| Container: /root/.claude/skills/                                        |
|   ├── skill-one/ (SKILL.md, references/, ...)                           |
|   └── skill-two/ (SKILL.md, scripts/, ...)                              |
+-------------------------------------------------------------------------+
```

---

## 2. Configuring External Skills

### Method 1: Configuration File (`skills.conf`)
You can define persistent paths to external skill repositories in `$CONFIG_DIR/skills.conf` (`~/.config/claude-container/skills.conf`).

- One path per line.
- Supports tilde (`~`) expansion to the user's home directory.
- Blank lines and comment lines (starting with `#`) are ignored.

**Example `~/.config/claude-container/skills.conf`:**
```text
# Custom private skills repository
~/src/private-claude-skills

# Shared team skills
/opt/engineering/claude-skills
```

### Method 2: Environment Variable (`CLAUDE_SKILLS_DIR`)
You can export `CLAUDE_SKILLS_DIR` with a colon-separated (`:`) list of directories:

```bash
export CLAUDE_SKILLS_DIR="$HOME/src/claude-skills:$HOME/projects/custom-tools"
claude-container
```

### Method 3: Command-Line Flag (`--skills-dir`)
Pass one or more `--skills-dir` options when launching `claude-container`:

```bash
claude-container --skills-dir /path/to/my-skills --skills-dir /path/to/other-skill
```

---

## 3. Directory Layouts: Single-Skill vs Multi-Skill Bundle

`collect_skills_mounts()` intelligently inspects each target directory to support both single-skill repositories and multi-skill bundle folders:

### Single-Skill Repository
If the specified directory contains a `SKILL.md` directly at its root:
```
my-custom-skill/
├── SKILL.md
├── scripts/
└── references/
```
It is mounted directly to `/root/.claude/skills/<directory-name>` (e.g. `/root/.claude/skills/my-custom-skill`).

### Multi-Skill Bundle
If the specified directory does not have a top-level `SKILL.md`, `claude-container` iterates through each immediate subdirectory:
```
all-skills-bundle/
├── docker-tools/
│   └── SKILL.md
├── k8s-helper/
│   └── SKILL.md
└── code-review/
    └── SKILL.md
```
Each subdirectory is individually mounted as `/root/.claude/skills/<subdir-name>` (`/root/.claude/skills/docker-tools`, `/root/.claude/skills/k8s-helper`, etc.).

---

## 4. Symlink Resolution & GNU Stow Compatibility

When managing dotfiles or skills via symlink tools (such as [GNU Stow](https://www.gnu.org/software/stow/)), directories often consist of symlinks pointing back to a central `.dotfiles` repository.

`claude-container` uses `resolve_host_path()` (via `readlink -f`) on all skill directories before mounting. This ensures:
- Symlinks are resolved to their true physical path on the host.
- The mount target inside the container retains the semantic skill name.
- Skills never result in dangling symlinks inside the container.
- Skill files are mounted with `ro,z` (read-only with SELinux relabeling), preventing the container from unintentionally mutating external skill repositories.
