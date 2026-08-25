#!/usr/bin/env bash
#
# test-pinp.sh - Automated Podman-in-Podman (PinP) & Argument Passthrough Test
#
# This script is designed to run either:
# 1. Directly on a system with Podman installed.
# 2. Inside a privileged outer container (e.g. alpine:3.20 or quay.io/podman/stable).
#

set -eEuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d "/tmp/claude-container-test.XXXXXX")"

cleanup() {
	rm -rf "$TEST_TMP"
}
trap cleanup EXIT

echo "==> Running PinP and CLI Argument Tests in: $TEST_TMP"

# 1. Test CLI Help
echo "--> Testing --help option..."
"$REPO_ROOT/scripts/claude-container" --help >/dev/null

# 2. Test skeleton seeding via migrate-from-home on fresh setup
echo "--> Testing skeleton seeding via migrate-from-home..."
export XDG_CONFIG_HOME="$TEST_TMP/config"
export XDG_DATA_HOME="$TEST_TMP/data"
export XDG_STATE_HOME="$TEST_TMP/state"
export XDG_CACHE_HOME="$TEST_TMP/cache"
export XDG_RUNTIME_DIR="$TEST_TMP/run"
export CLAUDE_LEGACY_DIR="$TEST_TMP/legacy-claude"
export CLAUDE_LEGACY_JSON="$TEST_TMP/legacy-claude.json"
unset SSH_AUTH_SOCK
mkdir -p "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR"

# Run migrate-from-home to seed skeleton
"$REPO_ROOT/scripts/migrate-from-home"

# Verify seeded files
[[ -f "$XDG_CONFIG_HOME/claude-container/rules/container.md" ]] || {
	echo "FAIL: rules/container.md was not seeded" >&2
	exit 1
}
[[ -f "$XDG_CONFIG_HOME/claude-container/CLAUDE.md" ]] || {
	echo "FAIL: CLAUDE.md was not seeded" >&2
	exit 1
}
[[ -f "$XDG_STATE_HOME/claude-container/claude.json" ]] || {
	echo "FAIL: claude.json was not seeded" >&2
	exit 1
}

# Verify non-destructive behavior: existing files must not be overwritten
echo "custom-instruction" > "$XDG_CONFIG_HOME/claude-container/CLAUDE.md"
"$REPO_ROOT/scripts/migrate-from-home"
grep -q "custom-instruction" "$XDG_CONFIG_HOME/claude-container/CLAUDE.md" || {
	echo "FAIL: migrate-from-home overwrote existing user CLAUDE.md" >&2
	exit 1
}

# 3. Create dummy skills directory and skills.conf
mkdir -p "$TEST_TMP/custom-skills/my-skill"
cat <<'EOF' >"$TEST_TMP/custom-skills/my-skill/SKILL.md"
---
description: Custom test skill
---
# Test Skill
EOF

mkdir -p "$XDG_CONFIG_HOME/claude-container"
echo "$TEST_TMP/custom-skills" >"$XDG_CONFIG_HOME/claude-container/skills.conf"

# 4. Setup mock podman to verify invocation arguments
mkdir -p "$TEST_TMP/extra"
mkdir -p "$TEST_TMP/workspace"
MOCK_BIN="$TEST_TMP/bin"
mkdir -p "$MOCK_BIN"
MOCK_OUT="$TEST_TMP/podman-args.log"

cat <<EOF >"$MOCK_BIN/podman"
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$MOCK_OUT"
EOF
chmod +x "$MOCK_BIN/podman"

# 5. Execute claude-container with -C container args and trailing claude args
echo "--> Testing argument collection and passthrough with mock podman..."
PATH="$MOCK_BIN:$PATH" "$REPO_ROOT/scripts/claude-container" \
	-C --privileged \
	-C "--device=/dev/fuse" \
	-m "$TEST_TMP/extra:$TEST_TMP/extra:ro" \
	"$TEST_TMP/workspace" \
	--print \
	"hello world"

# 6. Validate captured arguments in mock output
echo "--> Verifying captured podman invocation arguments..."

grep -q -- "--privileged" "$MOCK_OUT" || {
	echo "FAIL: --privileged not found in container args" >&2
	exit 1
}

grep -q -- "--device=/dev/fuse" "$MOCK_OUT" || {
	echo "FAIL: --device=/dev/fuse not found in container args" >&2
	exit 1
}

grep -q -- "docker.io/hyprhvn/claude-container:full" "$MOCK_OUT" || {
	echo "FAIL: container image name not found" >&2
	exit 1
}

