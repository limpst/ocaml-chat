#!/usr/bin/env bash
# =========================================================================
#  tests/smoke.sh - end-to-end smoke test (Linux / macOS / Git Bash)
#  Starts bin/server.exe, drives bin/client.exe with scripted input,
#  and checks the client's screen output.  Run after build.sh / build.ps1.
# =========================================================================
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT=${PORT:-9123}
WORK=$(mktemp -d)
cd "$WORK"                       # chat_history.log is written here, not in the repo

"$ROOT/bin/server.exe" "$PORT" > server.log 2>&1 &
SERVER_PID=$!
cleanup() {
    kill "$SERVER_PID" 2>/dev/null || true
    if command -v taskkill >/dev/null 2>&1; then taskkill //F //IM server.exe >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

# Wait until the server is listening (max ~10s)
for _ in $(seq 1 50); do
    grep -q "listening on port" server.log 2>/dev/null && break
    sleep 0.2
done

printf '%s\n' '/nick bad name!' '/nick alice' 'hello smoke' '/who' '/history' '/quit' \
    | timeout 20 "$ROOT/bin/client.exe" 127.0.0.1 "$PORT" > client.log 2>&1

echo "---- client ----"; cat client.log
echo "---- server ----"; cat server.log

failed=0
expect() {
    if grep -qF -- "$1" client.log; then echo "ok   $1"; else echo "FAIL $1"; failed=1; fi
}
expect "*** Welcome, guest1!"
expect "!!! invalid nickname"
expect "*** guest1 is now known as alice"
expect "alice: hello smoke"
expect "*** online (1): alice"
expect "*** ---- last messages ----"
expect "*** disconnected from server"
exit "$failed"
