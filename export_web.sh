#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_PRESET_NAME="Web"
EXPORT_PATH="${ROOT_DIR}/web/index.html"

find_godot() {
  local candidate
  for candidate in godot4.6 godot4 godot; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  for candidate in "${HOME}/soft/Godot_v4.6.2-stable_linux.x86_64"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

main() {
  local godot_cmd
  godot_cmd="$(find_godot)" || {
    echo "ERROR: No encuentro godot4.6, godot4 ni godot en PATH." >&2
    echo "Abre Godot y exporta manualmente el preset '${EXPORT_PRESET_NAME}' a web/index.html." >&2
    exit 1
  }

  mkdir -p "${ROOT_DIR}/web"
  cd "$ROOT_DIR"
  "$godot_cmd" --headless --export-release "$EXPORT_PRESET_NAME" "$EXPORT_PATH"
}

main "$@"
