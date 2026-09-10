# 自訂 Smart Polish Endpoint

建立 `~/.config/butterfly/butterfly.json`。沒有設定檔時，維持 Apple Foundation Models 與本機 rules fallback。

Repo 根目錄的 [`butterfly.json`](../butterfly.json) 提供自訂 AI provider 與 Ollama 模型的範本，預設仍使用本機 Apple Foundation Models。App 不會自動讀取 repo 裡的檔案；請將它複製到上述使用者設定路徑，並設定自己的 endpoint 與 API key 環境變數。範本的 `gpt-5.6-terra` 包含 reasoning、variants 與 token limit 設定。

```json
{
  "polish": {
    "defaultModel": "my-gateway/team/polish-model",
    "fallback": "rules"
  },
  "provider": {
    "my-gateway": {
      "name": "My AI Gateway",
      "type": "openai-compatible",
      "options": {
        "baseURL": "$BUTTERFLY_BASE_URL",
        "apiKey": "$BUTTERFLY_API_KEY",
        "timeoutMs": 30000,
        "headers": { "X-Client": "Butterfly" }
      },
      "models": {
        "team/polish-model": {
          "name": "Polish Model",
          "chunkCharacterLimit": 12000,
          "maxTokens": 4096
        },
        "fast-model": { "name": "Fast Model" }
      }
    }
  }
}
```

這是仿照 OpenCode 的 Butterfly 設定格式，並非完整相容 OpenCode。`type` 目前只支援 `openai-compatible`；模型的 `api` 預設為 `chat-completions`，使用 `POST <baseURL>/chat/completions`。設定 `api: "responses"` 則使用 `POST <baseURL>/responses`。不支援原生 Anthropic API 或 npm adapter。

`models` 的 key 必須是伺服器接受的 model ID，可以包含 `/`。`polish.defaultModel` 第一個 `/` 前為 provider ID，其餘為完整 model ID。內建本機 provider 為 `local`，提供 `local/foundation`（Apple Foundation Models，預設）和 `local/rules`（規則式潤飾，非 AI 模型），不需要填入 endpoint。舊設定的 `apple/foundation`、`builtin/rules` 仍可讀取，會分別對應至這兩個本機選項。舊版 `polish.model` 也會相容讀取；新設定請使用 `defaultModel`。請勿將內建模型 ID 用於自訂 endpoint。

App 的 **Smart Polish Model** 選單只列出各 provider 的模型／潤飾選項。每次啟動使用 JSON 的 `polish.defaultModel` 作為預設；在選單選取其他模型只會暫時覆寫目前執行期間的選擇，不會寫入含有 endpoint 或金鑰的 JSON。重新啟動或使用 **Reload Polish Configuration** 後會回到設定檔的 `polish.defaultModel`。每次開始 Smart Polish 錄音也會重新載入設定，錄音途中修改檔案不會改變該次使用的 endpoint。

CLI 使用相同檔案：

```sh
swift run butterfly-cli test-polish --smart --style concise "Please polish this transcript."
```

URL、金鑰與 header 值支援完整字串形式的 `$VARIABLE_NAME`、`${VARIABLE_NAME}` 與既有的 `{env:VARIABLE_NAME}`。缺少變數會回報設定錯誤。App 從 Finder 啟動時不一定繼承 shell 的環境變數；第一版尚未整合 Keychain。設定也接受直接填入金鑰，請勿把含金鑰的檔案加入版本控制。

本機相容伺服器可以使用 `http://127.0.0.1:1234/v1` 並省略 `apiKey`；其他主機須使用 HTTPS。HTTP redirect 不會自動跟隨。選擇 endpoint 後，逐字稿與潤飾指令會送往該伺服器，此功能不會上傳音訊。選單的 Configured 只表示本機設定有效，並不代表已成功連線。

網路 timeout、HTTP 錯誤、空回應或輸出截斷會使用本機 rules fallback；CLI 會顯示原因。設定錯誤則停止執行，讓使用者修正。取消不會觸發 fallback 或貼上文字。

`timeoutMs` 預設 30000，最大 300000，限制每次請求；長文可能包含多次請求，並非整次潤飾的總時限。`chunkCharacterLimit` 預設 12000，是字元數而非 token 數，需替 system prompt 和輸出預留模型容量。Structured Notes 與 Summary 長文會先分段準備，再做整體整理；遇到伺服器的 `context_length_exceeded` 會遞迴切分，極長文件的跨段一致性仍受模型容量限制。

## Reasoning、variants 與容量限制

模型可設定以下欄位；範本已替 `gpt-5.6-terra` 加入這組設定：

```json
{
  "name": "GPT-5.6-terra",
  "api": "responses",
  "reasoning": true,
  "interleaved": true,
  "defaultVariant": "xhigh",
  "variants": {
    "xhigh": {
      "reasoningEffort": "xhigh",
      "textVerbosity": "low",
      "reasoningSummary": "auto"
    }
  },
  "limit": { "context": 512000, "output": 65536 }
}
```

`defaultVariant` 明確選擇要使用的 variant；省略時不送出 variant 參數，不會自動選第一筆。App 與 CLI 都使用所選模型的 `defaultVariant`，目前沒有獨立的 variant 選單。

| 設定 | Responses 請求 | Chat Completions 請求 |
| --- | --- | --- |
| `reasoningEffort` | `reasoning.effort` | `reasoning_effort` |
| `textVerbosity` | `text.verbosity` | `verbosity` |
| `reasoningSummary` | `reasoning.summary` | 不支援，選中的 variant 含此欄位時回報設定錯誤 |
| `maxTokens`，未填時使用 `limit.output` | `max_output_tokens` | reasoning 模型使用 `max_completion_tokens`，其他模型使用 `max_tokens` |

參數對應依據 [OpenAI 模型參數指南](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.2) 與 [Responses API 文件](https://developers.openai.com/api/reference/typescript/resources/beta/subresources/responses/methods/create)。各 gateway／模型是否支援這些參數仍由伺服器決定；請確認自己的 endpoint 支援 `/responses`。若 gateway 只有 Chat Completions，請將 `api` 改為 `chat-completions` 並移除選中 variant 的 `reasoningSummary`。不會在錯誤後自動移除參數重送。

`reasoning` 和 `interleaved` 是能力描述，不會作為同名欄位送到 API。`reasoning: false` 與選中的 reasoning 參數衝突時會報錯。`interleaved` 只保存 metadata；Butterfly 是單次文字潤飾，沒有工具呼叫或交錯推理流程。Responses 只取 assistant 的 `output_text`，不會將 reasoning summary 貼入文字框，並送出 `store: false`。

`limit.context`／`limit.output` 的單位是 token，並非字元。輸出預算不得超過 `limit.output`，也必須小於 context。輸入採 UTF-8 byte 數加訊息 overhead 作為保守 token 估計，再扣除輸出預算；超出時走既有分段重試。這不是模型專用 tokenizer，可能提前切分。設定容量不會改變伺服器的實際模型容量。

新增模型不會自動探測伺服器的模型清單；只要 API 協定相容，修改 `models` 即可，不需要改 Swift 程式碼。
