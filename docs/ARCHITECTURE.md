# Butterfly 系統架構設計文件 (System Architecture)

## 1. 專案概念與使命 (Concept & Mission)

> **Butterfly（蝴蝶）**  
> **寓意**：解放雙手，無需碰觸鍵盤，讓雙手如蝴蝶雙翼般自由展翅（Hands-Free Voice Dictation）。  
> **使命**：專為 macOS (Apple Silicon) 打造的極致輕量、零雲端依賴的本地端語音輸入與筆記重構工具。在任何輸入框聚焦時，一鍵語音輸入，即時中英雙語混雜辨識，並強制轉換為標準台灣繁體中文輸出。

---

## 2. 系統架構圖 (System Architecture Diagram)

```mermaid
graph TB
    subgraph UserLayer ["1. 使用者互動層 (User Interaction Layer)"]
        CGTap["macOS 核心事件攔截器<br/>(Low-Level CGEventTap)"]
        MenuBar["狀態選單列<br/>(Status Menu Bar 🦋)"]
        SystemPromptDoc["智慧潤稿 Prompt<br/>(SMART_POLISH_PROMPT.md)"]
    end

    subgraph AudioPipeline ["2. 音訊採集與會話管理層 (Audio Pipeline)"]
        MicCapture["麥克風低延遲收音<br/>(AVAudioEngine 16kHz PCM)"]
        SessionRecycler["會話資源乾淨回收器<br/>(Audio Tap / Session Recycler)"]
    end

    subgraph InferenceEngine ["3. 本地 AI 推論與模型層 (Inference & Whitelist Engine)"]
        WhitelistManager["強弱優先白名單管理器<br/>(ModelManager Prioritized Whitelist)"]
        WhisperLarge["Whisper Large-v3-Turbo (Rank 1)"]
        AppleSpeech["Apple Speech Native (Fallback)"]
        SingleSourceAccumulator["單一真源就地狀態機<br/>(In-Place Utterance Tracker)"]
    end

    subgraph TextProcessing ["4. 兩輪認知重構與繁中轉換層 (Two-Pass Cognitive Engine)"]
        OpenCC["OpenCC 繁中轉換引擎<br/>(s2twp 台灣正體與慣用詞彙)"]
        TextFormatter["數字/單位標準化與盤古之白<br/>(Arabic Digits & Pangu Spacing)"]
        CognitivePolisher["智慧潤稿引擎<br/>(Apple Foundation Models / Rules Fallback)"]
    end

    subgraph InputInjection ["5. 系統焦點注入與防誤送層 (Input Injection Layer)"]
        EnterSwallower["Enter 鍵攔截防誤送<br/>(First Enter Discarded)"]
        LiveStreamingDelta["即時游標 Unicode 鍵盤注入<br/>(CGEvent In-Place Delta)"]
        ClipboardProxy["剪貼簿安全寫入與貼上<br/>(Pasteboard Cmd+V Proxy)"]
    end

    %% Flow Connections
    CGTap -->|"Option+Space (Mode 1)"| MicCapture
    CGTap -->|"Option+Shift+Space (Mode 2)"| MicCapture
    CGTap -->|"Enter (第一次按)"| EnterSwallower
    EnterSwallower -->|"吞掉 Enter 事件"| MicCapture
    MicCapture --> SessionRecycler
    SessionRecycler --> WhitelistManager
    WhitelistManager --> WhisperLarge
    WhitelistManager --> AppleSpeech
    AppleSpeech --> SingleSourceAccumulator
    SingleSourceAccumulator --> OpenCC
    OpenCC --> TextFormatter
    TextFormatter --> CognitivePolisher
    SystemPromptDoc -.-> CognitivePolisher
    CognitivePolisher -->|"Mode 1 即時打字"| LiveStreamingDelta
    CognitivePolisher -->|"Mode 2 忠實潤稿"| ClipboardProxy
    LiveStreamingDelta --> FocusedApp["前台活動視窗 (Cursor, VS Code, Chrome, Slack, Discord 等)"]
    ClipboardProxy --> FocusedApp
```

---

## 3. 雙模式運作與防誤送狀態機 (Dual-Mode & Safety State Machine)

```mermaid
stateDiagram-v2
    [*] --> Idle: 應用程式啟動 (載入 SYSTEM_PROMPT.md)

    Idle --> Mode1_Streaming: 按下 Option+Space (Mode 1)
    Idle --> Mode2_Recording: 按下 Option+Shift+Space (Mode 2)

    Mode1_Streaming --> Mode1_Streaming: 1~2 秒滑動視窗微調，即時 Unicode 打字 (保留所有詞句與標點)
    Mode2_Recording --> Mode2_Recording: 背景錄音，單一真源無重複累計

    Mode1_Streaming --> Stopping_SwallowEnter: 使用者按下 Enter / Esc
    Mode2_Recording --> Stopping_SwallowEnter: 使用者按下 Enter / Esc

    Stopping_SwallowEnter --> Idle: 1. CGEventTap 吞掉該 Enter 訊號 (防止目標 App 誤送訊息)<br/>2. 執行認知潤飾與注入<br/>3. 回收 Audio Engine 資源
```

---

## 4. 關鍵技術模組 (Key Technical Modules)

1. **`SmartPolishPrompt.swift` & `SMART_POLISH_PROMPT.md`**：
   - Mode 2 使用獨立提示詞，支援使用者覆寫且不影響 Whisper 詞彙偏置。
2. **`TextPolisher.swift`（兩輪認知意圖重構）**：
   - **Pass 1**：數字（`800`）、單位（`MB`, `GB`, `TB`, `kg`）與無邊界音素科技詞彙校正（`Mode 1`, `Mode 2`, `System Prompt`, `Context`, `Source Code`, `README`, `AGENTS.md`）。
   - **Pass 2**：Mode 1 嚴格非破壞性忠實輸出；Apple Intelligence 不可用時為 Mode 2 提供規則式 fallback。
3. **`LiveSpeechEngine.swift`（單一真源狀態機）**：
   - 廢除重複字串拼接，採用 `state.committed` + `state.active` 就地更新，徹底消除錄音時重複產生 3~4 次相同句子的問題。
4. **`ButterflyApp.swift`（低階 `CGEventTap` 核心攔截）**：
   - 註冊 `.cgSessionEventTap`，在錄音結束時吞掉 Enter 鍵，實現「第一次 Enter 結束錄音，第二次 Enter 才送出訊息」的安全保護。
