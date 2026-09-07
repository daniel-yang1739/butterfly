#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly APP_NAME="Butterfly"
readonly PRODUCT_NAME="ButterflyApp"
readonly APP_OUTPUT_DIRECTORY="${REPOSITORY_ROOT}/.build/app"
readonly APP_BUNDLE="${APP_OUTPUT_DIRECTORY}/${APP_NAME}.app"

configuration="release"
clean_build=false

fail() {
    printf 'Butterfly build error: %s\n' "$1" >&2
    exit 1
}

for argument in "$@"; do
    case "$argument" in
        --debug)
            configuration="debug"
            ;;
        --release)
            configuration="release"
            ;;
        --clean)
            clean_build=true
            ;;
        *)
            fail "Unknown option: $argument"
            ;;
    esac
done

cd "$REPOSITORY_ROOT"

if [[ "$clean_build" == true ]]; then
    swift package clean
fi

printf 'Building %s (%s)...\n' "$PRODUCT_NAME" "$configuration"
swift build --configuration "$configuration" --product "$PRODUCT_NAME"

binary_directory="$(swift build --configuration "$configuration" --show-bin-path)"
executable_path="${binary_directory}/${PRODUCT_NAME}"
core_resource_bundle="${binary_directory}/Butterfly_ButterflyCore.bundle"
opencc_dictionary="${REPOSITORY_ROOT}/.build/checkouts/SwiftyOpenCC/OpenCCDictionary.bundle/Contents/Resources/Dictionary"

[[ -x "$executable_path" ]] || fail "SwiftPM did not produce ${executable_path}."
[[ -d "$core_resource_bundle" ]] || fail "ButterflyCore resource bundle was not produced."
[[ -d "$opencc_dictionary" ]] || fail "The SwiftyOpenCC dictionary resources were not found."

if [[ -e "$APP_BUNDLE" ]]; then
    case "$APP_BUNDLE" in
        "${REPOSITORY_ROOT}/.build/app/Butterfly.app")
            rm -rf "$APP_BUNDLE"
            ;;
        *)
            fail "Refusing to replace an unexpected app path: ${APP_BUNDLE}"
            ;;
    esac
fi

mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
ditto "$executable_path" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod 755 "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
ditto "${REPOSITORY_ROOT}/Support/ButterflyApp-Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# App builds load these from Bundle.main. CLI builds continue to use Bundle.module.
ditto "$core_resource_bundle" "${APP_BUNDLE}/Contents/Resources"

# SwiftyOpenCC loads its dictionaries from Bundle.main/Resources/Dictionary.
ditto "$opencc_dictionary" "${APP_BUNDLE}/Contents/Resources/Dictionary"

for icon_name in menu_bar_icon.png menu_bar_icon@2x.png; do
    icon_source="${REPOSITORY_ROOT}/docs/assets/${icon_name}"
    if [[ -f "$icon_source" ]]; then
        ditto "$icon_source" "${APP_BUNDLE}/Contents/Resources/${icon_name}"
    fi
done

codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

printf 'Built %s\n' "$APP_BUNDLE"
