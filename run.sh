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

Stop any running Butterfly app, then build and launch it.

Options:
  --debug      Build with debug settings.
  --release    Build with release settings (default).
  --clean      Recreate Swift build artifacts before building.
  --no-open    Build without stopping or launching the app.
  -h, --help   Show this help message.
EOF
}

fail() {
    printf 'Butterfly setup error: %s\n' "$1" >&2
    exit 1
}

running_app_pids() {
    # Match exact executable names for bundled and swift-run app launches.
    pgrep -u "$(id -u)" -x 'Butterfly|ButterflyApp' || [[ "$?" -eq 1 ]]
}

stop_running_app() {
    local process_ids process_id attempt
    process_ids="$(running_app_pids)" || fail "Cannot check for running Butterfly processes."
    [[ -n "$process_ids" ]] || return 0

    printf 'Stopping running Butterfly app...\n'
    while IFS= read -r process_id; do
        kill -TERM "$process_id" 2>/dev/null || true
    done <<< "$process_ids"

    for ((attempt = 0; attempt < 50; attempt++)); do
        process_ids="$(running_app_pids)" || fail "Cannot check whether Butterfly stopped."
        [[ -n "$process_ids" ]] || return 0
        sleep 0.1
    done

    printf 'Butterfly did not stop within 5 seconds; forcing it to quit...\n'
    while IFS= read -r process_id; do
        kill -KILL "$process_id" 2>/dev/null || true
    done <<< "$process_ids"

    for ((attempt = 0; attempt < 20; attempt++)); do
        process_ids="$(running_app_pids)" || fail "Cannot verify Butterfly shutdown."
        [[ -n "$process_ids" ]] || return 0
        sleep 0.1
    done
    fail "Butterfly is still running; close it before launching another instance."
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

if [[ "$open_app" == true ]]; then
    stop_running_app
fi

"${SCRIPT_DIR}/Scripts/build-app.sh" "${build_arguments[@]}"

readonly APP_BUNDLE="${SCRIPT_DIR}/.build/app/Butterfly.app"
if [[ "$open_app" == true ]]; then
    printf 'Launching %s\n' "$APP_BUNDLE"
    open "$APP_BUNDLE"
else
    printf 'App created at %s\n' "$APP_BUNDLE"
fi
