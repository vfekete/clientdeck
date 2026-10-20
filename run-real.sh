#!/usr/bin/env bash
# Runs ClientDeck from a source checkout, together with the
# clientdeck-loader splash screen, in REAL mode: the privileged scripts
# really create/delete Linux users (via pkexec) and really launch apps as
# the client's user (su + xhost). See docs/comments-details.md [116],
# [138]; run-mocked.sh is the same with those actions only printed.
set -euo pipefail

export CLIENTDECK_MODE=real
echo "ClientDeck: starting in REAL mode — user accounts will actually be created/deleted." >&2

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

LOADER_BIN="$REPO_ROOT/src/loader/build/clientdeck-loader"
LOADER_PID=""
SOCKET_DIR=""

cleanup() {
    if [[ -n "$LOADER_PID" ]]; then
        kill "$LOADER_PID" 2>/dev/null || true
    fi
    if [[ -n "$SOCKET_DIR" ]]; then
        rm -rf "$SOCKET_DIR"
    fi
}
trap cleanup EXIT

# Best-effort: build (make is a no-op if already up to date) and launch
# the loader with a fresh socket for this run. Either step failing (e.g.
# the X11/Xinerama dev headers aren't installed) just means running with
# no splash, same as the packaged-build self-launch path — see [112].
if make -C "$REPO_ROOT/src/loader" >/dev/null 2>&1 && [[ -x "$LOADER_BIN" ]]; then
    SOCKET_DIR="$(mktemp -d)"
    export CLIENTDECK_LOADER_SOCKET="$SOCKET_DIR/loader.sock"
    "$LOADER_BIN" &
    LOADER_PID=$!
fi

uv run python -m clientdeck "$@"
