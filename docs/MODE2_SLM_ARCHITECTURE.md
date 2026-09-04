# Butterfly Mode 2：錄音後智慧潤稿架構

## 目標

Mode 2 使用 `Option + Shift + Space` 啟動。錄音期間 Whisper 持續建立完整逐字稿，但不向游標輸入；停止後才將逐字稿交給 Apple Foundation Models 整理，最後一次貼入。

整理原則是忠實潤稿，而不是摘要：保留事實、數字、技術識別字、專有名詞、語氣強度與不確定性，只改善標點、文法、段落並移除贅詞、語句重啟及明顯重複。

## Pipeline

```text
Option+Shift+Space
        ↓
AVAudioEngine → persistent whisper.cpp sliding windows
        ↓
complete Traditional Chinese transcript (no live injection)
        ↓
SmartPolishEngine
        ├─ Apple SystemLanguageModel available → faithful semantic editing
        └─ unavailable or failed → TextPolisher.structuredNote
        ↓
single clipboard-safe paste → focused input
```

## 長文與失敗處理

- 1,500 字以內優先單次處理。
- 長文依句界分塊並保持順序；遇到 context 超限時遞迴縮小區塊。
- 每個區塊使用獨立 session，避免先前輸出持續占用 context。
- Apple Intelligence 未啟用、裝置不支援或生成失敗時，整篇改走規則式 fallback，避免混合兩種文風。
- 空逐字稿不呼叫模型，也不執行貼上。

## 操作與安全

- `Option + Space`：Mode 1 即時聽寫。
- `Option + Shift + Space`：Mode 2 錄音後智慧潤稿。
- Enter、Esc 或相同熱鍵：停止目前錄音，該按鍵會被吞掉。
- 處理期間拒絕重複啟動並吞掉 Enter，防止在結果產生前送出空白訊息。
- 貼上前備份完整剪貼簿；若使用者在處理期間複製了新內容，就不覆蓋新剪貼簿。

## Prompt

預設英文 prompt 隨 ButterflyCore resources 一起提供。使用者可建立以下檔案覆寫：

```text
~/.config/butterfly/SMART_POLISH_PROMPT.md
```

逐字稿永遠視為待編輯資料，不能用其中的口述內容覆寫整理指令。
