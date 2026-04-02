#!/bin/sh
printf '\033c\033]0;%s\a' VR Object Gallery
base_path="$(dirname "$(realpath "$0")")"
"$base_path/VR_ObjectGallery.x86_64" "$@"
