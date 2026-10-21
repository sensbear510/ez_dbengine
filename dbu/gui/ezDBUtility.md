# 📄 ezDBUtility.md - 完整 UI/UX 設計協議規範 (Final Complete Protocol)

> **專案定位**：基於 Flutter 的跨平台（Windows, Linux, macOS, iOS, Android, Web）視覺化巨量資料庫維護工具，透過 `ez_dbengine.dart` API 驅動微秒級 I/O 資料操作。

---

## 🏛️ 1. 專案邊界與 API 依賴 (API Boundary)

1. **應用程式邊界 (Client-Only Scope)**：
  * `dbu/gui` 不包含、不延伸、也不維護 ez_dbengine (`source/`) 的內部實現。
  * **單一對接點**：所有資料庫讀寫、Seek 尋找、`ez_dbrowreplace` 原子覆蓋與 `ez_dbzap` 軟刪除操作，**100% 透過引入 `/ffi/flutter/lib/ez_dbengine.dart` 完成**。
  * **需可完全達成 xBase DBU 的操作功能**。
  * **引擎名稱 : ezDBEngine**。
  
2. **漸進式 App 開發哲學 (MVP First)**：
  * 初期專注於「簡潔、穩定、極速、低記憶體消耗」的維護體驗。
  * 提供把資料匯出至 Excel / CSV / Json 處理。
  * 套件引用版本固定 不使用 ^ 做版本號。

3. **程式開發規則 (Implement develop rules)**：
  * AI 需根據 `/dbu/gui/lib/service/ez_dbengine.dart` 所封裝的API 來操作資料庫引情 ez_dbengine
  * AI 所有的code 註解 使用 專業英文 溝通用中文
  * AI 須依據現有程式邏輯 進行調整 無必要不得刪除 或自行腦補 無端猜測 創立毫無根據的方法  
  * 編碼規範 成員變數 需有 m_+type+變數名稱 
  * 規範好 Widget 的 Key 值 和 上下關係
  * 對於 deprecreated 的 function 不可使用
  * 結構性邏輯+物件導向 思考 
  * 產生程式碼 註解使用英文 且不的刪除原有代碼的 註解
  * AI 提供修正建議 不要使用行號導航 因編輯環境不同 導製無效
  * 因為是多國語言 所有的 flutter 輸出文字階用 m_language.getValue()替代 並提工 zh_TW, en_US .json 增補KEY 
  * 不要盲目猜測 腦補 可以提示提供原始碼供參考 

  
---

## 🎨 2. UI/UX 視覺主題與色彩系統 (Theme & Palette System)

全平台採用 **「深色與亮色系工匠質感 (Craftsman Dark Precision)」 雙主題**，兼顧高對比度視覺辨識與長時間維護資料的眼部舒適度：

### 2.1 色彩代碼規範
* **基底背景色 (Dark Steel Backgrounds)**：
  * 主背景 (`#121110`)：極致深灰褐色，用於視窗底層。
  * 卡片/面板 (`#1E1C1A`)：次級區塊與 DataGrid 奇數列。
  * 標頭/導覽列 (`#25221F`)：頂部與底部固定導覽列底色。
  * 邊框分隔線 (`#38332E` / `#4A443D`)：極細工匠質感分隔線。
* **強調色 (Accent Colors)**：
  * **黃銅金 (Brass Gold, `#D4AF37`)**：作用中 Active 狀態、Key 主鍵識別、導向高亮、重點 Icon。
  * **暖琥珀 (Warm Amber, `#E6A15C`)**：一般 Seek 欄位、非 Key 索引識別。
  * **工匠棕 (Craftsman Brown, `#8C5A2B`)**：主要執行按鈕（Seek / Export）預設色。
* **資料狀態色 (Status Indicators)**：
  * 🟢 **已同步/正常 (`#4CAF50`)**：資料與硬碟 IO 正常同步。
  * 🔴 **標記刪除/Zap (`#E53935`)**：被 `ez_dbzap` 標記為刪除的列（帶著淡紅背景與刪除線）。
  * ⚪ **空值/Empty (`#6B6357`)**：Null、Empty 槽位或無資料標記。
* **回歸 Theme 為系統 顏色 圖像 字型 最高管理 元件**
  

---。。。。。。。。。。。。。。。。。。。

## 🖼️ 3. 跨平台 SVG 向量 Icon 規範 (SVG Vector Standard)

為了確保在 4K/8K 桌面高 DPI 螢幕（Windows High-DPI, macOS Retina display）以及各式行動裝置螢幕上都能呈現 **0 像素化、銳利清晰的線條**，Icon 採用嚴格的向量規範：

1. **全面 SVG 化 (Vector First)**：
  * 所有 UI Icon 優先採用 SVG 向量格式（放置於 `assets/icons/`）。
