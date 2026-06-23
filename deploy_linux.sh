#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_PRESET_NAME="${EXPORT_PRESET_NAME:-Linux}"
EXPORT_PRESETS_PATH="${ROOT_DIR}/export_presets.cfg"
GODOT_BIN="${GODOT_BIN:-$HOME/soft/Godot_v4.6.2-stable_linux.x86_64}"
BUILD_LOG="${BUILD_LOG:-/tmp/vr_objectgallery_linux_build.log}"
EXPORT_MODE="${EXPORT_MODE:-debug}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || die "No existe: $path"
}

check_godot_available() {
  [[ -x "$GODOT_BIN" ]] || die "No encuentro Godot ejecutable en GODOT_BIN=$GODOT_BIN"
}

preset_export_path() {
  local preset_name="$1"
  local preset_platform="$2"
  local current_name=""
  local current_platform=""
  local current_export_path=""

  require_file "$EXPORT_PRESETS_PATH"

  while IFS= read -r line; do
    case "$line" in
      \[preset.*\])
        current_name=""
        current_platform=""
        current_export_path=""
        ;;
      name=\"*\")
        current_name="${line#name=\"}"
        current_name="${current_name%\"}"
        ;;
      platform=\"*\")
        current_platform="${line#platform=\"}"
        current_platform="${current_platform%\"}"
        ;;
      export_path=\"*\")
        current_export_path="${line#export_path=\"}"
        current_export_path="${current_export_path%\"}"
        if [[ "$current_name" == "$preset_name" && "$current_platform" == "$preset_platform" ]]; then
          printf '%s\n' "$current_export_path"
          return 0
        fi
        ;;
    esac
  done < "$EXPORT_PRESETS_PATH"

  return 1
}

resolve_export_path() {
  local export_path
  export_path="$(preset_export_path "$EXPORT_PRESET_NAME" "Linux")" || die "No encuentro el export_path del preset Linux '$EXPORT_PRESET_NAME'"

  case "$export_path" in
    /*) printf '%s\n' "$export_path" ;;
    ./*) printf '%s/%s\n' "$ROOT_DIR" "${export_path#./}" ;;
    *) printf '%s/%s\n' "$ROOT_DIR" "$export_path" ;;
  esac
}

latest_source_file() {
  find "$ROOT_DIR" \
    \( -path "$ROOT_DIR/.git" -o -path "$ROOT_DIR/.godot" -o -path "$ROOT_DIR/android/build" -o -path "$ROOT_DIR/addons" -o -path "$ROOT_DIR/web" \) -prune -o \
    -type f \
    \( \
      -name "*.gd" -o \
      -name "*.tscn" -o \
      -name "*.tres" -o \
      -name "*.godot" -o \
      -name "*.cfg" -o \
      -name "*.yaml" -o \
      -name "*.yml" -o \
      -path "$ROOT_DIR/models/*" \
    \) \
    ! -name "*.import" \
    ! -name "*.md5" \
    ! -name "*.apk" \
    ! -name "*.x86_64" \
    ! -name "*.pck" \
    -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-
}

export_needs_build() {
  local newest_source
  newest_source="$(latest_source_file)"
  [[ -n "$newest_source" ]] || die "No he encontrado ficheros fuente a comparar"

  if [[ ! -f "$BINARY_PATH" ]]; then
    echo "Binario: no existe $BINARY_PATH"
    echo "Fuente:  $(stat -c '%y %n' "$newest_source")"
    return 0
  fi

  local binary_mtime src_mtime
  binary_mtime="$(stat -c '%Y' "$BINARY_PATH")"
  src_mtime="$(stat -c '%Y' "$newest_source")"

  echo "Binario: $(stat -c '%y %n' "$BINARY_PATH")"
  echo "Fuente:  $(stat -c '%y %n' "$newest_source")"

  if (( binary_mtime < src_mtime )); then
    return 0
  fi
  return 1
}

export_binary() {
  check_godot_available
  mkdir -p "$(dirname "$BINARY_PATH")"
  echo "Exportando preset '$EXPORT_PRESET_NAME' -> $BINARY_PATH"
  echo "Godot: $GODOT_BIN"
  echo "Modo export: $EXPORT_MODE"
  echo "Log build: $BUILD_LOG"

  local export_flag="--export-debug"
  if [[ "$EXPORT_MODE" == "release" ]]; then
    export_flag="--export-release"
  fi

  if ! "$GODOT_BIN" --headless --path "$ROOT_DIR" "$export_flag" "$EXPORT_PRESET_NAME" "$BINARY_PATH" 2>&1 | tee "$BUILD_LOG"; then
    die "La exportacion fallo. Log completo: $BUILD_LOG"
  fi
  require_file "$BINARY_PATH"
  chmod +x "$BINARY_PATH"
  echo "Binario generado: $(stat -c '%y %n' "$BINARY_PATH")"
}

ensure_binary_is_fresh() {
  if export_needs_build; then
    export_binary
  else
    echo "Binario actualizado, no recompilo."
  fi
}

main() {
  BINARY_PATH="$(resolve_export_path)"
  ensure_binary_is_fresh
  echo "Lanzando: $BINARY_PATH $*"
  cd "$ROOT_DIR"
  exec "$BINARY_PATH" "$@"
}

main "$@"
