#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK_PATH="${ROOT_DIR}/VR_ObjectGallery.apk"
PACKAGE_NAME="eu.cosmobots.vr_objectgallery"
ADB_CMD=(env ADB_LIBUSB=1 adb)

die() {
  echo "ERROR: $*" >&2
  exit 1
}

check_adb_available() {
  command -v adb >/dev/null 2>&1 || die "No encuentro 'adb' en PATH. Instala Android Platform Tools y asegurate de que 'adb' se puede ejecutar desde la terminal."
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || die "No existe: $path"
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

check_apk_is_fresh() {
  require_file "$APK_PATH"

  local newest_source
  newest_source="$(latest_source_file)"
  [[ -n "$newest_source" ]] || die "No he encontrado ficheros fuente a comparar"

  local apk_mtime src_mtime
  apk_mtime="$(stat -c '%Y' "$APK_PATH")"
  src_mtime="$(stat -c '%Y' "$newest_source")"

  echo "APK:    $(stat -c '%y %n' "$APK_PATH")"
  echo "Fuente: $(stat -c '%y %n' "$newest_source")"

  if (( apk_mtime < src_mtime )); then
    die "El APK es mas antiguo que el ultimo cambio fuente. Reexporta antes de instalar."
  fi
}

check_adb_device() {
  local devices
  devices="$("${ADB_CMD[@]}" devices | awk 'NR>1 && $2=="device" {print $1}')"
  [[ -n "$devices" ]] || die "ADB no ve ningun dispositivo en estado 'device'"
  echo "Dispositivo ADB: $(echo "$devices" | head -n1)"
}

uninstall_app() {
  if "${ADB_CMD[@]}" shell pm list packages | grep -q "$PACKAGE_NAME"; then
    "${ADB_CMD[@]}" uninstall "$PACKAGE_NAME"
  else
    echo "Paquete no instalado, continuo"
  fi
}

install_app() {
  "${ADB_CMD[@]}" install "$APK_PATH"
}

launch_app() {
  "${ADB_CMD[@]}" shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1
}

main() {
  check_adb_available
  check_apk_is_fresh
  check_adb_device
  uninstall_app
  install_app
  launch_app
}

main "$@"
