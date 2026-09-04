<p align="center">
  <img src="docs/assets/banner.jpg" alt="Butterfly Banner" width="100%" />
</p>

# 🦋 Butterfly: macOS Native Real-Time Streaming Voice Dictation

> **Butterfly**: Liberate your hands from the keyboard and let your thoughts fly freely with zero-latency, hands-free local voice dictation on Apple Silicon.

A lightweight, privacy-focused, zero-cloud-dependency local speech-to-text system built for macOS (Apple Silicon). Press <kbd>Option</kbd> + <kbd>Space</kbd> for live dictation, or <kbd>Option</kbd> + <kbd>Shift</kbd> + <kbd>Space</kbd> to record first and let Apple's on-device Foundation Model produce a faithfully polished result.

Smart Polish supports four persistent output styles: Faithful Proofread, Concise Polish, Structured Notes, and Summary. Choose the style from the menu bar before recording.

---

## ✨ Key Features

1. **🎙️ Direct Real-Time Streaming Voice Dictation (`Option + Space`)**:
   - Downloaded Whisper models use app-owned microphone capture and the local whisper.cpp inference backend; Apple Speech is used only when explicitly selected.
   - Uses a persistent whisper.cpp context and a bounded rolling audio window instead of reloading the model or retranscribing the full recording.
   - Updates the active transcript continuously and types only cursor deltas into the focused input.
   - Preserves natural spoken narrative flow while allowing Whisper to revise the active window.
2. **📝 Record & Smart Polish (`Option + Shift + Space`)**:
   - Records without typing into the focused field, then processes the completed transcript once.
   - Uses Apple Foundation Models on macOS 26+ to improve punctuation, paragraphs, grammar, fillers, and obvious repetition without summarizing or changing facts.
   - Automatically falls back to the built-in deterministic structured-note rules when Apple Intelligence is unavailable.
   - Splits long transcripts at sentence boundaries and inserts the final result with a single clipboard-safe paste.
3. **🛑 Chat-Safe Accidental Send Protection (`Enter` / `Esc`)**:
   - Press <kbd>Enter</kbd> (or <kbd>Esc</kbd>) to stop voice dictation.
   - The first <kbd>Enter</kbd> is intercepted and swallowed at the macOS OS level by a low-level `CGEventTap` (`.headInsertEventTap`), ensuring you **never accidentally submit half-finished messages in Slack, Discord, ChatGPT, Claude, or Cursor**!
   - The second <kbd>Enter</kbd> passes through normally to submit your message.
4. **🇹🇼 Guaranteed Traditional Chinese Output (Zero Simplified Chinese)**:
   - Integrates the official `SwiftyOpenCC` package (`s2twp` standard with Taiwan idioms) to convert all recognized Chinese into Taiwan Traditional Chinese standards (`伺服器`, `記憶體`, `程式碼`, `資料庫`, `專案`), while strictly preserving English tokens and case.
   - Native Apple ICU Hans-to-Hant transliteration fallback.
5. **📚 Curated Software Engineering, InfoSec & Architecture Lexicon**:
   - **Bundled Out-of-the-Box**: Ships with over 300+ curated developer, cybersecurity, and service naming keywords in `Sources/ButterflyCore/Resources/dictionary.txt` (`Git`, `Docker`, `Kubernetes`, `CI/CD`, `Threat Model`, `Zero Trust`, `WAF`, `OAuth`, `Translator`, `Manager`, `Sensor`, `Agent`...).
   - **Dynamic User Config**: Automatically initializes `~/.config/butterfly/dictionary.txt` for personal team jargon and hot-reloads on every recording session without restarting the app.
   - **Lean Contextual Biasing**: Fast-loading acoustic prior weighting (< 5ms startup delay) that eliminates acoustic model distortion.
6. **🪄 Automatic Pangu Spacing & Number Formatting**:
   - Automatically inserts Pangu spacing (standard typographic space between CJK characters and alphanumeric terms, e.g. `800 MB 的空間`).
   - Formats spoken numbers and digital storage units (`八百 MB` $\rightarrow$ `800 MB`, `兩千行` $\rightarrow$ `2000 行`).
7. **⚡ Multi-Tiered Whisper ASR Whitelist on Apple Silicon**:
   - Built-in multi-model support:
     - 🥇 **Rank 1**: `Whisper Large-v3-Turbo` (1.62 GB / Flagship accuracy, recommended)
     - 🥈 **Rank 2**: `Whisper Small` (488 MB / High accuracy code-switching)
     - 🥉 **Rank 3**: `SenseVoice Small` (230 MB / Ultra-low latency)
     - 🍎 **Rank 4**: `Apple Speech Native` (Built-in / 0 MB)
   - Hardware accelerated via Apple Neural Engine (ANE) and Metal GPU unified memory.
8. **🖥️ Sleek Floating Capsule HUD**:
   - Displays real-time streaming speech transcription in a modern frosted-glass floating capsule HUD (`FloatingHUDWindow`).
9. **🔒 100% On-Device Privacy**:
   - All audio processing, speech recognition, and formatting execute 100% locally on your Mac. Zero audio or text ever leaves your machine.

---

## 📁 Repository Structure

