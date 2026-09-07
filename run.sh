#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MINIMUM_MACOS_MAJOR=13

configuration="release"
open_app=true
clean_build=false

print_usage() {
    cat <<'EOF'
Usage: ./run.sh [options]

Build and launch the Butterfly menu bar app.

Options:
  --debug      Build with debug settings.
  --release    Build with release settings (default).
  --clean      Recreate Swift build artifacts before building.
  --no-open    Build the app without launching it.
  -h, --help   Show this help message.
EOF
}

fail() {
    printf 'Butterfly setup error: %s\n' "$1" >&2
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
        --no-open)
            open_app=false
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            fail "Unknown option: $argument"
            ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || fail "Butterfly requires macOS."
[[ "$(uname -m)" == "arm64" ]] || fail "Butterfly currently requires an Apple Silicon Mac."

macos_version="$(sw_vers -productVersion)"
macos_major="${macos_version%%.*}"
(( macos_major >= MINIMUM_MACOS_MAJOR )) || fail "macOS ${MINIMUM_MACOS_MAJOR} or later is required; found ${macos_version}."

if ! xcode-select -p >/dev/null 2>&1; then
    printf 'Xcode Command Line Tools are required. Opening the Apple installer...\n'
    xcode-select --install >/dev/null 2>&1 || true
    printf 'Complete the installation, then press Return to continue.\n'
    read -r
    xcode-select -p >/dev/null 2>&1 || fail "Xcode Command Line Tools are not installed yet."
fi

command -v swift >/dev/null 2>&1 || fail "Swift is unavailable after installing Xcode Command Line Tools."

if ! command -v brew >/dev/null 2>&1; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}"
    else
        printf 'Homebrew is required to install whisper.cpp.\n'
        printf 'Install Homebrew now using its official installer? [y/N] '
        read -r install_homebrew
        case "$install_homebrew" in
            y|Y|yes|YES)
                command -v curl >/dev/null 2>&1 || fail "curl is required to download the Homebrew installer."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                [[ -x /opt/homebrew/bin/brew ]] || fail "Homebrew installation did not create /opt/homebrew/bin/brew."
                export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}"
                ;;
            *)
                fail "Homebrew installation was declined. Install it from https://brew.sh and run ./run.sh again."
                ;;
        esac
    fi
fi

if ! brew list --versions whisper-cpp >/dev/null 2>&1; then
    printf 'Installing the whisper.cpp native runtime with Homebrew...\n'
    brew install whisper-cpp
fi

build_arguments=("--${configuration}")
if [[ "$clean_build" == true ]]; then
    build_arguments+=("--clean")
fi

"${SCRIPT_DIR}/Scripts/build-app.sh" "${build_arguments[@]}"

readonly APP_BUNDLE="${SCRIPT_DIR}/.build/app/Butterfly.app"
if [[ "$open_app" == true ]]; then
    printf 'Launching %s\n' "$APP_BUNDLE"
    open "$APP_BUNDLE"
else
    printf 'App created at %s\n' "$APP_BUNDLE"
fi