2. **渲染相容性與鎖定**：
  * 透過精準鎖定版本的 SVG 解析元件進行渲染，確保在 6 大平台（包含 Web WebGL / WASM Canvas）上渲染出的向量路徑 100% 一致。
3. **動態著色 (Dynamic Tinting)**：
  * SVG Icon 源檔統一保持單色向量路徑（`fill="currentColor"`），在 Flutter 端直接透過 Theme 的 `Color` 進行動態著色（如預設灰階 `#8C8275`，Hover/Active 自動轉為黃銅金 `#D4AF37`）。

---

## 🧭 4. 全平台導覽列與操作機制 (Navigation Bar & Operations)

採用 **「桌面導航列 (Top MenuBar) ↔ 行動大拇指熱區 (Bottom Dock)」** 雙軌自適應設計：

```text
 🖥️ Desktop / Web Mode (>= 1024px)
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 📌 MenuBar:  [ 📂 檔案 ]   [ 🔍 尋找 ]   [ 🛠️ 工具 ]   [ 🌐 語系 ]    │
 ├────────────────────────────────────────────────────────────────────────┤
 │ 📌 Fixed EBF Header ┊ 🔄 8-Slot EDX Carousel Ribbon (Horizontal Scroll)│
 └────────────────────────────────────────────────────────────────────────┘

 📱 Mobile / Tablet Mode (< 1024px)
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 📌 Compact Top Bar: 📂 customers.ebf ┊ 🔑 TAG_ACC_KEY (Slot 3)        │
 ├────────────────────────────────────────────────────────────────────────┤
 │ [ Scrollable Card List / Compact Data Grid                           ] │
 ├────────────────────────────────────────────────────────────────────────┤
 │ 📌 Bottom Navigation Dock: [ 📂 開檔 ] [ 🔍 SEEK ] [ ➕ 新增 ] [ ⚙️ 設定 ]│
 └────────────────────────────────────────────────────────────────────────┘
```

### 4.1 桌面端 (Desktop MenuBar Flow)
* **視窗頂部選單列 (System MenuBar)**：
  * `檔案 (File)`：開啟 `.ebf`、關閉檔、匯出 (`Export to...`)、離開。
  * `尋找 (Seek)`：跳轉 Seek Bar (`Ctrl+F`)、尋找下筆 (`F3`)、前筆 (`Shift+F3`)。
  * `工具 (Tools)`：`[🧹 PACK 資料庫清理]`、`[📦 Binary Inspector]`。
  * `語系 (Language)`：動態切換 `zh_TW` / `en_US` / `ja_JP`。
* **鍵盤流導向熱鍵 (Keyboard Navigation)**：
  * `Tab` / `Shift+Tab` ──► GridView 單元格流暢切換。
  * `Ctrl + F` (Mac: `Cmd + F`) ──► 焦點直接拉回 Smart Seek Bar。
  * `F3` ──► Duplicate Key 模式下直接尋找下一筆 matching record。
  * `Ctrl + C` ──► 複製選取列為 TSV 文字（直接貼上 Excel）。

### 4.2 行動端 (Mobile Navigation Dock & Gestures)
* **底置大拇指熱區 (Bottom Navigation Dock)**：
  * 將最高頻動作（開檔、Seek 抽屜、新增、設定）固定在螢幕最下方的 48px 區域，單手大拇指即可極速操作。
* **手勢操作 (Gesture Operations)**：
  * **水平滑動 (Horizontal Swipe)**：於頂部 EDX 區塊滑動切換 1~8 索引槽位。
  * **卡片左滑 (Swipe to Zap)**：在 Card 列表上向左滑動直接觸發 `ez_dbzap` 軟刪除，帶有紅底刪除圖示與 `HapticFeedback.mediumImpact()` 物理震動回饋。
  * **長按 (Long Press)**：彈出快速操作選單（複製、編輯、檢視 Type B 二進位檔）。

---

## 📐 5. 頂部雙區列與 Smart Seek Bar 規範

### 5.1 頂部雙區列 (Header Shell)
* **左側：固定錨定區 (Fixed EBF Anchor 📌)**
  * **永遠置頂固定**（不隨索引滾動移位）。
  * 呈現：`📂 主檔名.ebf`、`總筆數`、`Sync 狀態標籤 (🟢 In-Sync)`。
* **右側：8 槽位水平滑動卡帶 (8-Slot EDX Carousel Ribbon 🔄)**
  * 最多呈現 8 個 `.edx` 索引槽位（`[1]` ~ `[8]`）。
  * 單張 Slide Item 完整顯示：`Slot 號碼`、`Tag 名稱`、`Key 組合公式`、`Unique 鑰匙/搜尋 SVG Icon`。
  * **Active 高亮**：當前作用中的 Tag 呈現黃銅金發光邊框（Brass Glow）。

