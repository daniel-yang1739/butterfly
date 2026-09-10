<p align="center">
  <img src="docs/assets/banner.jpg" alt="Butterfly Banner" width="100%" />
</p>

# 🦋 Butterfly

Butterfly is a native macOS voice dictation tool for Apple Silicon. It transcribes speech locally with Whisper or Apple Speech, types live text into the focused application, and can optionally polish a completed transcript with an on-device model or an explicitly configured OpenAI-compatible endpoint.

Butterfly is a menu bar app. The recommended workflow is to build or launch the packaged app with `./run.sh`; this gives the app the resources, app bundle metadata, and signing step required by macOS permissions.

## Requirements

- Apple Silicon Mac (`arm64`)
- macOS 13 or later
- Xcode Command Line Tools and Swift 5.9 or later
- Homebrew and the `whisper-cpp` package for downloaded local Whisper models
- macOS 26 or later with Apple Intelligence enabled for the Apple Foundation Models backend

The app can still use the built-in Apple Speech model when no downloaded Whisper model is available. Apple Speech requires the macOS Speech Recognition permission.

## Install, build, and launch

From the repository root:

```bash
./run.sh
```

The first invocation checks the platform and developer tools, installs `whisper-cpp` with Homebrew when needed, builds a release app, and opens it. Later invocations launch the existing app without rebuilding or signing it. This distinction matters: a rebuild can change the ad-hoc code signature and cause macOS to ask for Accessibility again.

Use these options when needed:

| Command | Behavior |
| --- | --- |
| `./run.sh` | Launch the existing `.build/app/Butterfly.app`; build it first if it does not exist. |
| `./run.sh --build` | Rebuild a release app, sign it, and launch it. |
| `./run.sh --debug` | Rebuild a debug app, sign it, and launch it. |
| `./run.sh --release` | Explicit release rebuild. |
| `./run.sh --clean` | Clean Swift package artifacts, rebuild, and launch. |
| `./run.sh --no-open` | Build and sign without launching. |
| `./run.sh --no-build` | Launch an existing app only; fails when no app has been built. |
| `./run.sh --help` | Show the current launcher help. |

The packaged app is created at:

```text
.build/app/Butterfly.app
```

For a library or CLI-only build, use Swift Package Manager directly:

```bash
brew install whisper-cpp
swift build
```

`swift run ButterflyApp` is useful for development, but `./run.sh` is preferred for normal use because it creates the complete `.app` bundle and applies the same signing and resource packaging as a user launch.

## Permissions and macOS signing

Butterfly needs these permissions for the corresponding features:

| Permission | Required for |
| --- | --- |
| **Accessibility** | Global `Option + Space` shortcuts, the low-level event tap, swallowing the first Enter/Esc, and keyboard/clipboard insertion. |
| **Microphone** | Any recording mode. |
| **Speech Recognition** | Only when the active speech model is **Apple Speech Native**. Downloaded Whisper models transcribe locally and do not use this permission. |

Open **System Settings → Privacy & Security → Accessibility**, add the current `Butterfly.app`, and enable it. The menu bar status reports `Global Hotkeys: Ready` when the event tap is active. If it reports `Accessibility Permission Required` or `Hotkeys unavailable`, use **Open Accessibility Settings...** from the Butterfly menu and re-enable the exact app bundle being used.

The default build uses an ad-hoc signature (`codesign --sign -`). macOS associates an Accessibility grant with the signed app identity, so replacing the bundle with `./run.sh --build` or `--clean` may require removing the old Butterfly entry and adding the newly built app again. `./run.sh` without a build does not replace the bundle and normally preserves the existing grant. A stable Developer ID signing identity can be supplied with `BUTTERFLY_CODESIGN_IDENTITY`, but a paid Apple Developer membership is not required for local development. See [macOS signing and Accessibility](docs/MACOS_SIGNING_AND_ACCESSIBILITY.md) for the certificate purpose, TCC behavior, and recovery steps.

