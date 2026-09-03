# 🦋 Butterfly - AI Agent & Developer Guide

Welcome to the **Butterfly** repository. This document defines the engineering standards, architecture patterns, and operational rules for AI agents and human contributors collaborating on this codebase.

---

## 🌐 Language & Localization Policy

1. **Repository English Rule**:
   - All source code files (`Sources/`), test suites (`Tests/`), configuration files (`Package.swift`, build scripts), commit messages, symbol identifiers, comments, and docstrings **MUST be written strictly in English**.
   - The only exception is the `docs/` directory or dictionary lookup tables in `OpenCCTranslator.swift` / regexes in `TextPolisher.swift`.
2. **User Interaction Language**:
   - When conversing with the user in chat or providing conversational summaries, always use **Traditional Chinese (Taiwan standard, zh-TW, 繁體中文)** as defined in user global rules.

---

## 🏛️ System Architecture

Butterfly is structured as a modular Swift Package consisting of three main targets:

```text
butterfly/
├── SYSTEM_PROMPT.md             # External editable system prompt & cognitive guidelines
├── Package.swift                # Swift Package Manager manifest (macOS 13+)
├── AGENTS.md                    # Agent developer guidelines (this file)
├── README.md                    # Public repository documentation
├── docs/                        # System documentation and architecture guides
│   ├── ARCHITECTURE.md          # Detailed pipeline architecture & diagrams
│   ├── IMPLEMENTATION_PLAN.md   # Roadmap & feature implementations
│   └── TEST_PLAN.md             # Test matrix and quality assurance specs
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

## 🎙️ Operating Model & Global Hotkeys

Butterfly provides a pure, zero-latency real-time voice dictation experience powered by Whisper ASR and direct cursor injection:

1. **Toggle Real-Time Voice Dictation (`Option + Space`)**:
   - 100% faithful real-time speech-to-text with continuous streaming directly into your active cursor via `InputInjector.injectStreamingDelta`.
   - Zero intermediate delay, zero sliding window complexity.
   - Preserves natural spoken narrative flow, numbers/units formatting, and Pangu spacing.
2. **Stop & Commit Dictation (`Enter` / `Esc`)**:
   - Monitored via macOS low-level `CGEventTap` (`.headInsertEventTap`).
   - The first `Enter` stops recording and is **swallowed at the OS level to prevent accidental chat/agent message submission**.
   - The second `Enter` passes through normally to submit your message.
3. **Lexicon & Domain Customization**:
   - Built-in curated software engineering, InfoSec, and service naming dictionary (`Sources/ButterflyCore/Resources/dictionary.txt`).
   - Dynamically merged with user overrides from `~/.config/butterfly/dictionary.txt` on every recording start.

---

## 🛠️ Development Workflows

### Building the Project
```bash
swift build
```

### Running CLI Tools
```bash
# Start terminal live streaming dictation
swift run butterfly-cli listen

# Run full automated test suite (25 core logic assertions)
swift run butterfly-cli test

# List available speech recognition models
swift run butterfly-cli models

# Display hardware acceleration, model cache and dictionary telemetry
swift run butterfly-cli info
```

### Running the macOS Application
```bash
swift run ButterflyApp
```

---

## 📐 Key Engineering Conventions

1. **Strict Concurrency & Sendable Compliance**:
   - All shared singletons and manager classes must adhere to Swift concurrency guidelines (`@unchecked Sendable` or actor isolation with thread locks).
2. **Zero Cloud Dependency & Local Privacy**:
   - All audio processing, speech recognition, and text polishing run 100% locally on the user's Apple Silicon hardware.
3. **Traditional Chinese Guarantee**:
   - Transcribed Chinese text passes through official `OpenCC` (`s2twp` standard via `SwiftyOpenCC`) to guarantee 0% Simplified Chinese in final outputs.
4. **Lean Contextual Biasing**:
   - Contextual strings are strictly restricted to curated tech terms to prevent acoustic model dilution and startup latency.
5. **Native macOS AppKit Best Practices**:
   - `NSStatusItem` must natively bind `statusItem.menu` to prevent recursive event dispatch loops.