### 5.2 智能尋找列 (Smart Seek Bar)
* **動態欄位變形**：依據 Active EDX Tag 的 Key 結構，自動切換為單一輸入框，或多欄位分割輸入框（組合鍵 Combined Key，支援自動定長空白補齊）。
* **運算子與算術求值 (Smart Parser)**：
  * 比較運算子：`>`、`<`、`=`、`>=`、`<=`、`<>`。
  * 算術表達式：前端 Parse 求值（如 `500 * 1.1` $\to$ `550.0`）後，呼叫 `ez_dbseek_by_tag_array` 跳轉 B-Tree 邊界。

---

## 📦 6. 二進位 (Type B) 欄位處理與 Inspector

* **FDT 屬性預先鎖定**：存取模式在建庫（Schema Level）即決定，全表一致。
  * **InField 槽位 ($\le 64\text{KB}$)**：Grid 顯示 `[📦 12.4 KB / 16 KB Used]`。
  * **ZBF 側掛槽位 ($> 64\text{KB}$)**：Grid 顯示 `[📎 4.2 MB in .zbf #0042]`。
* **Binary Inspector (側滑抽屜)**：
  * **Magic Bytes 自動偵測**：PNG/JPG/PDF 自動彩現預覽，其他格式呈現 16 進位 Hex Viewer。
  * 提供「另存實體檔案」與「選擇新檔寫回覆蓋」功能。

---

## 🌐 7. 獨立 JSON 多語系檔與 UTF-8 編碼規範

1. **獨立語系檔 (Per-Locale INI Files)**：
  * 按 Locale Code 獨立拆分，存放於 `assets/lang/`：
    * `assets/language/zh_TW.json` (繁體中文)
    * `assets/language/en_US.json` (英文)
  * **全專案強制 UTF-8 (Without BOM)** 格式。
2. **GUI 載入機制**：
  * 啟動時讀取 `.json` 並解析為 Map，提供 `Lang.get('KEY')` 全局調用，支援動態無縫切換語系。
3. **匯出 CSV 編碼**：
  * 匯出 CSV 時補上 **UTF-8 BOM (`0xEF, 0xBB, 0xBF`)**，確保 Excel 雙擊開啟繁體中文 100% 無亂碼。

---

## 📦 8. 套件管理與版本鎖定規範 (Dependency Lock Standard)

1. **嚴禁使用 `^` (Caret) 浮動版本號**：
  * 在 `pubspec.yaml` 裡面的所有第三方套件，**必須 100% 使用「精準固定版本號」**。
  * **正確範例**：`ini: 2.1.0`
  * **錯誤範例**：`ini: ^2.1.0`（嚴禁使用！）
  * **目的**：避免背景升級帶來的 Break Changes 與跨 6 平台編譯衝突，杜絕維護地獄。
2. **極簡套件依賴原則**：
  * 優先採用 Flutter 原生 Framework 提供的組件與工具，降低對外部 Package 的依賴。

---

## 🧩 9. Plug-in 預留生命週期介面 (Lightweight Plugin Hooks)

初期**不預載任何實體外掛**，僅在系統中保留標準的 4 個生命週期鉤子與登記總線（Plugin Registry）：

```text
 [ 登記 Register ] ──► [ 載入 Load ] ──► ( 運作中 ) ──► [ 解登 Unregister ] ──► [ 卸載 Unload ]
```

 **跨平台遵從約束**：未來所有接入的外掛必須宣告支援的平台集合 (`Set<TargetPlatform>`)，且介面自動對不支援當前 Runtime 的外掛進行優雅隱藏，確保 6 大平台 UX 體驗連貫一致。

 
/* ====================================================================================== */
/*           PROTOCOL ENFORCEMENT CHECKLIST (100% VERIFIED)                               */
/* -------------------------------------------------------------------------------------- */
/* 1. LANGUAGE ISOLATION : Internal Comments [100% EN] | Chat or Communication  [100% ZH] */
/* 2. ABI LAYOUT AUDIT   : Checked with target mode's official kernel spec?               */
/* 3. HARDWARE ALIGNMENT : Vectorized Stride & Byte-granular calculation?                 */
/* 4. BASIC CODE LOGIC   : Inference protocol                                             */
/* 5. SOURCE INTEGRITY   : Refactor/Patch strictly based on existing code; NEVER          */
/*                         hallucinate non-existent symbols. NO unauthorized omission or  */
/*                         deletion of code/original comments. Any deprecation MUST be    */
/*                         commented out and explicitly marked.                           */
/* 6. CODE COWORK        : Provide correction suggestions. Do not use line number         */
/*                         navigation. Due to different editing environments,             */ 
/*                         this may not work.                                             */
/* 7. OUTPUT TEXT        : Because it's multilingual, all Flutter output text is replaced */
/*                         with `m_language.getValue()`, and the `zh_TW` and `en_US`.json */
/*                         files are supplemented with keys.                              */
/* ====================================================================================== */