## Keyboard controls and modes

| Shortcut | Mode | Result |
| --- | --- | --- |
| `Option + Space` | **Live Voice Dictation** | Streams transcription into the focused input while recording. The HUD shows the live microphone waveform. |
| `Option + Shift + Space` | **Record & Smart Polish** | Records without inserting text, polishes the final transcript once, then inserts the result with a clipboard-safe paste. |
| `Enter` or `Esc` | Stop | Stops recording. The first Enter is swallowed by the event tap so a chat app cannot submit a partial message; the next Enter is passed through normally. |

The same actions are available from the menu bar if a global hotkey cannot be used. While Smart Polish is processing, Enter/Esc remains swallowed until insertion finishes.

## Speech models and model storage

The **Speech Model** menu controls local ASR. The available models are:

- Whisper Large-v3-Turbo (highest accuracy, about 1.6 GB)
- Whisper Small (about 488 MB)
- SenseVoice Small (about 230 MB; catalog entry, currently disabled by the bundled runtime)
- Whisper Base (about 148 MB)
- Whisper Tiny (about 78 MB)
- Apple Speech Native (built into macOS)

Downloaded Whisper files are stored in `~/.cache/butterfly/models`. The app selects the highest-ranked downloaded runtime-supported model unless a downloaded model has been selected in the menu. Apple Speech is the fallback when no usable Whisper model is cached. The selected ASR model is stored in the app's UserDefaults and is independent of the Smart Polish model.

The menu also provides model download, deletion, cache cleanup, and **Open Models Folder in Finder**. The CLI exposes the same cache:

```bash
swift run butterfly-cli models
swift run butterfly-cli download whisper-large-v3-turbo
swift run butterfly-cli delete whisper-small
swift run butterfly-cli clean
swift run butterfly-cli info
```

## Smart Polish configuration

Butterfly reads this exact file when Smart Polish starts:

```text
~/.config/butterfly/butterfly.json
```

The repository includes [`butterfly.sample.json`](butterfly.sample.json). It is a safe template with placeholders, not a credential file. Copy it once, then edit the copy:

```bash
mkdir -p ~/.config/butterfly
cp butterfly.sample.json ~/.config/butterfly/butterfly.json
```

The `polish.defaultModel` value is the model used at startup. A model ID is either a built-in ID or `<provider-id>/<model-id>`:

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
        "apiKey": "$AI_API_KEY",
        "timeoutMs": 30000
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

Built-in model IDs are:

- `local/foundation`: Apple Foundation Models on macOS 26+.
- `local/rules`: deterministic local rules; it does not call a remote model.

For an endpoint, set `polish.defaultModel` to `my-provider/example-model`. Providers currently use `type: "openai-compatible"`; `options.baseURL` accepts HTTPS URLs (HTTP is allowed only for loopback), `apiKey` and custom headers are optional, and the model can select `api: "chat-completions"` or `api: "responses"`. Model entries may also define limits, variants, reasoning options, and chunk sizes; see [endpoint configuration](docs/POLISH_ENDPOINTS.md).

The decoder accepts the old `polish.model` key for existing installations, but new files should use `polish.defaultModel`. The **Smart Polish Model** menu can temporarily override the configured default for the current app process. **Reload Polish Configuration** clears that override; restarting the app also returns to `polish.defaultModel`.

### Smart Polish styles and fallback

Choose **Smart Polish Style** from the menu bar. The selection is stored in UserDefaults and survives relaunches:

| Style | Behavior |
| --- | --- |
| **Faithful Proofread** | Correct punctuation and boundaries while preserving wording and detail. |
| **Concise Polish** | Remove fillers, stutters, abandoned starts, and clearly redundant repetition while preserving substantive points. This is the default. |
| **Structured Notes** | Keep paragraph-first blocks and add headings or genuine parallel lists when they clarify the transcript. |
| **Summary** | Keep central ideas, decisions, caveats, and conclusions; omit minor detail. |

