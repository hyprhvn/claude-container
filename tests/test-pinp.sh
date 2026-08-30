#!/usr/bin/env bash
#
# test-pinp.sh - Automated storage-layout, CLI argument, and PinP readiness
# tests.
#
# This script is designed to run either:
# 1. Directly on a system with Podman installed.
# 2. Inside a privileged outer container (e.g. alpine:3.24 or quay.io/podman/stable).
#
# The storage tests run entirely against a temporary CLAUDE_CONTAINER_DIR and
# a fake HOME, so they need no Podman at all. The mock podman binary captures
# the launcher's `podman run` arguments; it overwrites its log per run, so
# assertions happen immediately after each run.

set -eEuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d "/tmp/claude-container-test.XXXXXX")"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

cleanup() {
	rm -rf "$TEST_TMP"
}
trap cleanup EXIT

echo "==> Running CLI argument, mount, and skel tests in: $TEST_TMP"

# Isolated environment: a fake HOME keeps git/ssh lookups inside TEST_TMP.
export HOME="$TEST_TMP/home"
mkdir -p "$HOME"
CC_DIR="$TEST_TMP/cc"
export CLAUDE_CONTAINER_DIR="$CC_DIR"
unset SSH_AUTH_SOCK

# 1. Test CLI Help
echo "--> Testing --help option..."
"$REPO_ROOT/scripts/claude-container" --help >/dev/null || fail "claude-container --help"

# 2. Syntax-check all scripts; shellcheck when available
echo "--> Syntax-checking scripts..."
for s in claude-container update-skel test-env; do
	bash -n "$REPO_ROOT/scripts/$s" || fail "scripts/$s has a syntax error"
done
if command -v shellcheck >/dev/null 2>&1; then
	for s in claude-container update-skel; do
		shellcheck -s bash "$REPO_ROOT/scripts/$s" || fail "shellcheck scripts/$s"
	done
fi

# 3. Test one-time installation seeding via update-skel --seed
echo "--> Testing one-time seeding via update-skel --seed..."
"$REPO_ROOT/scripts/update-skel" --seed || fail "update-skel --seed (fresh)"

for f in CLAUDE.md settings.json statusline.sh claude.json rules/container.md hooks/session-start.sh hooks/README.md; do
	[[ -f "$CC_DIR/$f" ]] || fail "seeding did not create $CC_DIR/$f"
done
[[ -x "$CC_DIR/hooks/session-start.sh" ]] || fail "seeded hooks/session-start.sh is not executable"
[[ -f "$CC_DIR/.skel-manifest.tsv" ]] || fail "seeding did not create .skel-manifest.tsv"
grep -q "rules/container.md" "$CC_DIR/.skel-manifest.tsv" || fail "manifest lacks rules/container.md"
[[ ! -e "$CC_DIR/test" ]] || fail "skel/test/ must never be seeded"

# Verify non-destructive behavior: existing files must not be overwritten
echo "custom-instruction" >"$CC_DIR/CLAUDE.md"
"$REPO_ROOT/scripts/update-skel" --seed >/dev/null || fail "update-skel --seed (re-run)"
grep -q "custom-instruction" "$CC_DIR/CLAUDE.md" || fail "update-skel overwrote existing user CLAUDE.md"

# 4. Test update-skel semantics
echo "--> Testing update-skel semantics..."
CC3="$TEST_TMP/cc-skel"
US() {
	CLAUDE_CONTAINER_DIR="$CC3" "$REPO_ROOT/scripts/update-skel" "$@"
}

US --seed || fail "update-skel --seed"
[[ -f "$CC3/settings.json" ]] || fail "update-skel did not seed settings.json"

# manifest hash must match the installed file
h=$(sha256sum "$CC3/rules/container.md" | awk '{print $1}')
awk -F'\t' -v h="$h" '$1 == "rules/container.md" && $2 == h { found = 1 } END { exit !found }' \
	"$CC3/.skel-manifest.tsv" || fail "update-skel: manifest hash mismatch"

# idempotent, silent re-seed: no output, manifest untouched
m1=$(sha256sum "$CC3/.skel-manifest.tsv")
out=$(US --seed 2>&1) || fail "update-skel re-seed"
[[ -z "$out" ]] || fail "update-skel re-seed not silent: $out"
[[ "$(sha256sum "$CC3/.skel-manifest.tsv")" == "$m1" ]] || fail "update-skel re-seed rewrote the manifest"

# a modified destination must survive both --seed and --update
echo "user edit" >>"$CC3/CLAUDE.md"
out=$(US --update 2>&1) || fail "update-skel --update"
echo "$out" | grep -q "user-managed" || fail "update-skel --update did not report the user-managed file"
grep -q "user edit" "$CC3/CLAUDE.md" || fail "update-skel --update clobbered a modified file"
US --seed >/dev/null || fail "update-skel --seed after edit"
grep -q "user edit" "$CC3/CLAUDE.md" || fail "update-skel --seed clobbered a modified file"

