#!/usr/bin/env bash
#
# Check that a downloaded Cubism SDK is where Package.swift expects it.
#
# Package.swift decides whether to build CubismBridge by testing for one header.
# If the SDK is present but laid out differently, the build either skips the
# bridge silently or fails deep inside C++ header resolution, and neither says
# "the SDK is in the wrong place". This does.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="$ROOT/Vendor/CubismSDK"

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
missing=0

check() {  # check <description> <path>
    if [ -e "$2" ]; then
        printf '  %spass%s  %s\n' "$GREEN" "$RESET" "$1"
    else
        printf '  %sMISS%s  %s\n' "$RED" "$RESET" "$1"
        printf '        %s%s%s\n' "$DIM" "${2#$ROOT/}" "$RESET"
        missing=$((missing + 1))
    fi
}

echo
echo "Cubism SDK"

if [ ! -d "$SDK" ]; then
    printf '  %sMISS%s  no Vendor/CubismSDK at all\n' "$RED" "$RESET"
    echo
    echo "  Download Cubism SDK for Native 5.3+ from live2d.com and unpack it to:"
    echo "    ${SDK#$ROOT/}"
    echo "  See Vendor/README.md. The app builds without it — you get the"
    echo "  procedural placeholder instead of the rig."
    exit 1
fi

# The one Package.swift keys on. If only this is wrong, the bridge is skipped
# silently, which is the most confusing possible outcome.
check "Core header (Package.swift detects on this)" "$SDK/Core/include/Live2DCubismCore.h"
check "Core static library"                         "$SDK/Core/lib/macos/libLive2DCubismCore.a"
check "Framework sources"                           "$SDK/Framework/src/CubismFramework.hpp"
check "Metal renderer"                              "$SDK/Framework/src/Rendering/Metal"
check "physics"                                     "$SDK/Framework/src/Physics"
check "model settings parser"                       "$SDK/Framework/src/CubismModelSettingJson.hpp"

echo
if [ "$missing" -gt 0 ]; then
    printf '%s%d item(s) missing%s\n' "$RED" "$missing" "$RESET"
    echo "The downloaded folder is usually CubismSdkForNative-5.x.y — rename it"
    echo "to CubismSDK, or symlink it. See Vendor/README.md."
    exit 1
fi

printf '%sSDK looks right%s\n' "$GREEN" "$RESET"
printf '%sswift build will now compile CubismBridge; Live2DRenderer stops being%s\n' "$DIM" "$RESET"
printf '%scompiled out. The rig needs a 5.3+ Core — it is moc3 version 6.%s\n' "$DIM" "$RESET"
