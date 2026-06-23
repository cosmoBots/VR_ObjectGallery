#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGETS_ENV_PATH="${ROOT_DIR}/.targets"

if [[ ! -f "$TARGETS_ENV_PATH" ]]; then
  echo "ERROR: No existe ${TARGETS_ENV_PATH}" >&2
  echo "Copia .targets.example a .targets y ajusta META_SERIAL para esta maquina." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$TARGETS_ENV_PATH"

if [[ -z "${META_SERIAL:-}" ]]; then
  echo "ERROR: META_SERIAL esta vacio en .targets" >&2
  exit 1
fi

exec "${ROOT_DIR}/view_headset.sh" "$META_SERIAL" "$@"
