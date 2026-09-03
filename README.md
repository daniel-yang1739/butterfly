<p align="center">
  <img src="docs/assets/banner.jpg" alt="Butterfly Banner" width="100%" />
</p>

# 🦋 Butterfly: macOS Native Real-Time Streaming Voice Dictation

> **Butterfly**: Liberate your hands from the keyboard and let your thoughts fly freely with zero-latency, hands-free local voice dictation.

A lightweight, privacy-focused, zero-cloud-dependency local speech-to-text tool built for macOS (Apple Silicon). Whenever your cursor is focused in any text input or application, press <kbd>Option</kbd> + <kbd>Space</kbd> to stream mixed Chinese and English speech directly into your active cursor with automatic pause-gated typo self-healing and guaranteed Traditional Chinese (Taiwan standard / OpenCC `s2twp`).

---

## ✨ Key Features

1. **🎙️ Real-Time Live Streaming Voice Dictation (`Option + Space`)**:
   - 100% faithful real-time speech-to-text with continuous streaming directly into your active cursor.
   - **Pause-Gated In-Place Self-Healing (0.8s)**: Automatically normalizes tech terms (`System Prompt`, `Context`, `Model`), numbers, and units (`800 MB`, `1000 行`) on short pauses without disturbing earlier text.
   - **Cumulative Anti-Avalanche Freezing**: Automatically freezes validated clauses in RAM and screen mirror to ensure zero sentence duplication and zero avalanche deletions.
2. **🛑 Chat-Safe Accidental Send Protection (`Enter` / `Esc`)**:
   - Press <kbd>Enter</kbd> (or <kbd>Esc</kbd>) to stop voice dictation.
   - The first <kbd>Enter</kbd> is intercepted and swallowed at the OS level by low-level `CGEventTap` so it **never accidentally sends messages in Slack, Discord, ChatGPT, Claude, or Cursor**!
   - The second <kbd>Enter</kbd> passes through normally to submit your message.
3. **🇹🇼 Guaranteed Traditional Chinese Output (Zero Simplified Chinese)**:
   - Integrates OpenCC `s2twp` dictionary to convert all recognized Chinese into Taiwan Traditional Chinese standards (`伺服器`, `記憶體`, `程式碼`, `專案`), while preserving original English terms.
4. **🩹 Spoken Typo Self-Healing & Code-Switching**:
   - Accurately recognizes mixed Chinese and English speech (e.g., `System Prompt`, `Context`, `Source Code`, `README`, `AGENTS.md`, `Docker`, `Python`).
   - Applies standard Pangu spacing (a single space between CJK characters and alphanumeric terms: `800 MB 的空間`).
5. **⚡ Multi-Tiered Whisper ASR Whitelist on Apple Silicon**:
   - Built-in multi-model support:
     - 🥇 **Rank 1**: `Whisper Large-v3-Turbo` (1.62 GB / Flagship accuracy)
     - 🥈 **Rank 2**: `Whisper Small` (488 MB / High accuracy code-switching)
     - 🥉 **Rank 3**: `SenseVoice Small` (230 MB / Ultra-low latency)
     - 🍎 **Rank 4**: `Apple Speech Native` (Built-in / 0 MB)
   - Hardware accelerated via Apple Neural Engine (ANE / NPU) and Metal GPU.
6. **🔒 100% On-Device Privacy**:
   - All audio processing and speech recognition execute 100% locally on your Mac. No audio or text ever leaves your machine.

---

## 📁 Repository Structure

```text
butterfly/
├── SYSTEM_PROMPT.md             # External editable system prompt & vocabulary rules
├── docs/
│   ├── ARCHITECTURE.md          # Architecture & pipeline data flow diagrams
│   ├── TEST_PLAN.md             # Test plan & quality assurance matrix
│   └── IMPLEMENTATION_PLAN.md   # Implementation roadmap & design details
├── AGENTS.md                    # Agent instructions & engineering guidelines
├── Package.swift                # Swift Package Manager configuration (macOS 13+)
├── Sources/
│   ├── ButterflyCore/           # Core framework library
│   │   ├── Audio/               # Audio capture, resampling & VAD detection
│   │   ├── Engine/              # Whisper inference backend, LiveSpeechEngine, ModelManager
│   │   ├── Injector/            # CGEvent keyboard injector & cursor proxy
│   │   ├── State/               # State machine coordinator
│   │   └── Text/                # OpenCC s2twp, TextFormatter, TextPolisher, SlidingWindowBuffer
│   ├── ButterflyCLI/            # Command-line interface for testing & benchmarking
│   └── ButterflyApp/            # Native macOS menu bar application with CGEventTap
└── Tests/
    └── ButterflyTests/          # Unit test suites (36 automated assertions)
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

# Run full 36-assertion automated unit test suite
swift run butterfly-cli test

# List supported local speech recognition models
swift run butterfly-cli models

# Display hardware acceleration and cache directory info
swift run butterfly-cli info
```

### 3. Launch the macOS Menu Bar App
```bash
swift run ButterflyApp
```

Once launched, the 🦋 icon will appear in your macOS menu bar:
- Press <kbd>Option</kbd> + <kbd>Space</kbd> to start/stop **Live Voice Dictation**.
- Press <kbd>Enter</kbd> (or <kbd>Esc</kbd>) to **Stop Dictation** (First Enter stops recording safely without sending; Second Enter submits).
- Click the menu bar icon to download or switch between Whisper models.
