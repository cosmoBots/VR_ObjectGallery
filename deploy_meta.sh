#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_PRESET_NAME="Meta Quest 3"
EXPORT_PRESETS_PATH="${ROOT_DIR}/export_presets.cfg"
PACKAGE_NAME="eu.cosmobots.vr_objectgallery"
ADB_CMD=(env ADB_LIBUSB=1 adb)
ANDROID_ENV_PATH="${ROOT_DIR}/android.env"
TARGETS_ENV_PATH="${ROOT_DIR}/.targets"
GODOT_BIN="${GODOT_BIN:-$HOME/soft/Godot_v4.6.2-stable_linux.x86_64}"
BUILD_LOG="${BUILD_LOG:-/tmp/vr_objectgallery_meta_build.log}"
ADB_DEVICE_ARGS=()

die() {
  echo "ERROR: $*" >&2
  exit 1
}

check_adb_available() {
  command -v adb >/dev/null 2>&1 || die "No encuentro 'adb' en PATH. Instala Android Platform Tools y asegurate de que 'adb' se puede ejecutar desde la terminal."
}

check_godot_available() {
  [[ -x "$GODOT_BIN" ]] || die "No encuentro Godot ejecutable en GODOT_BIN=$GODOT_BIN"
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || die "No existe: $path"
}

load_android_env() {
  if [[ -f "$ANDROID_ENV_PATH" ]]; then
    # shellcheck source=/dev/null
    source "$ANDROID_ENV_PATH"
  fi
}

load_targets() {
  if [[ ! -f "$TARGETS_ENV_PATH" ]]; then
    die "No existe $TARGETS_ENV_PATH. Copia .targets.example a .targets y ajusta META_SERIAL."
  fi
  # shellcheck source=/dev/null
  source "$TARGETS_ENV_PATH"
  [[ -n "${META_SERIAL:-}" ]] || die "META_SERIAL esta vacio en .targets"
  ADB_DEVICE_ARGS=(-s "$META_SERIAL")
}

adb_target() {
  "${ADB_CMD[@]}" "${ADB_DEVICE_ARGS[@]}" "$@"
}

preset_export_path() {
  local preset_name="$1"
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
        if [[ "$current_name" == "$preset_name" && "$current_platform" == "Android" ]]; then
          printf '%s\n' "$current_export_path"
          return 0
        fi
        ;;
    esac
  done < "$EXPORT_PRESETS_PATH"

  return 1
}

resolve_default_apk_path() {
  local export_path
  export_path="$(preset_export_path "$EXPORT_PRESET_NAME")" || die "No encuentro el export_path del preset Android '$EXPORT_PRESET_NAME'"
  [[ "$export_path" == *.apk ]] || die "El export_path del preset '$EXPORT_PRESET_NAME' no es un APK: $export_path"

  case "$export_path" in
    /*) printf '%s\n' "$export_path" ;;
    ./*) printf '%s/%s\n' "$ROOT_DIR" "${export_path#./}" ;;
    *) printf '%s/%s\n' "$ROOT_DIR" "$export_path" ;;
  esac
}

resolve_apk_path() {
  local apk_name="$1"
  if [[ -z "$apk_name" ]]; then
    resolve_default_apk_path
    return
  fi

  [[ "$apk_name" == *.apk ]] || apk_name="${apk_name}.apk"
  case "$apk_name" in
    /*) printf '%s\n' "$apk_name" ;;
    *) printf '%s/%s\n' "$ROOT_DIR" "$apk_name" ;;
  esac
}

latest_source_file() {
  find "$ROOT_DIR" \
    \( -path "$ROOT_DIR/.git" -o -path "$ROOT_DIR/.godot" -o -path "$ROOT_DIR/android/build" -o -path "$ROOT_DIR/addons" \) -prune -o \
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
    -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-
}

apk_needs_build() {
  local newest_source
  newest_source="$(latest_source_file)"
  [[ -n "$newest_source" ]] || die "No he encontrado ficheros fuente a comparar"

  if [[ ! -f "$APK_PATH" ]]; then
    echo "APK:    no existe $APK_PATH"
    echo "Fuente: $(stat -c '%y %n' "$newest_source")"
    return 0
  fi

  local apk_mtime src_mtime
  apk_mtime="$(stat -c '%Y' "$APK_PATH")"
  src_mtime="$(stat -c '%Y' "$newest_source")"

  echo "APK:    $(stat -c '%y %n' "$APK_PATH")"
  echo "Fuente: $(stat -c '%y %n' "$newest_source")"

  if (( apk_mtime < src_mtime )); then
    return 0
  fi
  return 1
}

export_apk() {
  check_godot_available
  echo "Exportando preset '$EXPORT_PRESET_NAME' -> $APK_PATH"
  echo "Godot: $GODOT_BIN"
  echo "Log build: $BUILD_LOG"
  if ! "$GODOT_BIN" --headless --path "$ROOT_DIR" --export-debug "$EXPORT_PRESET_NAME" "$APK_PATH" 2>&1 | tee "$BUILD_LOG"; then
    die "La exportacion fallo. Log completo: $BUILD_LOG"
  fi
  require_file "$APK_PATH"
  echo "APK generado: $(stat -c '%y %n' "$APK_PATH")"
}

ensure_apk_is_fresh() {
  if apk_needs_build; then
    export_apk
  else
    echo "APK actualizado, no recompilo."
  fi
}

check_adb_device() {
  local state
  state="$("${ADB_CMD[@]}" devices | awk -v serial="${META_SERIAL:-}" '$1==serial {print $2}')"
  if [[ "$state" != "device" ]]; then
    "${ADB_CMD[@]}" devices -l
    die "ADB no ve META_SERIAL=${META_SERIAL:-} en estado 'device'"
  fi
  echo "Dispositivo ADB: $META_SERIAL"
}

uninstall_app() {
  if adb_target shell pm list packages | grep -q "$PACKAGE_NAME"; then
    adb_target uninstall "$PACKAGE_NAME"
  else
    echo "Paquete no instalado, continuo"
  fi
}

install_app() {
  adb_target install "$APK_PATH"
}

launch_app() {
  adb_target shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1
}

main() {
  local explicit_apk="${1:-}"
  APK_PATH="$(resolve_apk_path "$explicit_apk")"

  load_android_env
  load_targets
  check_adb_available
  if [[ -z "$explicit_apk" ]]; then
    ensure_apk_is_fresh
  else
    require_file "$APK_PATH"
  fi
  check_adb_device
  uninstall_app
  install_app
  launch_app
}

main "$@"
