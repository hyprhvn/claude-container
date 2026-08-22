# Host Mounts & Git Forwarding

This document explains how host directories, custom bind mounts, and Git identity configurations are securely forwarded into `claude-container`.

## 1. Custom Host Mounts (`-m` / `--mount`)

`claude-container` supports mounting additional host paths using standard Podman syntax: `<from>:<to>[:<options>]`.

### Syntax & Defaults

- **Syntax:** `-m <from>:<to>[:<options>]` or `--mount <from>:<to>[:<options>]`
- **Target (`<to>`):** Must be an absolute path inside the container. If omitted, `<to>` defaults to the resolved host path of `<from>`.
- **Options (`<options>`):** Defaults to `z` (SELinux shared relabeling).
- **Multiple Mounts:** The flag may be specified multiple times.

### Examples

```bash
# 1. Mount a specific directory to a container path
claude-container -m /home/user/extra-data:/opt/data:ro,z

# 2. Mount with default target and options (mounts to /home/user/extra-data with :z)
claude-container -m /home/user/extra-data

# 3. Mount pseudo-filesystems (without relabeling, using bare ro)
claude-container -m /sys/fs/selinux:/sys/fs/selinux:ro
```

### Direct Mount vs Directory Entry Expansion

When handling `-m/--mount`, `collect_mounts()` mounts the specified path directly as a single unit (rather than recursively expanding directory entries). This prevents pseudo-filesystems (like `/sys` or `/proc`) or large hierarchies from turning into hundreds of individual file mounts.

## 2. Git Configuration & Identity Forwarding

To ensure Git commits created by Claude Code inside the container have the correct user name, email, and signing configuration, `collect_git_config()` dynamically mounts the host's Git configuration.

### Read-Only Security Boundary

All Git configuration mounts are strictly mounted `ro,z` (read-only):

```bash
# Global ~/.gitconfig
add_mount "$HOME/.gitconfig" "/root/.gitconfig" "ro,z"

# XDG Git configuration (~/.config/git)
add_dir_mounts "${XDG_CONFIG_HOME:-$HOME/.config}/git" "/root/.config/git" "ro,z"
```

**Security Rationale:** If the container could write to host Git configuration directories, a compromised container process could create symlinks or write hooks that widen container access or execute code on the host during future host Git operations.

### GNU Stow & Symlink Farm Entry Expansion (`add_dir_mounts`)

Many developers manage their `.config/git` using dotfile managers like [GNU Stow](https://www.gnu.org/software/stow/). In a stow setup:

```
~/.config/git/config -> ../../.dotfiles/git/.config/git/config
```

If only the directory `~/.config/git` were mounted into `/root/.config/git`, the relative symlink `config` would dangle inside the container because `../../.dotfiles` is not mounted.

To solve this, `add_dir_mounts()` performs entry-by-entry resolution:

1. Traverses all non-directory entries in `${XDG_CONFIG_HOME:-~/.config}/git`.
2. Resolves each entry to its canonical real host path (`readlink -f`).
3. **Safety Check:** Skips any entry whose real path falls outside both the directory root and `$HOME` to prevent stray symlinks from exposing unintended host files.
4. Mounts each resolved file directly to its relative path in `/root/.config/git/<relative-path>` with `ro,z`.

## 3. SELinux Relabeling (`:z` vs `:Z`) & `$HOME` Boundary

### Why `:z` is Used

Podman provides two volume relabeling flags:

- `:z` (shared): Relabels the host files with `container_file_t` without assigning private category numbers, allowing multiple containers or host processes to access them.
- `:Z` (private): Relabels files with a private category set exclusively for this specific container run.

`claude-container` uses `:z` so that user configuration, caches, and skill files can be safely shared across successive container runs.

### The `$HOME` Boundary Restriction

Running `claude-container` with `$HOME` as the working directory (`DIR`) is prohibited:

```bash
if [[ "$DIR" == "$HOME" ]]; then
    echo -e "Unable to use HOME as DIR\n"
    usage
    exit 4
fi
```

**Reason:** In SELinux-enforcing systems, the user's top-level `$HOME` directory is labeled `user_home_dir_t`. Relabeling `$HOME` itself with `:z` (`container_file_t`) breaks desktop desktop-environment access, SSH daemon authorization, and system security controls. Workspace directories must be subdirectories of `$HOME` (e.g. `~/projects/my-app`), not the root `$HOME` itself.
