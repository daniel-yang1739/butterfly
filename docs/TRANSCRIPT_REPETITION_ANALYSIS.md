# 逐輪轉錄重複累積分析

> 以下「已確認的兩個問題」記錄修正前的行為。目前已完成音訊分段與游標修正；實作及驗證見文末「本次實作」。

本次分析直接呼叫目前的 `TranscriptAccumulator` 與 `InputInjector.prepareStreamingDelta`，重播人工設計的多輪視窗。沒有錄音、沒有呼叫 Whisper，也沒有向任何視窗送出鍵盤事件。這能證明程式存在錯誤路徑，但不能判定使用者那次錄音每一個重複詞的來源。

## 已確認的兩個問題

### 1. 音訊重疊，但文字對齊失敗時，保留了兩份內容

`TranscriptAccumulator.appendSlidingWindow` 只用樣本範圍判斷是否重疊，再尋找舊視窗尾端與新視窗開頭的文字匹配。正規化能處理部分標點、空白及大小寫，不能處理辨識用詞改變。

找不到匹配時，程式會把整個舊視窗加入不可修改的 `committedSlidingText`，再接上整個新視窗。這把「無法確定哪些文字重疊」當成了「文字都應該保留」。後續更新只處理新的 active window，先前重複的內容便無法被更正。

重播使用 16 kHz、5 秒視窗，每次前進 2.5 秒：

| 輪次 | 視窗輸入 |
| --- | --- |
| 1 | We need to check the supported components |
| 2 | the available components include databases and queues |
| 3 | database and queue services need isolated test environments |

第二輪開始出現語意重複，第三輪再增加一次，實際合併結果為：

```text
We need to check the supported components，the available components include databases and queues，database and queue services need isolated test environments
```

每個視窗本身都沒有重複句。對照組使用完全相符的重疊文字，能合併成一份連續內容。這證明累積重複可以由合併器產生，不需要先假定 Whisper 在單輪輸出中重複。

### 2. 超過 25 字的修正，以字數差補字會破壞內容

`InputInjector.prepareStreamingDelta` 在需要刪除超過 25 個字元時，不再依共同前綴替換；若新文字較長，只取長度差對應的新尾端補上。字數相同或較短則不更新。

重播先輸入：

```text
We need to check all supported components before starting the integration tests.
```

接著要求修正成：

```text
We should check all supported components before starting the integration tests today.
```

實際動作卻是 `append("oday.")`，模擬游標結果為：

```text
We need to check all supported components before starting the integration tests.oday.
```

再次送入同一份修正版會得到 `noChange`，所以「重送不會再次注入」雖然成立，錯誤內容卻仍存在。驗證 bookkeeping 與模擬按鍵一致，也不足以證明它們與辨識結果一致。

## 尚未證實的部分

- 單次 Whisper 輸出是否已包含重複，需要實際音訊與逐輪 raw transcript。
- 真實目標應用程式是否完整接收刪除與輸入事件，離線模擬無法確認。
- 這次證明的是重複逐輪累積，並未證明指數成長或模型被重複文字持續回饋。C bridge 設定 `no_context = true`；不能把文字累積直接解釋成模型上下文的回饋迴圈。
- live stream 會先經過 `TextPolisher` 再合併；本次重播直接提供合併器輸入，沒有覆蓋這一層。

## 是否應該關閉 overlap？

目前不建議直接關閉。那會移除跨窗去重的需求，但不能解決同一視窗修正時的游標錯誤，也不能解決單輪辨識本身的重複。切割點的詞句缺少跨窗音訊上下文，是需要用真實音訊評估的另一項代價。

另外，目前的 50% overlap 是觸發門檻，不是每次推論都保證前進 2.5 秒。引擎每輪取最新 5 秒音訊，實際前進距離受推論時間、輪詢及語音活動條件影響。

## 建議修正方向

