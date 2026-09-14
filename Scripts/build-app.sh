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
whisper_framework="${binary_directory}/whisper.framework"

if [[ ! -d "$whisper_framework" ]]; then
    whisper_framework="$(find "${REPOSITORY_ROOT}/.build/artifacts" -path '*/whisper.xcframework/macos-arm64_x86_64/whisper.framework' -type d -print -quit 2>/dev/null || true)"
fi

[[ -x "$executable_path" ]] || fail "SwiftPM did not produce ${executable_path}."
[[ -d "$core_resource_bundle" ]] || fail "ButterflyCore resource bundle was not produced."
[[ -d "$opencc_dictionary" ]] || fail "The SwiftyOpenCC dictionary resources were not found."
[[ -n "$whisper_framework" && -d "$whisper_framework" ]] || fail "The whisper.cpp framework was not produced."

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

mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources" "${APP_BUNDLE}/Contents/Frameworks"
ditto "$executable_path" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod 755 "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
ditto "${REPOSITORY_ROOT}/Support/ButterflyApp-Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
ditto "$whisper_framework" "${APP_BUNDLE}/Contents/Frameworks/whisper.framework"

if ! otool -l "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" | grep -Fq '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
fi

# App builds load these from Bundle.main. CLI builds continue to use Bundle.module.
ditto "$core_resource_bundle" "${APP_BUNDLE}/Contents/Resources"

# SwiftyOpenCC loads its dictionaries from Bundle.main/Resources/Dictionary.
ditto "$opencc_dictionary" "${APP_BUNDLE}/Contents/Resources/Dictionary"
ditto "${REPOSITORY_ROOT}/THIRD_PARTY_NOTICES.md" "${APP_BUNDLE}/Contents/Resources/THIRD_PARTY_NOTICES.md"

for icon_name in menu_bar_icon.png menu_bar_icon@2x.png; do
    icon_source="${REPOSITORY_ROOT}/docs/assets/${icon_name}"
    if [[ -f "$icon_source" ]]; then
        ditto "$icon_source" "${APP_BUNDLE}/Contents/Resources/${icon_name}"
    fi
done

# The repository artwork is currently stored as a JPEG with a .png filename.
# Convert it while packaging so Finder receives a valid PNG app icon.
app_icon_source="${REPOSITORY_ROOT}/docs/assets/icon.png"
[[ -f "$app_icon_source" ]] || fail "The app icon was not found at ${app_icon_source}."
sips -s format png "$app_icon_source" --out "${APP_BUNDLE}/Contents/Resources/icon.png" >/dev/null

# Use the same certificate across builds to preserve the app's signing identity.
# Ad-hoc signatures identify one build only and may invalidate existing TCC grants.
signing_identity="${BUTTERFLY_CODESIGN_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    printf 'Using ad-hoc signing; changed builds may require Accessibility permission again.\n'
fi
codesign --force --sign "$signing_identity" "${APP_BUNDLE}/Contents/Frameworks/whisper.framework"
codesign --force --sign "$signing_identity" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

printf 'Built %s\n' "$APP_BUNDLE"
