<p align="center">
  <img src="docs/assets/banner.jpg" alt="Butterfly Banner" width="100%" />
</p>

# 🦋 Butterfly: macOS Native Real-Time Dual-Mode Speech-to-Text & Note Polisher

> **Butterfly**: Liberate your hands from the keyboard and let your thoughts fly freely with hands-free voice dictation and intelligent note structuring.

A lightweight, privacy-focused, zero-cloud-dependency local speech-to-text tool built for macOS (Apple Silicon). Whenever your cursor is focused in any text input or application, press a global hotkey to transcribe mixed Chinese and English speech with real-time streaming or smart note structuring into Traditional Chinese (Taiwan standard / OpenCC s2twp).

---

## ✨ Key Features

1. **Dual Voice Input Modes**:
   - **🎙️ Mode 1: Live Streaming Dictation (`Option + Space`)**:
     - Real-time streaming transcription with live incremental typing directly into your active cursor.
     - Live filler word removal and stutter filtering.
   - **📝 Mode 2: Record & Smart Polish (`Option + Shift + Space`)**:
     - Complete, uninterrupted recording of long monologues, meetings, and thoughts.
     - Automatic deep filler filtering (`呃`, `啊`, `哦`, `那個那個`, `就是說`), stutter cleaning, intelligent paragraph structuring, and Markdown bullet point extraction (`- ...`).
     - One-shot paste into the active window with clipboard protection.
2. **Seamless Code-Switching (Mixed Chinese & English)**:
   - Accurately recognizes mixed Chinese and English speech (e.g., "Please review this React component") without manual language switching.
3. **Guaranteed Traditional Chinese Output (Zero Simplified Chinese)**:
   - Integrates OpenCC `s2twp` dictionary to convert all recognized Chinese into Taiwan Traditional Chinese standards (`伺服器`, `記憶體`, `程式碼`), while preserving original English terms.
4. **Apple Silicon Hardware Acceleration**:
   - Hardware accelerated via Apple Neural Engine (ANE / NPU) and Metal GPU for low latency and minimal battery consumption.
5. **Universal Focus Injection**:
   - Works across all macOS apps via simulated keyboard events and Accessibility APIs with automatic clipboard backup and restoration.

---

## 📁 Repository Structure

```text
butterfly/
├── docs/
│   ├── ARCHITECTURE.md          # Architecture & data flow diagrams
│   ├── TEST_PLAN.md             # Test plan & verification matrix
│   └── IMPLEMENTATION_PLAN.md   # Implementation roadmap & design details
├── AGENTS.md                    # Agent instructions & development guidelines
├── Package.swift                # Swift Package Manager configuration
├── Sources/
│   ├── ButterflyCore/           # Core library (Text, Audio, Engine, Injector, State)
│   ├── ButterflyCLI/            # Command-line interface for testing & benchmarking
│   └── ButterflyApp/            # Native macOS menu bar application
└── Tests/
    └── ButterflyTests/          # Unit test suites
```

---

## 🚀 Quick Start

### 1. Build the Project
```bash
swift build
```

### 2. Run CLI Commands
```bash
# List supported local models and download status
swift run butterfly-cli models

# Display hardware acceleration and cache directory info
swift run butterfly-cli info

# Test text polishing, bullet points, and filler removal
swift run butterfly-cli test-polish "呃我想說就是說，我們有兩種模式需求，第一點是即時串流，第二點是錄音智慧整理。"

# Start Live Streaming Dictation in terminal
swift run butterfly-cli listen

# Start Record & Smart Polish mode in terminal
swift run butterfly-cli listen --polish
```

### 3. Launch the macOS Menu Bar App
```bash
swift run ButterflyApp
```
Once launched, the 🦋 icon will appear in your macOS menu bar:
- Press <kbd>Option</kbd> + <kbd>Space</kbd> to start **Live Streaming Dictation**.
- Press <kbd>Option</kbd> + <kbd>Shift</kbd> + <kbd>Space</kbd> to start **Record & Smart Polish**.
- Press <kbd>Esc</kbd> at any time to **Stop & Commit Recording**.
