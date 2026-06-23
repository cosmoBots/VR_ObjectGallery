#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_PRESETS_PATH="${ROOT_DIR}/export_presets.cfg"
ANDROID_ENV_PATH="${ROOT_DIR}/android.env"
TARGETS_ENV_PATH="${ROOT_DIR}/.targets"
PACKAGE_NAME="eu.cosmobots.vr_objectgallery"
GODOT_BIN="${GODOT_BIN:-$HOME/soft/Godot_v4.6.2-stable_linux.x86_64}"
BUILD_LOG="${BUILD_LOG:-/tmp/vr_objectgallery_build.log}"
ADB_CMD=(env ADB_LIBUSB=1 adb)
ADB_DEVICE_ARGS=()

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Uso:
  ./clean_build_deploy.sh [vive|meta|pico] [--build-only] [--release]

Por defecto:
  ./clean_build_deploy.sh

Hace una exportacion debug limpia para HTC Vive XR Elite, instala el APK por
ADB y lanza la app. Debug evita depender del keystore de release durante las
pruebas de controles. Usa --release solo cuando el keystore este configurado.

Variables utiles:
  GODOT_BIN=/ruta/a/Godot ./clean_build_deploy.sh vive
  BUILD_LOG=/tmp/build.log ./clean_build_deploy.sh vive
EOF
}

load_android_env() {
  if [[ -f "$ANDROID_ENV_PATH" ]]; then
    # shellcheck source=/dev/null
    source "$ANDROID_ENV_PATH"
  fi
}

load_targets() {
  if [[ ! -f "$TARGETS_ENV_PATH" ]]; then
    die "No existe $TARGETS_ENV_PATH. Copia .targets.example a .targets y ajusta los seriales."
  fi
  # shellcheck source=/dev/null
  source "$TARGETS_ENV_PATH"
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || die "No existe: $path"
}

check_tools() {
  require_file "$GODOT_BIN"
  command -v adb >/dev/null 2>&1 || die "No encuentro 'adb' en PATH"
}

preset_for_target() {
  local target="$1"
  case "$target" in
    vive) printf '%s\n' "HTC Vive XR Elite" ;;
    meta) printf '%s\n' "Meta Quest 3" ;;
    pico) printf '%s\n' "PicoVR" ;;
    *) die "Target desconocido: $target" ;;
  esac
}

serial_for_target() {
  local target="$1"
  case "$target" in
    vive) printf '%s\n' "${VIVE_SERIAL:-}" ;;
    meta) printf '%s\n' "${META_SERIAL:-}" ;;
    pico) printf '%s\n' "${PICO_SERIAL:-}" ;;
    *) die "Target desconocido: $target" ;;
  esac
}

configure_adb_target() {
  local target="$1"
  local serial
  serial="$(serial_for_target "$target")"
  [[ -n "$serial" ]] || die "El serial para '$target' esta vacio en .targets"
  ADB_DEVICE_ARGS=(-s "$serial")
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

resolve_apk_path() {
  local preset_name="$1"
  local export_path

  export_path="$(preset_export_path "$preset_name")" || die "No encuentro el export_path del preset Android '$preset_name'"
  [[ "$export_path" == *.apk ]] || die "El export_path del preset '$preset_name' no es un APK: $export_path"

  case "$export_path" in
    /*) printf '%s\n' "$export_path" ;;
    ./*) printf '%s/%s\n' "$ROOT_DIR" "${export_path#./}" ;;
    *) printf '%s/%s\n' "$ROOT_DIR" "$export_path" ;;
  esac
}

check_adb_device() {
  local serial state
  serial="${ADB_DEVICE_ARGS[1]:-}"
  state="$("${ADB_CMD[@]}" devices | awk -v wanted="$serial" '$1==wanted {print $2}')"
  if [[ "$state" != "device" ]]; then
    "${ADB_CMD[@]}" devices -l
    die "ADB no ve el target '$serial' en estado 'device'"
  fi
  echo "Dispositivo ADB: $serial"
}

force_stop_app() {
  adb_target shell am force-stop "$PACKAGE_NAME" >/dev/null 2>&1 || true
}

prepare_adb_server() {
  export ADB_LIBUSB="${ADB_LIBUSB:-1}"
  if ! adb start-server >/dev/null 2>&1; then
    echo "ADB no arranco a la primera; reinicio daemon..."
    adb kill-server >/dev/null 2>&1 || true
    adb start-server >/dev/null 2>&1 || die "No puedo arrancar el daemon adb"
  fi
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
  local target="vive"
  local build_only=false
  local export_mode="--export-debug"

  while (($#)); do
    case "$1" in
      vive|meta|pico) target="$1" ;;
      --build-only) build_only=true ;;
      --release) export_mode="--export-release" ;;
      -h|--help)
        usage
        exit 0
        ;;
      *) die "Argumento desconocido: $1" ;;
    esac
    shift
  done

  load_android_env
  load_targets
  check_tools
  configure_adb_target "$target"

  local preset_name
  preset_name="$(preset_for_target "$target")"
  APK_PATH="$(resolve_apk_path "$preset_name")"

  echo "Target: $target"
  echo "Preset: $preset_name"
  echo "APK: $APK_PATH"
  echo "Godot: $GODOT_BIN"
  echo "Modo export: $export_mode"
  echo "Log build: $BUILD_LOG"

  rm -f "$APK_PATH"
  prepare_adb_server
  if ! "$GODOT_BIN" --headless --path "$ROOT_DIR" "$export_mode" "$preset_name" "$APK_PATH" 2>&1 | tee "$BUILD_LOG"; then
    die "La exportacion fallo. Log completo: $BUILD_LOG"
  fi
  require_file "$APK_PATH"
  echo "APK generado: $(stat -c '%y %n' "$APK_PATH")"

  if [[ "$build_only" == true ]]; then
    exit 0
  fi

  check_adb_device
  force_stop_app
  uninstall_app
  install_app
  force_stop_app
  launch_app
}

main "$@"
