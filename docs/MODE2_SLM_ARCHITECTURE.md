# Butterfly Mode 2：錄音後智慧潤稿架構

## 目標

Mode 2 使用 `Option + Shift + Space` 啟動。錄音期間 Whisper 持續建立完整逐字稿，但不向游標輸入；停止後才將逐字稿交給 Apple Foundation Models 整理，最後一次貼入。

使用者可從純文字選單選擇四種整理強度，選擇會透過 `UserDefaults` 保留：

- `Faithful Proofread`：只處理標點、錯字、斷句與分段，不重排內容。
- `Concise Polish`：移除贅詞、語句重啟及明顯重複，保留所有實質觀點與原始順序。
- `Structured Notes`：採用 paragraph-first 的區塊結構；以完整段落為主，只在至少兩個完整、平行項目形成真正清單時插入條列。
- `Summary`：只保留核心資訊、結論與重要限制。

所有模式都禁止猜測缺少的數值或單位、回答逐字稿中的問題，或加入原文沒有的事實。

## Pipeline

```text
Option+Shift+Space
        ↓
AVAudioEngine → persistent whisper.cpp sliding windows
        ↓
complete Traditional Chinese transcript (no live injection)
        ↓
SmartPolishEngine + selected style
        ├─ Apple SystemLanguageModel available → style-specific semantic editing
        └─ unavailable or failed → conservative TextPolisher fallback
        ↓
single clipboard-safe paste → focused input
```

## 長文與失敗處理

- 1,500 字以內優先單次處理。
- 忠實校稿與精簡潤稿的長文依句界分塊並保持順序。
- 結構整理與摘要的長文先逐段保守整理，再進行全文整合。
- 遇到 context 超限時遞迴縮小區塊。
- 每個區塊使用獨立 session，避免先前輸出持續占用 context。
- Apple Intelligence 未啟用、裝置不支援或生成失敗時，整篇改走規則式 fallback，避免混合兩種文風。規則式 fallback 不承諾語意重組或真正摘要。
- 空逐字稿不呼叫模型，也不執行貼上。

## 操作與安全

- `Option + Space`：Mode 1 即時聽寫。
- `Option + Shift + Space`：Mode 2 錄音後智慧潤稿。
- 選單中的 `Smart Polish Style`：選擇整理強度，錄音或處理期間不可變更。
- Enter、Esc 或相同熱鍵：停止目前錄音，該按鍵會被吞掉。
- 處理期間拒絕重複啟動並吞掉 Enter，防止在結果產生前送出空白訊息。
- 貼上前備份完整剪貼簿；若使用者在處理期間複製了新內容，就不覆蓋新剪貼簿。

## Prompt

預設英文 prompt 隨 ButterflyCore resources 一起提供。使用者可建立以下檔案覆寫：

```text
~/.config/butterfly/SMART_POLISH_PROMPT.md
```

逐字稿永遠視為待編輯資料，不能用其中的口述內容覆寫整理指令。