# skel template change: --seed must refuse to refresh, --update must
SKEL2="$TEST_TMP/skel-modified"
cp -a "$REPO_ROOT/skel" "$SKEL2"
echo "template v2" >>"$SKEL2/rules/container.md"
out=$(CLAUDE_CONTAINER_SKEL="$SKEL2" US --seed 2>&1) || fail "update-skel --seed (skel changed)"
echo "$out" | grep -q "run --update" || fail "update-skel --seed did not report the stale template"
grep -q "template v2" "$CC3/rules/container.md" && fail "update-skel --seed refreshed a stale template"
CLAUDE_CONTAINER_SKEL="$SKEL2" US --update >/dev/null || fail "update-skel --update (skel changed)"
grep -q "template v2" "$CC3/rules/container.md" || fail "update-skel --update did not refresh the stale template"

# --force <path>: restore the template, leave a .bak sidecar
echo "local tweak" >>"$CC3/rules/container.md"
CLAUDE_CONTAINER_SKEL="$SKEL2" US --force rules/container.md >/dev/null || fail "update-skel --force <path>"
grep -q "local tweak" "$CC3/rules/container.md" && fail "--force <path> did not restore the template"
grep -q "template v2" "$CC3/rules/container.md" || fail "--force <path> restored the wrong content"
ls "$CC3"/rules/container.md.bak.* >/dev/null 2>&1 || fail "--force <path> left no .bak sidecar"

# --force (bare): force all tracked files
echo "another edit" >>"$CC3/settings.json"
CLAUDE_CONTAINER_SKEL="$SKEL2" US --force >/dev/null || fail "update-skel --force"
grep -q "another edit" "$CC3/settings.json" && fail "--force (bare) did not force all tracked files"
ls "$CC3"/settings.json.bak.* >/dev/null 2>&1 || fail "--force (bare) left no .bak sidecar"

# a stow-style symlink is never replaced, and loses its manifest entry
echo "stowed content" >"$TEST_TMP/stowed-CLAUDE.md"
rm "$CC3/CLAUDE.md"
ln -s "$TEST_TMP/stowed-CLAUDE.md" "$CC3/CLAUDE.md"
US --seed >/dev/null 2>&1 || fail "update-skel (symlink dest)"
[[ -L "$CC3/CLAUDE.md" ]] || fail "update-skel replaced a stow symlink"
grep -q "stowed content" "$CC3/CLAUDE.md" || fail "update-skel corrupted a stow symlink target"
awk -F'\t' '$1 == "CLAUDE.md" { exit 1 } END { exit 0 }' "$CC3/.skel-manifest.tsv" \
	|| fail "update-skel did not drop the manifest entry of a symlinked file"

# --dry-run purity: nothing on disk may change
rm "$CC3/statusline.sh"
snap=$(cd "$CC3" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum)
US --seed --dry-run >/dev/null || fail "update-skel --dry-run"
[[ -e "$CC3/statusline.sh" ]] && fail "--dry-run created a file"
snap2=$(cd "$CC3" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum)
[[ "$snap" == "$snap2" ]] || fail "--dry-run modified the tree"

# 5. Setup mock podman to verify invocation arguments
echo "--> Testing argument collection and unified mounts with mock podman..."
CC4="$TEST_TMP/cc-launch"
mkdir -p "$CC4"
mkdir -p "$TEST_TMP/custom-skills/my-skill"
cat <<'EOF' >"$TEST_TMP/custom-skills/my-skill/SKILL.md"
---
description: Custom test skill
---
# Test Skill
EOF
echo "$TEST_TMP/custom-skills" >"$CC4/skills.conf"

MOCK_BIN="$TEST_TMP/bin"
MOCK_OUT="$TEST_TMP/podman-args.log"
mkdir -p "$MOCK_BIN"
cat <<EOF >"$MOCK_BIN/podman"
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$MOCK_OUT"
EOF
chmod +x "$MOCK_BIN/podman"

mkdir -p "$TEST_TMP/extra" "$TEST_TMP/workspace"

# 6. One-time installation seeding (the launcher does not seed), then run
# claude-container on the clean CLAUDE_CONTAINER_DIR
CLAUDE_CONTAINER_DIR="$CC4" "$REPO_ROOT/scripts/update-skel" --seed >/dev/null \
	|| fail "update-skel --seed (pre-seed for launcher test)"
[[ -f "$CC4/rules/container.md" ]] || fail "install-time seeding did not seed rules"
[[ -f "$CC4/settings.json" ]] || fail "install-time seeding did not seed settings.json"
[[ -x "$CC4/hooks/session-start.sh" ]] || fail "install-time seeding did not seed hooks"
grep -q '"statusLine"' "$CC4/settings.json" || fail "seeded settings.json lacks the statusLine wiring"
grep -q 'session-start.sh' "$CC4/settings.json" || fail "seeded settings.json lacks the SessionStart hook"

