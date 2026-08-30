# External Skills Management

Claude Code supports custom capabilities called [skills](https://code.claude.com/docs/en/skills). In `claude-container`, skills can be loaded both from local user storage and from external repositories, private workspaces, or symlinked packages.

## 1. Skill Storage Hierarchy

Skills are loaded into the container at `/root/.claude/skills` from multiple sources:

`$CC_DIR` is the unified claude-container directory
(`${CLAUDE_CONTAINER_DIR:-$HOME/.local/opt/claude-container}`, see
[Unified Storage Layout](storage-layout.md)).

```
+-------------------------------------------------------------------------+
| Host Sources                                                            |
|                                                                         |
| 1. Local User Skills:                                                   |
|    $CC_DIR/skills/                            -> (rw,z, via parent)     |
|                                                                         |
| 2. External Skills Config File:                                         |
|    $CC_DIR/skills.conf                        -> (ro,z per skill)       |
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

## 2. Configuring External Skills

### Method 1: Configuration File (`skills.conf`)

You can define persistent paths to external skill repositories in
`$CC_DIR/skills.conf` (`~/.local/opt/claude-container/skills.conf` by
default).

- One path per line.
- Supports tilde (`~`) expansion to the user's home directory.
- Blank lines and comment lines (starting with `#`) are ignored.

**Example `$CC_DIR/skills.conf` (a `claude-skills` style repository):**

```text
# First-party skills of the repo (multi-skill bundle)
~/Desktop/hyprhvn/claude-skills/skills

# External bundles, one source per line
~/Desktop/hyprhvn/claude-skills/external/anthropic/skills
~/Desktop/hyprhvn/claude-skills/external/mattpocock/skills
~/Desktop/hyprhvn/claude-skills/external/superpowers/skills
~/Desktop/hyprhvn/claude-skills/external/gsd-core/skills

# A repo that is a single skill (SKILL.md at its root)
~/Desktop/hyprhvn/claude-skills/external/gstack
```

Note the last line: a source directory that itself contains a `SKILL.md` is
mounted as one skill under its directory name (see below), so point at the
skill's root rather than at a parent that would only wrap it.

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

## 4. Rules vs. Skills (Ambient Context vs. On-Demand)

Claude Code supports two related but distinct extension mechanisms, and `claude-container` seeds one of them by default:

- **Rules (`~/.claude/rules/`):** Plain Markdown instruction files loaded **ambiently into context on every startup** (unless a `paths:` frontmatter key restricts them to specific files). They are the right place for always-relevant environmental context. The skel seeding (via `scripts/update-skel`, run once during setup) installs a default `rules/container.md` describing the Alpine container environment and the catalog of pre-installed CLI tools, so the agent always knows what it is running in.
- **Skills (`~/.claude/skills/`):** Packaged capabilities (a `SKILL.md` plus optional `references/`, `scripts/`) that are **activated on demand** via tool selection or invocation. They conserve context tokens because their full body is not loaded up front, but they must be explicitly triggered.

Because the container environment and available tooling are relevant to *every* task, they ship as a default **rule** (seeded from `skel/`) rather than a skill. If you prefer the tooling catalog to be opt-in instead, convert `rules/container.md` into a skill under `$CC_DIR/skills/container/SKILL.md` and remove the rule.

## 5. Symlink Resolution & GNU Stow Compatibility

When managing dotfiles or skills via symlink tools (such as [GNU Stow](https://www.gnu.org/software/stow/)), directories often consist of symlinks pointing back to a central `.dotfiles` repository.

`claude-container` uses `resolve_host_path()` (via `readlink -f`) on all skill directories before mounting. This ensures:

- Symlinks are resolved to their true physical path on the host.
- The mount target inside the container retains the semantic skill name.
- Skills never result in dangling symlinks inside the container.
- Skill files are mounted with `ro,z` (read-only with SELinux relabeling), preventing the container from unintentionally mutating external skill repositories.
