# Butterfly 測試計畫與邏輯測試矩陣 (Test Plan & Test Matrix)

## 1. 測試理念 (Testing Philosophy)

為防止在 Butterfly 新增功能、升級模型或重構架構時造成既有核心邏輯的迴歸損壞（Regression），我們建立了全方位的 26 項核心邏輯測試矩陣。所有繁簡轉換、排版、兩輪認知意圖重構、數字/單位標準化、動態提示詞、白名單與鍵盤注入均有嚴格的自動化斷言保護。

---

## 2. 邏輯測試案例矩陣 (26 Core Logic Assertions)

### 📦 Suite 1：繁簡轉換與語言過濾測試 (`OpenCCTranslator`)
- **TC-A1**：純簡體字轉換（`"这是语音识别测试"` $\rightarrow$ `"這是語音識別測試"`）
- **TC-A2**：台灣慣用詞彙適配（`"服务器内存不足"` $\rightarrow$ `"伺服器記憶體不足"`）
- **TC-A3**：中英混雜語音轉換（`"请帮我review这段React代码"` $\rightarrow$ `"請幫我 review 這段 React 程式碼"`）
- **TC-A4**：純英文大小寫與符號保留（`"git checkout -b feature/butterfly --quiet"`）
- **TC-A5**：零簡體殘留斷言（`assert(!containsSimplified(output))`）

### 📦 Suite 2：文字格式化與數字/單位標準化測試 (`TextFormatter`)
- **TC-B1**：中英混排盤古之白自動補空格（`"建立一個React組件與10個API端點"` $\rightarrow$ `"建立一個 React 組件與 10 個 API 端點"`）
- **TC-B2**：口語大寫數字轉阿拉伯數字（`"八百多 MB... 兩千行程式碼第 1 點"` $\rightarrow$ `"800 多 MB... 2000 行程式碼第 1 點"`）
- **TC-B3**：口語數據與公制度量單位縮寫標準化（`"500 Mega bite... 2 Tara bite... 5 kilogram"` $\rightarrow$ `"500 MB... 2 TB... 5 kg"`）
- **TC-B4**：口語開頭結巴重複代名詞過濾（`"我我我覺得這這這個可以"` $\rightarrow$ `"我覺得這個可以"`）

### 📦 Suite 3：兩輪認知意圖重構引擎測試 (`TextPolisher`)
- **TC-C1**：Mode 1 全音素泛化還原（`"切換到 沒ode 1 試試看 茂 the one 模式"` $\rightarrow$ `"Mode 1"`）
- **TC-C2**：Mode 2 全音素泛化還原（`"試試看 茂 t 與 冒著吐兔 以及 貓的兔 的結果"` $\rightarrow$ `"Mode 2"`）
- **TC-C3**：System Prompt 全音素模糊還原與尾音自癒（`"sister Prom"`, `"sister from"`, `"season Pro"`, `"To Pro"`, `"System Promptpt"` $\rightarrow$ `"System Prompt"`）
- **TC-C4**：Context 上下文語境定向（`"看到上下文這個字，所以知道要翻成 contact"` $\rightarrow$ `"翻成 Context"`）
- **TC-C5**：文件與架構關鍵字自癒（`"Varun"` $\rightarrow$ `"README"`, `"A DM D R"` $\rightarrow$ `"AGENTS.md"`, `"Source Coded"` $\rightarrow$ `"Source Code"`）
- **TC-C6**：Mode 1 即時串流忠實性保證（自然重複詞 `"測試測試"` 與標點符號 `"，。？"` 100% 完整保留，零刪字）
- **TC-C7**：Mode 2 深度口吃與重啟句消除（`"好我們來，好我們來測，好，我們來測試一下"` $\rightarrow$ `"我們來測試一下"`）
- **TC-C8**：Mode 2 Markdown 智慧列點結構化提取（`"第一點是... 第二點是..."` $\rightarrow$ `"- 第 1 點是...\n- 第 2 點是..."`）
- **TC-C9**：Mode 2 長篇獨白全句去重複（消除 3 次連續重複錄音句子）
- **TC-C10**：語意意圖與同音字上下文校正（`"好的認識"` $\rightarrow$ `"好的潤飾"`, `"羽翼"` $\rightarrow$ `"語意"`, `"把蚊子"` $\rightarrow$ `"把文字"`）

### 📦 Suite 4：系統提示詞動態載入測試 (`SystemPrompt`)
- **TC-D1**：`SYSTEM_PROMPT.md` 磁碟動態載入驗證
- **TC-D2**：Butterfly 提示詞角色與規則完整性驗證

### 📦 Suite 5：模型白名單與硬體偵測測試 (`ModelManager`)
- **TC-E1**：模型白名單排序優先級（Rank 1 為 `Whisper Large-v3-Turbo`）
- **TC-E2**：模型檔案大小格式化驗證
- **TC-E3**：本機可用模型自動探測（`getBestAvailableModel()`）

### 📦 Suite 6：游標注入增量計算測試 (`InputInjector`)
- **TC-F1**：即時串流正向追加增量計算（`"你好"` $\rightarrow$ `"你好世界"`）
- **TC-F2**：即時串流退格就地微調增量計算（`"你好是界"` $\rightarrow$ `"你好世界"`）

---

## 3. 測試執行方式 (How to Run Tests)

```bash
# 執行所有 26 項核心邏輯單元測試
swift run butterfly-cli test
```