PATH="$MOCK_BIN:$PATH" CLAUDE_CONTAINER_DIR="$CC4" "$REPO_ROOT/scripts/claude-container" \
	-C --privileged \
	-C "--device=/dev/fuse" \
	-m "$TEST_TMP/extra:$TEST_TMP/extra:ro" \
	"$TEST_TMP/workspace" \
	--print \
	"hello world" 2>/dev/null || fail "claude-container (mock podman)"

echo "--> Verifying captured podman invocation arguments..."

# the unified mount set: rw parent, claude.json, seven ro instruction trees
grep -q -- "$CC4:/root/.claude:rw,z" "$MOCK_OUT" || fail "rw parent mount missing"
grep -q -- "$CC4/claude.json:/root/.claude.json:rw,z" "$MOCK_OUT" || fail "claude.json mount missing"
for d in rules agents hooks themes output-styles workflows commands; do
	grep -q -- "$CC4/$d:/root/.claude/$d:ro,z" "$MOCK_OUT" || fail "ro mount for $d missing"
done

# external skills from skills.conf are still mounted per skill
grep -q -- "$TEST_TMP/custom-skills/my-skill:/root/.claude/skills/my-skill:ro,z" "$MOCK_OUT" \
	|| fail "skills.conf skill mount missing"

# container args, image, and argument ordering
grep -q -- "--privileged" "$MOCK_OUT" || fail "--privileged not found in container args"
grep -q -- "--device=/dev/fuse" "$MOCK_OUT" || fail "--device=/dev/fuse not found in container args"
grep -q -- "docker.io/hyprhvn/claude-container:full" "$MOCK_OUT" || fail "container image name not found"

IMAGE_LINE=$(grep -n "docker.io/hyprhvn/claude-container:full" "$MOCK_OUT" | cut -d: -f1)
PRINT_LINE=$(grep -n -- "--print" "$MOCK_OUT" | cut -d: -f1)
PROMPT_LINE=$(grep -n -- "hello world" "$MOCK_OUT" | cut -d: -f1)
if [[ "$PRINT_LINE" -le "$IMAGE_LINE" || "$PROMPT_LINE" -le "$IMAGE_LINE" ]]; then
	fail "claude arguments are not placed after the container image"
fi

if ! grep -q -- "-w" "$MOCK_OUT" || ! grep -q -- "$TEST_TMP/workspace" "$MOCK_OUT"; then
	fail "workspace directory flag not found"
fi
grep -q -- "$TEST_TMP/extra:$TEST_TMP/extra:ro" "$MOCK_OUT" || fail "custom mount -m was not found in podman args"

# 7. Test literal '--' argument separator syntax (assert before the next
# run overwrites the mock log)
echo "--> Testing explicit '--' argument separator..."
PATH="$MOCK_BIN:$PATH" CLAUDE_CONTAINER_DIR="$CC4" "$REPO_ROOT/scripts/claude-container" \
	-- \
	"$TEST_TMP/workspace" \
	-p "explicit prompt" 2>/dev/null || fail "claude-container (separator)"

grep -q -- "-p" "$MOCK_OUT" || fail "-p not found after '--' separator"
grep -q -- "explicit prompt" "$MOCK_OUT" || fail "prompt text not found after '--' separator"

# 8. Sanity-check the test environment script and its skill wiring.
#     A full test-env run needs an active SELinux host plus a privileged
#     Test container, so keep these checks side-effect-free.
echo "--> Sanity-checking scripts/test-env and the container-debug skill..."
bash -n "$REPO_ROOT/scripts/test-env" || fail "scripts/test-env has a syntax error"

"$REPO_ROOT/scripts/test-env" --help | grep -q "test-env" || fail "scripts/test-env --help did not print usage"

# The container-debug skill must exist where Containerfiles/Test copies it from.
[[ -f "$REPO_ROOT/skel/test/skills/container-debug/SKILL.md" ]] \
	|| fail "container-debug skill not found at skel/test/skills/"

grep -q "skel/test/skills/" "$REPO_ROOT/Containerfiles/Test" \
	|| fail "Containerfiles/Test does not COPY skel/test/skills/"

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
		fail "test-env exited 0 without active SELinux"
	}
	grep -qE "SELinux is not active|SELinux appears active but /sys/fs/selinux is not usable" "$TEST_TMP/test-env-err.log" || {
		echo "FAIL: test-env failed without the expected SELinux error message" >&2
		cat "$TEST_TMP/test-env-err.log" >&2
		exit 1
	}
	echo "--> test-env correctly hard-fails without usable SELinux."
fi

echo "==> All CLI argument, mount, and skel tests passed successfully!"
