#!/usr/bin/env bash
# Packages ClientDeck into a single-file executable.
#
# Implements claude-blocks/python-single-app-instance.claude.md for this
# project: a PySide6/Qt GUI app, built via `pyside6-deploy` (which drives
# Nuitka's --onefile mode under the hood). Run with zero arguments; output
# lands at dist/clientdeck-<version> (no extension, chmod +x).
#
# This is a one-time-setup script per CLAUDE.md's "Deployment / packaging"
# section: once it works, extend it for new needs (e.g. a new bundled asset
# directory) rather than regenerating it from the blueprint from scratch.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

APP_NAME="clientdeck"
ENTRY_POINT="src/clientdeck/__main__.py"
DIST_DIR="$REPO_ROOT/dist"
SPEC_FILE="$REPO_ROOT/src/clientdeck/pysidedeploy.spec"
DEPLOYMENT_DIR="$REPO_ROOT/src/clientdeck/deployment"

echo "==> Checking version consistency (pyproject.toml vs. clientdeck.__version__)"
VERSION="$(uv run python tools/check_versions.py)"
echo "    version: $VERSION"

echo "==> Checking required assets"
for asset in resources/app_icon.png src/clientdeck/qml/Main.qml src/scripts/launch_as_user.py src/scripts/create_user.py; do
  if [[ ! -f "$asset" ]]; then
    echo "error: required asset missing: $asset" >&2
    exit 1
  fi
done

echo "==> Cleaning previous build artifacts"
rm -rf "$DIST_DIR" "$SPEC_FILE" "$DEPLOYMENT_DIR" \
       "$REPO_ROOT"/src/clientdeck/deploy_main.py
# --include-raw-dir (below) bundles src/scripts/ verbatim, __pycache__ and
# all — strip local bytecode cache first so it doesn't ship in the binary.
find "$REPO_ROOT/src/scripts" -name "__pycache__" -type d -exec rm -rf {} +
mkdir -p "$DIST_DIR"

echo "==> Installing the (isolated, build-only) packaging dependency group"
uv sync --group build

OUTPUT_NAME="${APP_NAME}-${VERSION}"

echo "==> Generating pysidedeploy.spec (auto-detects QML files/Qt modules)"
uv run pyside6-deploy "$ENTRY_POINT" --init -f

echo "==> Patching spec: title, icon, output dir, and bundling src/scripts/"
# src/scripts/ is a sibling of src/clientdeck/, not a subdirectory of it, so
# pyside6-deploy's own auto-bundling (which only picks up subdirectories
# next to the entry point, e.g. qml/) never sees it — it must be added
# explicitly, or app.paths.get_scripts_dir() finds nothing once packaged.
#
# Uses --include-raw-dir, not --include-data-dir: Nuitka's --include-data-dir
# silently *excludes* .py files by default (it treats them as source, not
# data) and src/scripts/ contains only .py files — confirmed by actually
# building with --include-data-dir first: Nuitka logged "No data files in
# directory '.../src/scripts'" and the scripts were silently left out
# entirely. --include-raw-dir bundles the directory's contents verbatim.
sed -i "s|^title = .*|title = ${OUTPUT_NAME}|" "$SPEC_FILE"
sed -i "s|^exec_directory = .*|exec_directory = ${DIST_DIR}|" "$SPEC_FILE"
sed -i "s|^icon = .*|icon = ${REPO_ROOT}/resources/app_icon.png|" "$SPEC_FILE"
sed -i "s|^extra_args = .*|extra_args = --quiet --noinclude-qt-translations --include-raw-dir=${REPO_ROOT}/src/scripts=./scripts|" "$SPEC_FILE"

echo "==> Running pyside6-deploy (Nuitka onefile build — this takes a while)"
uv run pyside6-deploy "$ENTRY_POINT" -c "$SPEC_FILE" -f

GENERATED_BIN="$DIST_DIR/${OUTPUT_NAME}.bin"
FINAL_BIN="$DIST_DIR/${OUTPUT_NAME}"

if [[ ! -f "$GENERATED_BIN" ]]; then
  echo "error: expected output not found at $GENERATED_BIN" >&2
  exit 1
fi

mv "$GENERATED_BIN" "$FINAL_BIN"
chmod +x "$FINAL_BIN"

echo "==> Cleaning up deploy-time leftovers"
rm -rf "$SPEC_FILE" "$DEPLOYMENT_DIR" "$REPO_ROOT"/src/clientdeck/deploy_main.py

echo "==> Done: $FINAL_BIN"
