#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_ENV_PATH="${ROOT_DIR}/android.env"
SCRCPY_BIN="${SCRCPY_BIN:-$HOME/soft/bin/scrcpy}"
ADB_CMD=(env ADB_LIBUSB=1 adb)

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Uso:
  ./view_headset.sh [opciones] [serial] [-- argumentos extra de scrcpy]

Opciones:
  --fast       Baja latencia: menos resolucion/bitrate/FPS y sin audio.
  --left-eye   Recorta la mitad izquierda de la pantalla enviada por el visor.
  --right-eye  Recorta la mitad derecha de la pantalla enviada por el visor.
  --reset-adb  Reinicia el servidor ADB antes de lanzar scrcpy.

Ejemplos:
  ./view_headset.sh
  ./view_headset.sh --fast
  ./view_headset.sh --reset-adb --fast
  ./view_headset.sh --fast --left-eye
  ./view_headset.sh 1WMHH000000000
  ./view_headset.sh --fast 1WMHH000000000 -- --max-size 960 --video-bit-rate 1M

Variables:
  SCRCPY_BIN=/ruta/a/scrcpy ./view_headset.sh
EOF
}

load_android_env() {
  if [[ -f "$ANDROID_ENV_PATH" ]]; then
    # shellcheck source=/dev/null
    source "$ANDROID_ENV_PATH"
  fi
}

check_tools() {
  command -v adb >/dev/null 2>&1 || die "No encuentro 'adb' en PATH. Revisa android.env o instala Android Platform Tools."
  [[ -x "$SCRCPY_BIN" ]] || die "No encuentro scrcpy ejecutable en SCRCPY_BIN=$SCRCPY_BIN"
}

connected_devices() {
  "${ADB_CMD[@]}" devices | awk 'NR>1 && $2=="device" {print $1}'
}

reset_adb_server() {
  echo "Reiniciando servidor ADB..."
  "${ADB_CMD[@]}" kill-server >/dev/null 2>&1 || true
  "${ADB_CMD[@]}" start-server
}

device_screen_size() {
  local serial="$1"
  "${ADB_CMD[@]}" -s "$serial" shell wm size | awk '
    match($0, /[0-9]+x[0-9]+/) {
      print substr($0, RSTART, RLENGTH)
      exit
    }
  '
}

append_eye_crop_args() {
  local serial="$1"
  local eye="$2"
  local size width height crop_width crop_x

  size="$(device_screen_size "$serial")"
  [[ "$size" == *x* ]] || die "No pude leer el tamano de pantalla con 'adb shell wm size'"

  width="${size%x*}"
  height="${size#*x}"
  crop_width=$((width / 2))
  crop_x=0
  if [[ "$eye" == "right" ]]; then
    crop_x="$crop_width"
  fi

  scrcpy_args+=("--crop=${crop_width}:${height}:${crop_x}:0")
  echo "Crop ${eye}: ${crop_width}x${height}+${crop_x}+0 de pantalla ${width}x${height}"
}

has_no_control_arg() {
  local arg
  for arg in "${scrcpy_args[@]}"; do
    if [[ "$arg" == "--no-control" || "$arg" == "-n" ]]; then
      return 0
    fi
  done
  return 1
}

main() {
  load_android_env
  check_tools

  local serial=""
  local low_latency=false
  local eye_crop=""
  local reset_adb=false
  local -a scrcpy_args=()
  while (($# > 0)); do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --fast)
        low_latency=true
        shift
        ;;
      --left-eye)
        eye_crop="left"
        shift
        ;;
      --right-eye)
        eye_crop="right"
        shift
        ;;
      --reset-adb)
        reset_adb=true
        shift
        ;;
      --)
        shift
        scrcpy_args+=("$@")
        break
        ;;
      *)
        if [[ -z "$serial" ]]; then
          serial="$1"
        else
          scrcpy_args+=("$1")
        fi
        shift
        ;;
    esac
  done

  if [[ "$reset_adb" == true ]]; then
    reset_adb_server
  fi

  mapfile -t devices < <(connected_devices)
  if ((${#devices[@]} == 0)); then
    die "ADB no ve ninguna gafa/dispositivo en estado 'device'. Comprueba USB debugging y acepta el permiso en la gafa."
  fi

  if [[ -z "$serial" ]]; then
    if ((${#devices[@]} > 1)); then
      echo "Hay varios dispositivos ADB. Lanza el script con uno de estos seriales:"
      printf '  %s\n' "${devices[@]}"
      exit 1
    fi
    serial="${devices[0]}"
  fi

  if [[ "$low_latency" == true ]]; then
    scrcpy_args=(
      --no-audio
      --video-buffer=0
      --max-size=1024
      --max-fps=30
      --video-bit-rate=2M
      "${scrcpy_args[@]}"
    )
  fi

  if [[ -n "$eye_crop" ]]; then
    append_eye_crop_args "$serial" "$eye_crop"
  fi

  echo "Dispositivo ADB: $serial"
  echo "scrcpy: $SCRCPY_BIN"
  if has_no_control_arg; then
    exec "$SCRCPY_BIN" -s "$serial" "${scrcpy_args[@]}"
  fi
  exec "$SCRCPY_BIN" -s "$serial" --stay-awake "${scrcpy_args[@]}"
}

main "$@"