# Ensure trailing claude args come AFTER the image name
IMAGE_LINE=$(grep -n "docker.io/hyprhvn/claude-container:full" "$MOCK_OUT" | cut -d: -f1)
PRINT_LINE=$(grep -n -- "--print" "$MOCK_OUT" | cut -d: -f1)
PROMPT_LINE=$(grep -n -- "hello world" "$MOCK_OUT" | cut -d: -f1)

if [[ "$PRINT_LINE" -le "$IMAGE_LINE" || "$PROMPT_LINE" -le "$IMAGE_LINE" ]]; then
	echo "FAIL: claude arguments are not placed after the container image" >&2
	exit 1
fi

# Ensure workspace directory is set correctly
if ! grep -q -- "-w" "$MOCK_OUT" || ! grep -q -- "$TEST_TMP/workspace" "$MOCK_OUT"; then
	echo "FAIL: workspace directory flag not found" >&2
	exit 1
fi

# Ensure custom mount was included
grep -q -- "$TEST_TMP/extra:$TEST_TMP/extra:ro" "$MOCK_OUT" || {
	echo "FAIL: custom mount -m was not found in podman args" >&2
	exit 1
}

# Ensure rules directory and CLAUDE.md are mounted into podman args
grep -q -- "$XDG_CONFIG_HOME/claude-container/rules:/root/.claude/rules:ro,z" "$MOCK_OUT" || {
	echo "FAIL: rules directory mount was not found in podman args" >&2
	exit 1
}
grep -q -- "$XDG_CONFIG_HOME/claude-container/CLAUDE.md:/root/.claude/CLAUDE.md:rw,z" "$MOCK_OUT" || {
	echo "FAIL: CLAUDE.md mount was not found in podman args" >&2
	exit 1
}

# 7. Test literal '--' argument separator syntax
echo "--> Testing explicit '--' argument separator..."
PATH="$MOCK_BIN:$PATH" "$REPO_ROOT/scripts/claude-container" \
	-- \
	"$TEST_TMP/workspace" \
	-p "explicit prompt"

grep -q -- "-p" "$MOCK_OUT" || {
	echo "FAIL: -p not found after '--' separator" >&2
	exit 1
}

grep -q -- "explicit prompt" "$MOCK_OUT" || {
	echo "FAIL: prompt text not found after '--' separator" >&2
	exit 1
}

# 8. Sanity-check the test environment script and its skill wiring.
#    A full test-env run needs an active SELinux host plus a privileged Test
#    container, so keep these checks side-effect-free.
echo "--> Sanity-checking scripts/test-env and the container-debug skill..."
bash -n "$REPO_ROOT/scripts/test-env" || {
	echo "FAIL: scripts/test-env has a syntax error" >&2
	exit 1
}

"$REPO_ROOT/scripts/test-env" --help | grep -q "test-env" || {
	echo "FAIL: scripts/test-env --help did not print usage" >&2
	exit 1
}

# The container-debug skill must exist where Containerfiles/Test copies it from.
[[ -f "$REPO_ROOT/skel/test/skills/container-debug/SKILL.md" ]] || {
	echo "FAIL: container-debug skill not found at skel/test/skills/" >&2
	exit 1
}

grep -q "skel/test/skills/" "$REPO_ROOT/Containerfiles/Test" || {
	echo "FAIL: Containerfiles/Test does not COPY skel/test/skills/" >&2
	exit 1
}

# test-env's contract: on a SELinux host a full run requires the privileged
# Test container (verified there); without usable SELinux it MUST hard-fail
# with a clear message rather than build a misleading environment.
# Detect SELinux the same way test-env does — via /sys/fs/selinux, NOT
# selinuxenabled: the library's mount registry may never be populated in a
# container (observed: host Enforcing, yet selinuxenabled says "disabled"
# behind a read-only bind), which would take the hard-fail branch falsely.
if [[ -f /sys/fs/selinux/enforce ]] && [[ -s /sys/fs/selinux/policy ]]; then
	echo "--> SELinux active: full test-env run is covered by the Test container workflow."
else
	"$REPO_ROOT/scripts/test-env" 2>"$TEST_TMP/test-env-err.log" && {
		echo "FAIL: test-env exited 0 without active SELinux" >&2
		exit 1
	}
	grep -qE "SELinux is not active|SELinux appears active but /sys/fs/selinux is not usable" "$TEST_TMP/test-env-err.log" || {
		echo "FAIL: test-env failed without the expected SELinux error message" >&2
		cat "$TEST_TMP/test-env-err.log" >&2
		exit 1
	}
	echo "--> test-env correctly hard-fails without usable SELinux."
fi

echo "==> All CLI argument and mount collection tests passed successfully!"
