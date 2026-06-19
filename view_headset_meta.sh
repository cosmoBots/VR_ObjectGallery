#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${ROOT_DIR}/view_headset.sh" --reset-adb 2G0YC5ZG4W02GZ "$@"
