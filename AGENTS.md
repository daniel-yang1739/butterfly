# 🦋 Butterfly - AI Agent & Developer Guide

Welcome to the **Butterfly** repository. This document defines the engineering standards, architecture patterns, and operational rules for AI agents and human contributors collaborating on this codebase.

---

## 🌐 Language & Localization Policy

1. **Repository English Rule**:
   - All source code files (`Sources/`), test suites (`Tests/`), configuration files (`Package.swift`, build scripts), commit messages, symbol identifiers, comments, and docstrings **MUST be written strictly in English**.
   - The only exception is the `docs/` directory or dictionary lookup tables in `OpenCCTranslator.swift` / regexes for Chinese filler removal in `TextPolisher.swift`.
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
│   │   ├── Injector/            # Low-level CGEventTap & cursor injector proxy
│   │   │   └── InputInjector.swift
│   │   ├── State/               # Core state machine coordinator
│   │   │   └── ButterflyStateMachine.swift
│   │   └── Text/                # OpenCC s2twp, TextFormatter & cognitive TextPolisher
│   │       ├── OpenCCTranslator.swift
│   │       ├── TextFormatter.swift
│   │       ├── TextPolisher.swift
│   │       └── TranscriptAccumulator.swift
│   ├── ButterflyCLI/            # Command-line interface for testing & benchmarking
│   │   └── main.swift
│   └── ButterflyApp/            # Native macOS menu bar application (CGEventTap integration)
│       └── ButterflyApp.swift
└── Tests/
    └── ButterflyTests/          # Unit test suites
        ├── InferenceEngineTests.swift
        ├── OpenCCTranslatorTests.swift
        ├── StateMachineTests.swift
        └── TextFormatterTests.swift
```

---

## 🎙️ Operating Model & Global Hotkeys

Butterfly provides a pure, zero-latency real-time voice dictation experience powered by Whisper ASR and a pure Swift in-place refinement engine:

1. **Toggle Real-Time Voice Dictation (`Option + Space`)**:
   - 100% faithful real-time speech-to-text with continuous streaming directly into your active cursor.
   - 0.8-second pause-gated in-place refinement (revises tech terms, numbers, and units without disturbing earlier text).
   - Preserves natural spoken narrative flow and punctuate accurately.
2. **Stop & Commit Dictation (`Enter` / `Esc`)**:
   - Monitored via macOS low-level `CGEventTap` (`.headInsertEventTap`).
   - The first `Enter` stops recording and is **swallowed at the OS level to prevent accidental chat/agent message submission**.
   - The second `Enter` passes through normally to submit your message.

---

## 🛠️ Development Workflows

### Building the Project
```bash
swift build
```

### Running CLI Tools
```bash
# List available models and hardware detection
swift run butterfly-cli models
swift run butterfly-cli info

# Test text polishing and bullet structuring
swift run butterfly-cli test-polish

# Start terminal live listening (Mode 1)
swift run butterfly-cli listen

# Start terminal record & polish mode (Mode 2)
swift run butterfly-cli listen --polish
```

### Running the macOS Application
```bash
swift run ButterflyApp
```

---

## 📐 Key Engineering Conventions

1. **Strict Concurrency & Sendable Compliance**:
   - All shared singletons and manager classes must adhere to Swift concurrency guidelines (`@unchecked Sendable` or actor isolation with `OSAllocatedUnfairLock`).
2. **Zero Cloud Dependency & Local Privacy**:
   - All audio processing, speech recognition, and text polishing run 100% locally on the user's Apple Silicon hardware.
3. **Traditional Chinese Guarantee**:
   - Any transcribed Chinese text must pass through `OpenCCTranslator` (s2twp standard) to ensure 0% Simplified Chinese characters in final outputs.
4. **Zero Hardcoded Paths**:
   - Dynamic path discovery using `FileManager.default.homeDirectoryForCurrentUser` and bundle resources.