If the selected primary backend is unavailable, Butterfly uses the configured `rules` fallback and reports the reason. Rule fallback is deterministic and has less context-sensitive restructuring than an LLM, so selecting **Structured Notes** does not guarantee extensive bullet lists when the fallback is active. A custom editing prompt can be placed at `~/.config/butterfly/SMART_POLISH_PROMPT.md`; the bundled prompt is used when that file is absent.

## CLI commands

The CLI is useful for checking models, formatting, and configuration without launching the menu bar app:

```bash
swift run butterfly-cli listen
swift run butterfly-cli test
swift run butterfly-cli test-polish --smart --style structured
swift run butterfly-cli test-convert "服务器内存不足"
swift run butterfly-cli models
swift run butterfly-cli info
```

`butterfly-cli test-polish --smart` loads the same `~/.config/butterfly/butterfly.json` and environment variables as the app. The CLI test runner is a zero-dependency logic suite; use `swift test` for XCTest targets.

## User customization and important paths

- `~/.config/butterfly/butterfly.json` — Smart Polish default model and providers.
- `~/.config/butterfly/dictionary.txt` — optional technical vocabulary; Butterfly initializes it from the bundled dictionary and reloads it at each recording start.
- `~/.config/butterfly/SMART_POLISH_PROMPT.md` — optional Smart Polish prompt override.
- `~/.cache/butterfly/models` — downloaded speech models.
- `.build/app/Butterfly.app` — packaged app produced by `run.sh`.
- `Sources/ButterflyCore/Resources/dictionary.txt` — bundled speech-recognition vocabulary and contextual biasing terms.

Keep personal configuration and credentials outside version control. `butterfly.sample.json` intentionally contains only generic names and environment-variable placeholders.

## Architecture

```text
Microphone
   │
   ▼
Local Whisper / Apple Speech ──► Traditional Chinese + formatting
   │                                  │
   ├─ Live Voice Dictation ───────────┴─► streaming cursor deltas
   │
   └─ Record & Smart Polish ─► local Foundation / rules / configured endpoint
                                      │
                                      └─► one clipboard-safe insertion
```

The core Swift package is split into audio capture, speech engines, text formatting and polishing, input injection, and state coordination. The AppKit target owns the menu bar item, floating HUD, global event tap, permissions, and lifecycle. See [architecture details](docs/ARCHITECTURE.md) and the [test plan](docs/TEST_PLAN.md).

## Troubleshooting

### `Hotkeys unavailable` or `Accessibility Permission Required`

Confirm that Accessibility is enabled for the exact `.build/app/Butterfly.app` currently running. If you used `./run.sh --build` or `--clean`, macOS may treat the newly signed ad-hoc bundle as a different client: quit Butterfly, remove the old entry, add the current app again, and enable it. `./run.sh` without a build reuses the existing signed bundle.

### `The language model is unavailable`

Check the selected Smart Polish model in the menu. For an endpoint model, validate JSON, confirm `type` is `openai-compatible`, ensure any referenced environment variables are available to the launched app, and relaunch it. For `local/foundation`, confirm that the OS supports Apple Foundation Models and that Apple Intelligence is available. The app falls back to rules when the primary backend cannot be used.

### Smart Polish does not produce headings or lists

Select **Structured Notes** in **Smart Polish Style**. Check whether the model menu says **(Configured)** or **(Rules Fallback)**; rules fallback intentionally performs conservative deterministic formatting.

### Recording does not start

Grant Microphone permission. If the active ASR model is Apple Speech Native, also grant Speech Recognition. For a Whisper model, download a supported model from the **Speech Model** menu or with `butterfly-cli download`.

### Verify the app and cache state

```bash
swift run butterfly-cli info
codesign --verify --deep --strict .build/app/Butterfly.app
```
