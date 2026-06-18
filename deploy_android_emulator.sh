#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESET="${GODOT_ANDROID_EMULATOR_PRESET:-Android Emulator}"
APK_PATH="${ROOT_DIR}/VR_NRT_AndroidEmulator.apk"
PACKAGE_NAME="eu.cosmobots.vr_objectgallery.emulator"
EMULATOR_GPU_MODE="${ANDROID_EMULATOR_GPU_MODE:-auto}"

find_bin() {
	local env_name="$1"
	shift
	local configured="${!env_name:-}"
	if [[ -n "${configured}" ]]; then
		printf '%s\n' "${configured}"
		return 0
	fi
	local candidate
	for candidate in "$@"; do
		if command -v "${candidate}" >/dev/null 2>&1; then
			command -v "${candidate}"
			return 0
		fi
	done
	return 1
}

GODOT_BIN="$(find_bin GODOT_BIN /home/txinto/soft/Godot_v4.6.2-stable_linux.x86_64 godot4.6 godot4 godot)" || {
	echo "No encuentro Godot. Define GODOT_BIN=/ruta/a/godot."
	exit 1
}

ADB_BIN="$(find_bin ADB_BIN /home/txinto/Android/Sdk/platform-tools/adb adb)" || {
	echo "No encuentro adb. Define ADB_BIN=/ruta/a/adb."
	exit 1
}

EMULATOR_BIN="$(find_bin EMULATOR_BIN /home/txinto/Android/Sdk/emulator/emulator emulator || true)"

running_device="$("${ADB_BIN}" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
if [[ -z "${running_device}" && -n "${EMULATOR_BIN}" ]]; then
	avd_name="${ANDROID_AVD_NAME:-}"
	if [[ -z "${avd_name}" ]]; then
		avd_name="$("${EMULATOR_BIN}" -list-avds | head -n 1)"
	fi
	if [[ -n "${avd_name}" ]]; then
		echo "Arrancando emulador Android: ${avd_name} (-gpu ${EMULATOR_GPU_MODE})"
		nohup "${EMULATOR_BIN}" -avd "${avd_name}" -gpu "${EMULATOR_GPU_MODE}" >/tmp/vr_nrt_android_emulator.log 2>&1 &
	fi
fi

if [[ -z "${running_device}" ]]; then
	running_device="$("${ADB_BIN}" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
	if [[ -z "${running_device}" && -n "${EMULATOR_BIN}" && -z "$("${EMULATOR_BIN}" -list-avds | head -n 1)" ]]; then
		echo "No hay ningun AVD creado. Crea uno en Android Studio > Device Manager."
		exit 1
	fi
fi

echo "Esperando dispositivo Android..."
"${ADB_BIN}" wait-for-device
echo "Esperando arranque completo de Android..."
until [[ "$("${ADB_BIN}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
	sleep 1
done

echo "Exportando ${PRESET} -> ${APK_PATH}"
"${GODOT_BIN}" --headless --path "${ROOT_DIR}" --export-debug "${PRESET}" "${APK_PATH}"

echo "Instalando APK en Android..."
"${ADB_BIN}" install -r "${APK_PATH}"
sleep 2

echo "Lanzando ${PACKAGE_NAME}..."
echo "Activity launcher resuelta:"
"${ADB_BIN}" shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "${PACKAGE_NAME}" || true
if ! "${ADB_BIN}" shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p "${PACKAGE_NAME}"; then
	if ! "${ADB_BIN}" shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -n "${PACKAGE_NAME}/com.godot.game.GodotAppLauncher"; then
		"${ADB_BIN}" shell am start -n "${PACKAGE_NAME}/com.godot.game.GodotApp"
	fi
fi

echo "Listo. Para ver logs MQTT: ${ADB_BIN} logcat | grep MQTT"
