<p align="center">
  <img src="docs/assets/banner.jpg" alt="Butterfly Banner" width="100%" />
</p>

# 🦋 Butterfly

Butterfly is a native macOS voice dictation tool for Apple Silicon. It records speech with downloaded Whisper models or Apple Speech, types live transcription into the focused app, and can optionally polish a completed transcript with an on-device model or a configured OpenAI-compatible endpoint.

## Requirements

- Apple Silicon Mac (`arm64`)
- macOS 13 or later
- Xcode Command Line Tools and Swift 5.9 or later
- Homebrew with `whisper-cpp` for local Whisper models
- macOS 26 or later with Apple Intelligence for Apple Foundation Models

When no downloaded Whisper model is available, Butterfly can use **Apple Speech Native**. That model requires macOS Speech Recognition permission.

## Build and launch

Run this from the repository root:

```bash
./run.sh
```

The first run installs missing developer dependencies, builds a release app, and opens it. Later runs open the existing app without rebuilding or signing it. The packaged app is written to `.build/app/Butterfly.app`.

| Command | Behavior |
| --- | --- |
| `./run.sh` | Open the existing app, or build it first when it does not exist. |
| `./run.sh --build` | Rebuild a release app and open it. |
| `./run.sh --debug` | Rebuild a debug app and open it. |
| `./run.sh --release` | Rebuild a release app and open it. |
| `./run.sh --clean` | Clean SwiftPM artifacts, rebuild, and open the app. |
| `./run.sh --no-open` | Build and sign without opening the app. |
| `./run.sh --no-build` | Open an existing app without rebuilding or signing it. |

Use `swift build` for a package build and `swift run ButterflyApp` for development. `./run.sh` is the normal app workflow because it creates the complete bundle and signs it.

## Permissions and signing

| Permission | Used for |
| --- | --- |
| **Accessibility** | Global hotkeys, the event tap, Enter/Esc interception, and text insertion. |
| **Microphone** | Recording in either mode. |
| **Speech Recognition** | Apple Speech Native only. Downloaded Whisper models do not use it. |

Enable Accessibility for the exact `.build/app/Butterfly.app` in **System Settings → Privacy & Security → Accessibility**. The menu shows `Global Hotkeys: Ready` when registration succeeds. If it shows `Hotkeys unavailable`, re-enable the current app bundle.

Local builds use an ad-hoc signature by default. Rebuilding with `--build`, `--debug`, or `--clean` can give the app a new identity in macOS TCC and require Accessibility to be enabled again. Running `./run.sh` without a build reuses the existing signed bundle. For the certificate and TCC details, see [macOS signing and Accessibility](docs/MACOS_SIGNING_AND_ACCESSIBILITY.md).

## Controls and modes

| Shortcut | Mode | Behavior |
| --- | --- | --- |
| `Option + Space` | **Live Voice Dictation** | Streams transcription into the focused input. The floating HUD shows the microphone waveform. |
| `Option + Shift + Space` | **Record & Smart Polish** | Records without insertion, polishes once, then pastes the final result. |
| `Enter` or `Esc` | Stop | Stops recording. The first Enter is swallowed to prevent accidental submission; the next Enter passes through. |

The same actions are available from the menu bar when global hotkeys are unavailable. Enter/Esc remains swallowed while Smart Polish is processing.

## Speech models

The **Speech Model** menu manages local ASR. It includes Whisper Large-v3-Turbo, Whisper Small, Whisper Base, Whisper Tiny, and Apple Speech Native. SenseVoice Small remains in the catalog but is disabled because the bundled runtime does not currently support it.

Whisper files are cached in `~/.cache/butterfly/models`. Butterfly chooses the highest-ranked downloaded runtime-supported model unless you select another downloaded model. The ASR choice is stored separately from Smart Polish settings.

The menu and CLI can download, delete, and inspect cached models:

```bash
swift run butterfly-cli models
swift run butterfly-cli download whisper-large-v3-turbo
swift run butterfly-cli delete whisper-small
swift run butterfly-cli clean
swift run butterfly-cli info
```

## Smart Polish configuration

Smart Polish reads:

```text
~/.config/butterfly/butterfly.json
```