1. 區分暫定文字與已確認文字，不要在重疊對齊失敗時直接把整個舊視窗永久提交。無法對齊的區域應保留待確認，透過下一輪結果或涵蓋該區域的音訊重新辨識來解決。
2. 為跨窗對齊保留 segment/token 的時間資訊與音訊的絕對時間。現有 C bridge 使用 `no_timestamps = true`、`single_segment = true`，回傳文字不足以直接判定每個字屬於哪段重疊音訊。時間資訊仍需驗證準確度，不能假定它能完全解決所有邊界問題。
3. 移除字數差猜測補字的策略。明確決定游標只提交穩定文字，或允許替換可管理的暫定尾段；這牽涉即時性與修正能力的取捨，不能單純把 25 改成更大的數字。
4. 補上可選的逐輪診斷：音訊樣本範圍、raw transcript、格式化後文字、合併結果、delta 動作。使用者提供的真實案例才能分辨辨識、格式化、合併、注入四層的責任。

以上是分析階段的候選方向。最終實作選擇固定起點的音訊分段，見下節，沒有加入 token 時間戳或模糊語意去重。

## 本次實作

- `DictationAudioBuffer` 保持每段音訊的起點不動；新音訊加入同一段，再辨識時修正的是整段暫定結果。
- 連續約 600 ms 低於既有語音活動門檻時結束該段；沒有偵測到停頓時，每段最多 20 秒。不同段不共享音訊樣本。這與單純把原本 sliding 的 overlap 設為零不同：段內仍保留先前完整音訊上下文，直到該段結束。
- 第一份暫定結果至少累積 1 秒音訊；後續暫定結果至少新增 2.5 秒才推論。停頓及停止錄音的最終結果不受最低長度門檻限制。
- 以音訊起點作為段落識別碼，呼叫 `TranscriptAccumulator.updateSegment`。同段覆寫暫定內容，新段才提交舊段；不再呼叫正式錄音流程原先的 `appendSlidingWindow` 文字對齊方法。舊 API 保留相容性，但不負責目前的麥克風串流流程。
- 音訊依序處理，只有完成辨識的封閉段才從待處理佇列移除。推論進行時新增的音訊不會被舊 snapshot 的完成通知刪除。停止錄音會封閉最後一段，依序處理剩餘段落；推論失敗時回報既有錯誤，不無限重試。
- 游標更新採共同前綴後的完整尾段替換。移除「超過 25 字不修正／按長度差追加」；較短、等長、較長及空字串修正都能同步預期游標內容。

取捨：長段落推論可能比原本 5 秒視窗慢，長句修正可能有可見的刪除與重輸入。20 秒上限可能切在詞句中間，需要真實錄音評估邊界辨識品質。語音活動仍使用既有 RMS 門檻；未偵測到的輕聲不能由這些測試保證辨識成功。推論長期慢於錄音時，待處理音訊佇列可能增長，而不是靜默丟棄未辨識的音訊。單次模型輸出本身的重複並未使用全句刪除規則處理，以保留使用者刻意的重複。

驗證：App 與 CLI 可建置；CLI 100 項 assertions 與離線回歸 42 項檢查全部通過。涵蓋同段多輪改寫、長句縮短、等長及空字串修正、重送冪等性、不同段刻意重複、停頓與短句結尾、慢速辨識及多段音訊樣本完整性。另新增 XCTest 案例，但此機執行 `swift test` 時缺少 `XCTest` 模組，因此未能執行該套件。這些是人工輸入的程式回歸，沒有量測真實錄音的重複率。

## 重播方式

在 repository 根目錄執行：

```bash
swiftc -module-cache-path /tmp/butterfly-replay-module-cache \
  Sources/ButterflyCore/Audio/DictationAudioBuffer.swift \
  Sources/ButterflyCore/Text/TranscriptAccumulator.swift \
  Sources/ButterflyCore/Injector/InputInjector.swift \
  Scripts/replay-transcript.swift \
  -o /tmp/butterfly-transcript-replay
/tmp/butterfly-transcript-replay
```

這不會重新建置或簽署 `.build/app/Butterfly.app`，不會修改 Accessibility 授權。腳本目前檢查修正後的行為；任一條件不符時會失敗退出。
