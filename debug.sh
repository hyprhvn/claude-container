#!/usr/bin/env bash

# SSH-agent-forwarding diagnostics. Run on the HOST (not inside the container).
# Best run while the container is up, so the socat socket still exists.
#
#   ./debug.sh | tee out.txt
#
# `out.txt` is then the record of the state this fix produced; read it back to
# decide whether the fix worked.

set -u

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/claude-container"

echo "=== SELinux mode (should be Enforcing) ==="
getenforce


echo
echo "=== container_connect_any (informational: governs TCP/UDP only, not Unix sockets) ==="
getsebool container_connect_any

echo
echo "=== GNOME Keyring agent socket (source, left untouched) ==="
ls -lZ "${SSH_AUTH_SOCK:-/run/user/1000/gcr/ssh}"

echo
echo "=== socat forwarder socket (KEY: should now be container_file_t) ==="
if [[ -S "$RUNTIME_DIR/agent.sock" ]]; then
    ls -lZ "$RUNTIME_DIR/agent.sock"
    echo "--- socat process SELinux context & details ---"
    ps -eZ | grep socat || true
    echo "--- parent directory SELinux label ---"
    ls -ldZ "$RUNTIME_DIR"
    echo "--- open unix sockets for socat ---"
    ss -xlp | grep -E "agent\.sock|socat" || true
    echo "--- SELinux socket security context via /proc (if accessible) ---"
    socat_pid=$(pgrep socat | head -n1 || true)
    if [[ -n "$socat_pid" ]]; then
        ls -lZ /proc/$socat_pid/fd/ 2>/dev/null || true
    fi
else
    echo "MISSING — container/socat not running; rerun while the container is up"
fi

echo
echo "=== chcon self-test: can chcon relabel a live unix socket at all? ==="
sockdir="$(mktemp -d)"
sock="$sockdir/sock"
socat "UNIX-LISTEN:$sock" /dev/null 2>/dev/null &
socat_pid=$!
sleep 0.3
before=$(stat -c '%C' "$sock" 2>/dev/null)
chcon -t container_file_t "$sock" 2>&1 || echo "(chcon failed)"
after=$(stat -c '%C' "$sock" 2>/dev/null)
echo "label: ${before:-?} -> ${after:-?}"
kill "$socat_pid" 2>/dev/null

echo
echo "=== SELinux policy checks for unix_stream_socket ==="
if command -v sesearch >/dev/null 2>&1; then
    sesearch -A -s container_t -t container_file_t -c unix_stream_socket 2>&1 || true
    sesearch -A -s container_t -t unconfined_t -c unix_stream_socket 2>&1 || true
    sesearch -A -s container_t -c unix_stream_socket -p connectto 2>&1 || true
    sesearch -A -s container_t -c sock_file 2>&1 || true
else
    echo "sesearch not installed on host (setools-console)"
fi

