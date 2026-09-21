#!/usr/bin/env bash
# Runs ClientDeck from a source checkout, via uv (see CLAUDE.md: "uv manages
# the virtualenv and all dependency/test execution").
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

exec uv run python -m clientdeck "$@"
