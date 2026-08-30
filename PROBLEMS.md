# PROBLEMS — `test/self-contained-pinp-debug` (commit 92070d2)

Review verdict: **all in-container verification done** (2026-08-29/30).
A1/A2 + doc/nit fixes applied; B1 (decisive nested `ssh-add -l`) **passed**
in the `:test` container (both `--network none` and default bridge
networking after `iptables` was added); B2 (module scan) root-caused as a
dead end and redesigned (NOTE + ground-truth check instead of an impossible
gate); production note (SUMMARY finding 11) **resolved** by host
`sesearch` — base policy allows `unconfined_domain_type → domain`
unix_stream_socket connectto, covering `spc_t → unconfined_t`.
`tests/test-pinp.sh` green in all three environment combinations.
Remaining: host-side rebuild of `:test` (picks up `iptables`), rebase + merge.

## A. Functional issues (blockers)

### A1. Documented host preload procedure is incompatible with `test-env`'s module check

`scripts/test-env` detects policy modules **by module name only** —
`module_for_target()` (`scripts/test-env:59`) expects `container_ssh_forward`
(unconfined_t) and `container_ssh_forward_<selftype>` (e.g.
`container_ssh_forward_spc_t`), and `module_loaded()` (`scripts/test-env:85`) scans
the `/sys/fs/selinux/policy` blob for the NUL-terminated module *name*.

But every documented preload path pipes CIL into `semodule -i /dev/stdin`:

- `SUMMARY.md:40-47` (host step 2, both rules in one stdin module)
- `skel/test/skills/container-debug/SKILL.md:69-72` (the skill's fix-it snippet)
- `scripts/test-env:80-81` (the script's own die message)

A module installed this way is named after its input source (e.g. `stdin`), **not**
after the CIL rules — so neither expected name ever exists in the policy blob.
Result: after following the documented preload, `test-env` still hard-fails with
"module … not loaded … load it on the host, then rerun", and rerunning the same
one-liner changes nothing. The documented verification flow (SUMMARY steps 2→4)
dead-ends at exactly the step this branch exists to verify. (The launcher's own
install path uses the named-file pattern — `container_ssh_forward.cil`,
`scripts/claude-container:488` — which is why it works there.)

**Fixed:** all three snippets now preload via two named files matching
`module_for_target()` (test-env die message, SUMMARY.md step 2, SKILL.md §3.1),
and `docs/testing.md` §3.1 notes that modules are detected by name:

```bash
printf '%s' '(allow container_t unconfined_t (unix_stream_socket (connectto)))' \
    > /tmp/container_ssh_forward.cil
printf '%s' '(allow container_t spc_t (unix_stream_socket (connectto)))' \
    > /tmp/container_ssh_forward_spc_t.cil
sudo semodule -i /tmp/container_ssh_forward.cil
sudo semodule -i /tmp/container_ssh_forward_spc_t.cil
```

### A2. `tests/test-pinp.sh` step 8 fails in non-SELinux environments without libselinux-utils

Reproduced on this branch (inside the `:full` container — no usable
`/sys/fs/selinux`, no `libselinux-utils`):

```
--> Sanity-checking scripts/test-env and the container-debug skill...
FAIL: test-env failed without the expected SELinux error message
ERROR: getfilecon not found — run inside the claude-container:test image
(exit 1)
```

Root cause: `scripts/test-env:175` checks for `getfilecon` **before** the selinuxfs
detection (`scripts/test-env:186-193`). Any environment with no usable
`/sys/fs/selinux` *and* no libselinux-utils — including the suite's own documented
targets (a plain podman host, or the `alpine:3.20` outer container from
`docs/testing.md` §2) — dies with the `getfilecon` message, which
`tests/test-pinp.sh:204` does not accept. Before this commit the suite passed in
those environments; step 8 is a regression for the suite's documented scope.

**Fixed:** the selinuxfs detection block (pure file tests, needs no tools) now
runs **before** the `getfilecon` requirement in `scripts/test-env`, so the
"SELinux is not active …" message is emitted in *every* non-SELinux environment
and the contract grep in `tests/test-pinp.sh:204` holds.

**Verified:** suite green in a container without selinuxfs, both with and without
`libselinux-utils` installed (2026-08-29). Remaining: rerun inside the `:test`
container with the selinuxfs bind (takes the "SELinux active" branch at
`tests/test-pinp.sh:197`).

## B. Open verification (already flagged in SUMMARY.md — keep as TODOs)

- **B1. (done 2026-08-30) The decisive nested `ssh-add -l` check passed** —
  the fixture key was listed end-to-end under Enforcing. The `:z` relabel
  watch item did not materialize (no relabel error). Two fixes were needed
  along the way: `--network none` (nested netavark required `iptables`,
  absent from the image — now added to `Containerfiles/Test`) and the
  domain caveat below (SUMMARY findings 8–11): the nested container runs in
  `spc_t`, so the check exercised `spc_t → spc_t` (base-policy-allowed)
  rather than the design-time `container_t → spc_t` tuple.
- **B2. (root-caused 2026-08-30, fixed) The policy-blob module scan can never
  work.** Module names are not stored in the merged kernel policy
  (`/sys/fs/selinux/policy` holds `POLICY_KERN`; checkpolicy writes
  name+version only for `POLICY_MOD` files — libsepol `write.c`
  `policydb_write`), and even the symbol names that ARE in the blob are
  stored terminator-less as `[len][hash][type][x][name]` (verified
  empirically against this host's 3.9 MB blob). The old NUL-terminated
  scan was an always-false check. `ensure_connectto_rule` now warns (with
  the host-side named-file command) instead of gating inside the Test
  image; the decisive `ssh-add -l` check is the ground truth.

## C. Doc fixes

- **C1. (fixed) `SUMMARY.md` was stale:** "`debug.sh` remains deleted in the
  working tree (user's own in-flight change — do not commit it …)" — `debug.sh`
  is tracked and present, unmodified. Note removed.
- **C2. (fixed) `SKILL.md` §4 full nested run** used `-p "reply with: ok"`, which
  never exercised the SSH path. Prompt now forces `ssh-add -l` through the nested
  forwarder.

## D. Nits

- **(fixed)** `scripts/test-env`: `--help` hardcoded a `sed -n '5,28p'` line range
  over the header comment — now `sed -n '/^# test-env -/,/^$/p'`, robust to header
  edits.
- **(fixed)** Missing trailing newline at EOF: `scripts/test-env`, `SUMMARY.md`,
  `skel/test/skills/container-debug/SKILL.md`.
- **Investigated, no change needed:** `ensure_socket_label()`'s
  `getfilecon "$sock" | cut -f2` was originally flagged as a no-op, but this
  libselinux build prints `name<TAB>context` even for a *single* file (verified
  empirically) — the tab-`cut -f2` is the correct parse. A brief "cleanup" that
  dropped it broke user extraction in the relabel branch and was reverted.

## E. Observations (pre-existing, out of scope — no action for this branch)

- CI (`.github/workflows/build.yaml`) tags the **Full** build as `:base`
  (overwriting the base image with the full build) and never publishes `:full`/`:test`.
  Now more relevant because `Containerfiles/Test` does `FROM …:full`.
- This commit also removes "You are an expert systems administrator and dev-ops
  engineer." from `CLAUDE.md` — unrelated to the test feature; confirm intentional.
