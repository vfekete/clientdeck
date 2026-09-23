#!/usr/bin/env bash
# Builds and runs clientdeck-loader standalone — no app, no socket — for
# manual visual testing of the splash by itself. See
# docs/comments-details.md [120].
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

make -C "$REPO_ROOT/src/loader"

exec "$REPO_ROOT/src/loader/build/clientdeck-loader"
