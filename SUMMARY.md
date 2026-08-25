# Handoff Summary — Test Container for Self-Contained PinP Debugging

## Goal (agreed with user)

Start the agent with `--privileged` and let it **debug the container setup itself** — via
Podman-in-Podman, *not* by giving the container access to the host. A third image,
`Containerfiles/Test`, bundles the testing tools and `scripts/test-env` sets up the testing
environment inside the container (fixture ssh-agent + socat forwarder + SELinux policy checks).

**Decisions:**
- SELinux is a **hard requirement** for `scripts/test-env` (exit 1 without it; Permissive = warn).
- The policy target is the forwarder's **server process domain** (SELinux socket *peer*
  mediation: `allow container_t <server_domain> (unix_stream_socket (connectto))`), read from
  `/proc/self/attr/current` — usually `spc_t` in a privileged container, **not** the canonical
  `unconfined_t`. The canonical rule is kept in sync for real hosts.
- No changes to `scripts/claude-container` (the agent runs it unchanged against nested podman).
- Alpine has no `setools`; policy is verified via `semodule -l` + the behavioral check.

## What was implemented (uncommitted)

| File | Change |
| --- | --- |
| `Containerfiles/Test` | `FROM full` + `podman fuse-overlayfs shadow` + `libselinux-utils semodule-utils`; bakes `skel/config/CLAUDE.md`, `skel/config/rules/`, `skel/test/skills/` into `/root/.claude/` (build context = repo root) |
| `scripts/test-env` (new, 755) | Hard SELinux gate → mount selinuxfs → vfs `storage.conf` → fixture `ssh-agent` (+ throwaway key) → `socat` forwarder chcon'd to `container_file_t` → ensures `container_t → <self-type>` + `unconfined_t` connectto modules → status report with the decisive `podman run --entrypoint ssh-add … -l` command. `--down` tears down. Idempotent. |
| `skel/test/skills/container-debug/SKILL.md` (new) | On-demand debug skill (Test-image only — `skel/test/` is deliberately **not** seeded into user configs). Setup → decisive check → diagnosis (policy / label / socat / `dmesg` AVC) → optional full nested launcher run. |
| `docs/testing.md` | New §3 "Test Image" (setup, hard gate, peer-mediation note, agent debug workflow). |
| `docs/ssh-agent-forwarding.md` | §5 rewritten: live-host verification + self-contained test environment (dangling `debug.sh` reference removed). |
| `README.md` | Build section: third image, explicit repo-root build context. |
| `CLAUDE.md` | One line under Testing & Diagnostics. |
| `tests/test-pinp.sh` | Side-effect-free sanity checks (syntax, `--help`, skill wiring) + deterministic hard-fail contract test in non-SELinux environments. |

`debug.sh` remains deleted in the working tree (user's own in-flight change — do not commit it
as part of this work). `Containerfiles/Test` was the user's draft, extended as above.

## Commands to run on the host (SELinux Fedora)

1. **Build** (from the repository root):
   ```bash
   podman build -f Containerfiles/Test -t docker.io/hyprhvn/claude-container:test .
   ```
2. **Pre-load the policy modules** (the Test image cannot compile CIL — no
   `checkpolicy`/`semodule` in the Alpine repo; see findings below):
   ```bash
   printf '%s\n' \
     '(allow container_t spc_t (unix_stream_socket (connectto)))' \
     '(allow container_t unconfined_t (unix_stream_socket (connectto)))' \
     | sudo semodule -i /dev/stdin
   ```
3. **Start privileged + rootful** (rootful needed so the host-side
   `semodule -i` can load policy; the **selinuxfs bind is required** — the
   `spc_t` domain cannot mount selinuxfs itself — and `:ro` is sufficient,
   since the image never writes selinuxfs: it cannot load modules, so the
   only potential write, `semodule -i` → `/sys/fs/selinux/load`, is
   host-side):
   ```bash
   sudo podman run -it --rm --privileged \
       -v /sys/fs/selinux:/sys/fs/selinux:ro \
       -v "$PWD":/workspace:z -w /workspace \
       docker.io/hyprhvn/claude-container:test
   ```
4. **In the session:** `run ./scripts/test-env, then use the container-debug skill to verify
   the SSH agent forwarding setup and report what you find.`

**Expected:** `SELinux mode: Enforcing` (read from `/sys/fs/selinux/enforce`, not
`getenforce`), `Test container domain: spc_t`, fixture agent + forwarder up with the
socket of type `container_file_t`, both modules detected in the policy blob, and the
decisive `podman run --rm --entrypoint ssh-add … -l` listing the throwaway key
(first run pulls `full` into nested vfs storage — takes a moment).

**Rootless fallback:** build as above; run without `sudo`; load the modules on the
host (step 2), then rerun `./scripts/test-env`.

## First test run (2026-08-25, in-container agent) — findings & fixes

The agent ran inside the `:test` image (`--privileged`, host SELinux **Enforcing**,
`spc_t` domain) with a `:ro` selinuxfs bind. Findings (all verified in-container):

