<p align="center">
  <img src="docs/assets/banner.jpg" alt="Butterfly Banner" width="100%" />
</p>

# 🦋 Butterfly: macOS Native Real-Time Streaming Voice Dictation

> **Butterfly**: Liberate your hands from the keyboard and let your thoughts fly freely with zero-latency, hands-free local voice dictation on Apple Silicon.

A lightweight, privacy-focused, zero-cloud-dependency local speech-to-text system built for macOS (Apple Silicon). Whenever your cursor is focused in any text input, terminal, or application, press <kbd>Option</kbd> + <kbd>Space</kbd> to stream mixed Chinese and English speech directly into your active cursor with automatic punctuation, Pangu spacing, curated technical vocabulary, and guaranteed Traditional Chinese (Taiwan standard / OpenCC `s2twp`).

---

## ✨ Key Features

1. **🎙️ Direct Real-Time Streaming Voice Dictation (`Option + Space`)**:
   - 100% faithful real-time speech-to-text with continuous live typing directly into your focused cursor via `InputInjector.injectStreamingDelta`.
   - Zero-latency character streaming: Words appear on screen the instant you speak.
   - Preserves natural spoken narrative flow without artificial delays.
2. **🛑 Chat-Safe Accidental Send Protection (`Enter` / `Esc`)**:
   - Press <kbd>Enter</kbd> (or <kbd>Esc</kbd>) to stop voice dictation.
   - The first <kbd>Enter</kbd> is intercepted and swallowed at the macOS OS level by a low-level `CGEventTap` (`.headInsertEventTap`), ensuring you **never accidentally submit half-finished messages in Slack, Discord, ChatGPT, Claude, or Cursor**!
   - The second <kbd>Enter</kbd> passes through normally to submit your message.
3. **🇹🇼 Guaranteed Traditional Chinese Output (Zero Simplified Chinese)**:
   - Integrates the official `SwiftyOpenCC` package (`s2twp` standard with Taiwan idioms) to convert all recognized Chinese into Taiwan Traditional Chinese standards (`伺服器`, `記憶體`, `程式碼`, `資料庫`, `專案`), while strictly preserving English tokens and case.
   - Native Apple ICU Hans-to-Hant transliteration fallback.
4. **📚 Curated Software Engineering, InfoSec & Architecture Lexicon**:
   - **Bundled Out-of-the-Box**: Ships with over 300+ curated developer, cybersecurity, and service naming keywords in `Sources/ButterflyCore/Resources/dictionary.txt` (`Git`, `Docker`, `Kubernetes`, `CI/CD`, `Threat Model`, `Zero Trust`, `WAF`, `OAuth`, `Translator`, `Manager`, `Sensor`, `Agent`...).
   - **Dynamic User Config**: Automatically initializes `~/.config/butterfly/dictionary.txt` for personal team jargon and hot-reloads on every recording session without restarting the app.
   - **Lean Contextual Biasing**: Fast-loading acoustic prior weighting (< 5ms startup delay) that eliminates acoustic model distortion.
5. **🪄 Automatic Pangu Spacing & Number Formatting**:
   - Automatically inserts Pangu spacing (standard typographic space between CJK characters and alphanumeric terms, e.g. `800 MB 的空間`).
   - Formats spoken numbers and digital storage units (`八百 MB` $\rightarrow$ `800 MB`, `兩千行` $\rightarrow$ `2000 行`).
6. **⚡ Multi-Tiered Whisper ASR Whitelist on Apple Silicon**:
   - Built-in multi-model support:
     - 🥇 **Rank 1**: `Whisper Large-v3-Turbo` (1.62 GB / Flagship accuracy, recommended)
     - 🥈 **Rank 2**: `Whisper Small` (488 MB / High accuracy code-switching)
     - 🥉 **Rank 3**: `SenseVoice Small` (230 MB / Ultra-low latency)
     - 🍎 **Rank 4**: `Apple Speech Native` (Built-in / 0 MB)
   - Hardware accelerated via Apple Neural Engine (ANE) and Metal GPU unified memory.
7. **🖥️ Sleek Floating Capsule HUD**:
   - Displays real-time streaming speech transcription in a modern frosted-glass floating capsule HUD (`FloatingHUDWindow`).
8. **🔒 100% On-Device Privacy**:
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
swift build
```

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
```

### 3. Launch the macOS Menu Bar App
```bash
swift run ButterflyApp
```

Once launched, the 🦋 icon will appear in your macOS menu bar:
- Press <kbd>Option</kbd> + <kbd>Space</kbd> to toggle **Live Voice Dictation**.
- Press <kbd>Enter</kbd> (or <kbd>Esc</kbd>) to **Stop Dictation** (First Enter safely stops recording; Second Enter submits).
- Click the menu bar icon to download or switch between Whisper models, manage cached model storage, or open the models directory in Finder.