Copy [`butterfly.sample.json`](butterfly.sample.json) as a starting point:

```bash
mkdir -p ~/.config/butterfly
cp butterfly.sample.json ~/.config/butterfly/butterfly.json
```

Set `polish.defaultModel` to a built-in model or `<provider-id>/<model-id>`:

```json
{
  "polish": {
    "defaultModel": "local/foundation",
    "fallback": "rules"
  },
  "provider": {
    "my-provider": {
      "name": "My AI Provider",
      "type": "openai-compatible",
      "options": {
        "baseURL": "$AI_ENDPOINT_BASE_URL",
        "apiKey": "$AI_API_KEY"
      },
      "models": {
        "example-model": {
          "name": "Example Model"
        }
      }
    }
  }
}
```

Built-in IDs are `local/foundation` (Apple Foundation Models on macOS 26+) and `local/rules` (deterministic local fallback). Endpoint providers must use `type: "openai-compatible"`; detailed options, API variants, limits, and environment placeholder syntax are documented in [POLISH_ENDPOINTS.md](docs/POLISH_ENDPOINTS.md).

Existing files using `polish.model` remain supported, but new files should use `polish.defaultModel`. The **Smart Polish Model** menu temporarily overrides the configured default for the current process; **Reload Polish Configuration** or a restart returns to the configured default.

## Smart Polish styles

Choose a style from **Smart Polish Style**. The choice persists between launches.

| Style | Behavior |
| --- | --- |
| **Faithful Proofread** | Correct punctuation and boundaries while preserving wording and detail. |
| **Concise Polish** | Remove fillers, stutters, and clearly redundant repetition. This is the default. |
| **Structured Notes** | Keep paragraph-first blocks and add headings or genuine parallel lists when useful. |
| **Summary** | Keep central ideas, decisions, caveats, and conclusions. |

If the primary model is unavailable, Butterfly uses the configured `rules` fallback and reports the reason. The fallback is deterministic and more conservative than an LLM. An optional Smart Polish prompt can be placed at `~/.config/butterfly/SMART_POLISH_PROMPT.md`.

## CLI

```bash
swift run butterfly-cli listen
swift run butterfly-cli test
swift run butterfly-cli test-polish --smart --style structured
swift run butterfly-cli test-convert "服务器内存不足"
```

The CLI uses the same Smart Polish configuration as the app. `swift run butterfly-cli test` runs the zero-dependency core regression suite; `swift test` runs XCTest targets.

## Important paths

- `~/.config/butterfly/butterfly.json` — Smart Polish providers and startup default.
- `~/.config/butterfly/dictionary.txt` — personal technical vocabulary.
- `~/.config/butterfly/SMART_POLISH_PROMPT.md` — optional Smart Polish prompt override.
- `~/.cache/butterfly/models` — downloaded speech models.
- `.build/app/Butterfly.app` — packaged application.
- `Sources/ButterflyCore/Resources/dictionary.txt` — bundled speech vocabulary.

Keep personal configuration and credentials outside version control. The sample file contains only generic names and placeholders.

## Troubleshooting

### `Hotkeys unavailable`

Enable Accessibility for the exact app bundle currently running. A rebuild can change the ad-hoc signing identity, so remove the old entry and add `.build/app/Butterfly.app` again if necessary.

### `The language model is unavailable`

Check the selected Smart Polish model, validate `butterfly.json`, and ensure referenced environment variables are available to the launched app. For `local/foundation`, confirm macOS 26+ and Apple Intelligence. Butterfly falls back to rules when the primary backend is unavailable.

### Recording does not start

Grant Microphone permission. Also grant Speech Recognition when Apple Speech Native is selected. For Whisper, download a supported model from the **Speech Model** menu or with `butterfly-cli download`.

More design and validation details are in [ARCHITECTURE.md](docs/ARCHITECTURE.md), [POLISH_ENDPOINTS.md](docs/POLISH_ENDPOINTS.md), [TEST_PLAN.md](docs/TEST_PLAN.md), and [MACOS_SIGNING_AND_ACCESSIBILITY.md](docs/MACOS_SIGNING_AND_ACCESSIBILITY.md).
