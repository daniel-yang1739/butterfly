# Butterfly 系統架構設計文件 (System Architecture)

## 1. 專案概念與使命 (Concept & Mission)

> **Butterfly（蝴蝶）**  
> **寓意**：解放雙手，無需碰觸鍵盤，讓雙手如蝴蝶雙翼般自由展翅（Hands-Free Voice Dictation）。  
> **使命**：專為 macOS (Apple Silicon) 打造的極致輕量、零雲端依賴的本地端語音輸入工具。在任何輸入框聚焦時，一鍵語音輸入，即時中英雙語混雜辨識，並強制轉換為標準台灣繁體中文輸出。

---

## 2. 系統架構圖 (System Architecture Diagram)

```mermaid
graph TB
    subgraph UserLayer ["1. 使用者互動層 (User Interaction Layer)"]
        Hotkey["全域快捷鍵監聽<br/>(Global HotKey / CGEventTap)"]
        HUD["懸浮膠囊 HUD<br/>(SwiftUI Floating Capsule)"]
        MenuBar["狀態選單列<br/>(Status Menu Bar 🦋)"]
    end

    subgraph AudioPipeline ["2. 音訊採集與處理層 (Audio & VAD Pipeline)"]
        MicCapture["麥克風低延遲收音<br/>(AVAudioEngine 16kHz PCM)"]
        VAD["語音活動偵測<br/>(Voice Activity Detector)"]
        AudioBuffer["音訊重取樣與緩衝區<br/>(16kHz Mono Float Buffer)"]
    end

    subgraph InferenceEngine ["3. 本地 AI 推論抽象層 (Local Inference Engine)"]
        Protocol["<< Protocol >><br/>SpeechInferenceBackend"]
        AppleMetal["Apple Silicon 後端 (CoreML ANE + Metal GPU)"]
        ModelCache["本機模型快取管理<br/>(~/.cache/butterfly/models/)"]
    end

    subgraph TextProcessing ["4. 文字格式化與繁中轉換層 (Text Processing Layer)"]
        OpenCC["OpenCC 繁中轉換引擎<br/>(s2twp 台灣正體與慣用詞彙)"]
        TextFormatter["中英混排空格校正與去重<br/>(Text Normalizer)"]
    end

    subgraph InputInjection ["5. 系統焦點注入層 (Input Injection Layer)"]
        AXDetector["焦點輸入框偵測<br/>(macOS Accessibility AXUIElement)"]
        KeystrokeInjector["自動貼上與鍵盤模擬<br/>(CGEvent / Clipboard Proxy)"]
        ClipRestorer["剪貼簿備份與瞬時還原<br/>(Clipboard Restorer)"]
    end

    %% Flow Connections
    Hotkey -->|觸發錄音| MicCapture
    MicCapture --> AudioBuffer
    AudioBuffer --> VAD
    VAD -->|說話結束/手動停止| AudioBuffer
    AudioBuffer -->|傳遞 16kHz 音訊| Protocol
    Protocol -.->|實作| AppleMetal
    ModelCache -.-> AppleMetal
    AppleMetal -->|原始中英辨識串流| OpenCC
    OpenCC -->|繁體中文 + 英文| TextFormatter
    TextFormatter -->|即時預覽| HUD
    TextFormatter -->|最終文字| AXDetector
    AXDetector --> KeystrokeInjector
    KeystrokeInjector --> ClipRestorer
    ClipRestorer -->|注入文字| FocusedApp["前台活動視窗 (VS Code, Chrome, Terminal, Slack 等)"]
```

---

## 3. 核心狀態機與生命週期 (State Machine)

```mermaid
stateDiagram-v2
    [*] --> Idle: 應用程式啟動

    Idle --> Listening: 按下全域快捷鍵 (Option+Space)
    Listening --> Listening: 麥克風即時取樣 (音波動畫顯示於 HUD)
    
    Listening --> Processing: 偵測到靜音停頓 / 再次按下快捷鍵
    Processing --> Normalizing: 本地端 Metal/NPU 模型轉譯音訊
    Normalizing --> Injecting: OpenCC (s2twp) 繁中轉換 + 格式美化
    
    Injecting --> Restoring: 備份剪貼簿 -> 模擬貼入焦點輸入框
    Restoring --> Idle: 0.05 秒內還原原剪貼簿 -> 隱藏 HUD
```

---

## 4. 可插拔硬體推論協定 (Pluggable Backend Protocol)

核心推論層採用抽象協定設計，上層所有繁中轉換、排版、VAD 與測試案例完全與底層硬體解耦：

- **macOS (v1)**：`AppleSiliconInferenceBackend`（榨取 CoreML ANE 與 Metal GPU 算力）。
- **Windows (v2 擴充)**：`WindowsNPUBackend`（支援 Qualcomm QNN、Intel OpenVINO、DirectML）。