```text
butterfly/
├── SYSTEM_PROMPT.md             # External editable system prompt & cognitive guidelines
├── Package.swift                # Swift Package Manager configuration (macOS 13+)
├── AGENTS.md                    # Agent engineering guidelines & architecture specs
├── README.md                    # Public repository documentation
├── docs/                        # Architecture & pipeline design documentation
│   ├── ARCHITECTURE.md          # Pipeline data flow and threading diagrams
│   ├── TEST_PLAN.md             # Quality assurance and test specs
│   └── IMPLEMENTATION_PLAN.md   # Implementation roadmap & milestones
├── Sources/
│   ├── ButterflyCore/           # Core framework library
│   │   ├── Audio/               # Audio capture, resampling & VAD detection
│   │   │   ├── AudioCaptureManager.swift
│   │   │   └── VADDetector.swift
│   │   ├── Engine/              # Speech recognition, model whitelist & SystemPrompt
│   │   │   ├── AppleSiliconInferenceBackend.swift
│   │   │   ├── LiveSpeechEngine.swift
│   │   │   ├── ModelManager.swift
│   │   │   ├── SpeechInferenceBackend.swift
│   │   │   ├── SystemPrompt.swift
│   │   │   └── TechDictionary.swift
│   │   ├── Injector/            # Low-level CGEventTap & direct cursor delta typing
│   │   │   └── InputInjector.swift
│   │   ├── Resources/           # Bundled SPM resources
│   │   │   └── dictionary.txt   # Curated 300+ dev, InfoSec & architecture terms
│   │   ├── State/               # Core state machine coordinator
│   │   │   └── ButterflyStateMachine.swift
│   │   └── Text/                # Official OpenCC s2twp, TextFormatter & TextPolisher
│   │       ├── OpenCCTranslator.swift
│   │       ├── TextFormatter.swift
│   │       ├── TextPolisher.swift
│   │       └── TranscriptAccumulator.swift
│   ├── ButterflyCLI/            # Command-line interface for testing & benchmarking
│   │   ├── TestRunner.swift
│   │   └── main.swift
│   └── ButterflyApp/            # Native macOS menu bar application
│       ├── ButterflyApp.swift   # AppKit status bar coordinator & CGEventTap hotkeys
│       └── FloatingHUDWindow.swift # Modern floating capsule transcription HUD
└── Tests/
    └── ButterflyTests/          # Unit test suites (XCTest compatible)
        ├── InferenceEngineTests.swift
        ├── InputInjectorTests.swift
        ├── ModelManagerTests.swift
        ├── OpenCCTranslatorTests.swift
        ├── StateMachineTests.swift
        ├── SystemPromptTests.swift
        ├── TextFormatterTests.swift
        └── TextPolisherTests.swift
```

---

## 🚀 Quick Start

### 1. Build the Project
```bash
brew install whisper-cpp
swift build
```

Butterfly links directly to the local whisper.cpp library so the model stays resident during dictation. The Homebrew package provides the required headers, native library, and Metal backend.

### 2. Run CLI Commands
```bash
# Start Live Streaming Dictation in terminal
swift run butterfly-cli listen

# Run full 25-assertion automated unit test suite
swift run butterfly-cli test

# List supported speech recognition models
swift run butterfly-cli models

# Display hardware acceleration, active model, and dictionary telemetry
swift run butterfly-cli info

# Test deferred Smart Polish with Apple Intelligence or the rules fallback
swift run butterfly-cli test-polish --smart
```

### 3. Launch the macOS Menu Bar App
```bash
swift run ButterflyApp
```

### 4. Enable Whisper Core ML / Apple Neural Engine Acceleration

The local whisper.cpp backend uses Metal by default. Homebrew's standard build does not currently include Core ML encoder support. To run the Whisper encoder on the Apple Neural Engine while keeping the decoder on Metal, both the native library and model asset must support Core ML:

1. Build and link whisper.cpp with Core ML support instead of the standard Homebrew library:

   ```bash
   cmake -B build -DWHISPER_COREML=1
   cmake --build build -j --config Release
   ```

2. Generate and compile the Core ML encoder that matches the GGML model. For `ggml-large-v3-turbo.bin`, the expected sibling directory is:

   ```text
   ggml-large-v3-turbo-encoder.mlmodelc/
   ```

3. Place both artifacts in the same model cache directory:

   ```text
   ~/.cache/butterfly/models/
   ├── ggml-large-v3-turbo.bin
   └── ggml-large-v3-turbo-encoder.mlmodelc/
   ```

4. Run `swift run butterfly-cli info` to verify that the encoder asset is detected. The asset alone is not sufficient: Butterfly must also be linked to the Core ML-enabled whisper.cpp build.

For the fastest hybrid configuration, keep GPU support enabled so the Core ML encoder can use ANE while the decoder uses Metal.

Once launched, the 🦋 icon will appear in your macOS menu bar:
- Press <kbd>Option</kbd> + <kbd>Space</kbd> to toggle **Live Voice Dictation**.
- Press <kbd>Option</kbd> + <kbd>Shift</kbd> + <kbd>Space</kbd> to start **Record & Smart Polish**.
- Press <kbd>Enter</kbd> (or <kbd>Esc</kbd>) to **Stop Dictation** (First Enter safely stops recording; Second Enter submits).
- Click the menu bar icon to download or switch between Whisper models, manage cached model storage, or open the models directory in Finder.
- Choose a Smart Polish style from the plain-text `Smart Polish Style` submenu. The selection is remembered between launches.

Smart Polish uses Apple Intelligence when it is enabled and available on macOS 26 or later. You can override its editing instructions at `~/.config/butterfly/SMART_POLISH_PROMPT.md`; otherwise Butterfly uses its bundled faithful-editing prompt.