1. **libselinux is blind in the container.** `selinuxenabled` → 1 and `getenforce` →
   "Disabled" although the host is Enforcing (enforce=1, `seclabel` mounts, real policy
   blob). Reverse-engineered `libselinux.so.1` (3.10): `is_selinux_enabled()` reads a
   lazily-initialized mount registry (statfs-magic helper + `access(F_OK)`) that never
   populates here — no files are opened at all. Old consequence: `test-env`'s gate died
   with the wrong diagnosis, and `tests/test-pinp.sh` printed the false
   "correctly hard-fails without SELinux" (observed on the Enforcing host).
   **Fix:** `test-env` and the suite now detect SELinux via `/sys/fs/selinux/enforce` +
   non-empty `policy` directly. Whether an rw (vs ro) bind makes libselinux work is
   still open — probe on next start.
2. **No `semodule` binary, ever, on Alpine.** `semodule-utils` ships only the
   `semodule_*` helpers; the repo has no `checkpolicy` package. `test-env`'s
   check/install could never work. **Fix:** module check = NUL-terminated name scan of
   `/sys/fs/selinux/policy` (python3, exact-match so `…_spc_t` ≠ canonical); missing
   module → hard error with the host-side `semodule -i` one-liner. Modules are therefore
   pre-loaded on the host (new step 2 above).
3. **No `chcon`, and the container rootfs refuses label writes** (setxattr
   `security.selinux` → ENOTSUPP on overlay; ext4 workspace works). Files on the rootfs
   are created already labeled `container_file_t`. **Fix:** `test-env` now uses
   `getfilecon` + `setfilecon`, verify-first/fail-only-if-wrong
   (`ensure_socket_label`).
4. **`spc_t` cannot mount selinuxfs** (`mount -t selinuxfs` → EPERM with full CapEff;
   `umount` works) — SELinux policy denial. `test-env`'s self-mount fallback is dead on
   Enforcing hosts; the runtime must provide the bind. **Fix:** bind is documented as
   required (SKILL.md, docs/testing.md, docs/ssh-agent-forwarding.md, SUMMARY.md);
   `test-env` still attempts the mount (harmless) but reports accurately.
5. **`container-debug` skill shadowed by the launcher.** Baked into
   `/root/.claude/skills`, but the launcher bind-mounts the host config's `skills/` over
   it (verified in `/proc/mounts`) — invisible through the launcher, visible via raw
   `podman run`. **Fix (docs for now):** documented in testing.md §3.2 with a
   `cp -r … <workspace>/.claude/skills/` workaround. Open design question: bake location
   vs launcher mount.
6. **Skill-doc diagnostics broken in the image.** `dmesg` → EPERM even `--privileged`
   (host `dmesg_restrict`); `ls -lZ` unsupported (coreutils w/o SELinux); `ps -eZ` works.
   **Fix:** SKILL.md now uses `/sys/fs/selinux/avc/messages`, `getfilecon`, and the
   policy-blob module check.

Also verified working: `--privileged` fully effective (CapEff full), `spc_t` domain,
nested podman 5.8.6 + `ssh-agent` + `socat` present, vfs storage writable, full
`test-pinp.sh` arg/mount/`--`-separator suite green, test-env hard-fail contract (exit 1
+ message).

Note: during diagnosis the ro selinuxfs bind was unmounted (a fresh self-mount was
denied by SELinux, finding 4), so the container must be (re)started with the bind to
have selinuxfs at all. The `:ro` bind is sufficient for the whole flow (see step 3);
an earlier "use rw" recommendation was premature — the in-container module-load path
it would enable does not exist on Alpine.

## After host verification — remaining work

1. ~~Run `bash tests/test-pinp.sh`~~ — done in-container (2026-08-25), green; the
   contract branch now keys off `/sys/fs/selinux` instead of `selinuxenabled`.
2. ~~Fix anything the run surfaces~~ — findings 1–6 fixed in the working tree;
   outstanding: confirm the decisive `ssh-add -l` end-to-end after the host preload +
   restart. (Whether libselinux itself detects selinuxfs behind the ro bind is now
   academic — test-env and the suite no longer depend on it.)
3. Review the diff and commit (message style: `feat(test): …`; do **not** commit `debug.sh`
   deletion or unrelated user work unless asked).

## Gotchas worth remembering

- `:z` does **not** relabel live Unix sockets — the explicit `chcon -t container_file_t` is what matters.
- Image `ENTRYPOINT` is `claude`, so the decisive check needs `--entrypoint ssh-add … -l`.
- The nested launcher cleans up its own `$RUNTIME_DIR` on exit — the fixture lives in
  `/var/test/claude-container/` precisely so it survives.
- The fixture ssh-agent env vars must be unset when spawning the fixture agent
  (`env -u SSH_AGENT_PID -u SSH_AUTH_SOCK`).
- BusyBox grep: no `\b` — use `grep -qE "^name([[:space:]]|\$)"`.