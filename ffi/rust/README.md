# ez_dbengine Rust FFI 模組

本模組提供 `ez_dbengine` 高效能 C 核心引擎的標準 Rust 封裝，遵循 Rust 的安全型別、生命週期管理與 RAII 原則，並提供多執行緒基準壓測程式。

---

## 📁 目錄結構

```text

ffi/rust/
├── build_windows.bat           # Windows 一鍵編譯腳本 (產出至 run_win)
├── build_linux.sh              # Linux 一鍵編譯腳本 (產出至 run_linux)
├── run_win/                    # Windows 執行目錄 (ez_dbengine.dll + ez_stress_master.exe)
├── run_linux/                  # Linux 執行目錄 (libez_dbengine.so + ez_stress_master)
├── Cargo.toml                  # Cargo 專案設定檔
├── build.rs                    # 跨平台動態庫與符號鏈結腳本
├── README.md                   # 模組使用說明
└── src/
    ├── ez_dbengine.rs          # 核心 SDK 封裝 (底層 C-FFI + Safe RAII 物件封裝)
    ├── ez_db_adapter.rs        # 業務適配層 (Shared Instance 句柄池 + RwLock 快取)
    └── main.rs                 # 多執行緒分桶壓測主程式
```

## ⚙️ 環境需求
PHP 呼叫原生動態函式庫需啟用 PHP 原生內建的 FFI 擴充。

* Rust 工具鏈（Rust 1.70+，含 cargo）
* 已編譯完成的核心動態函式庫：
* **Windows：** ez_dbengine.dll 與 ez_dbengine.lib
* **Linux：** libez_dbengine.so

## 核心設計與角色分工

**ez_dbengine.rs (無狀態單例驅動)：**

* 透過 EzDbEngine::global() 存取，所有 CRUD 與導航 API 顯式接收 handle: u64。

* 完全無狀態，不隨意 Drop 關閉底層 WorkArea。

**ez_db_adapter.rs (業務適配層)：**

* 專為 Axum / Actix-web 設計，以 RwLock<HashMap<String, u64>> 快取開啟過的資料表 Handle。

**main.rs (驅動極限壓力測試)：**

* 使用 4 個原生 std::thread 執行緒，共用同一組 Handle 發起原子寫入測試。


## 🚀 一鍵建置與執行


**Linux 環境：**
```text
cd ffi/rust
chmod +x build_linux.sh
./build_linux.sh

# 執行壓測
cd run_linux
./ez_stress_master
```
**Windows 環境：**
```text
cd ffi\rust
build_windows.bat

:: 執行壓測
cd run_win
ez_stress_master.exe
```

## 💡 架構特點
* **Safe Rust RAII 管理：** EzDbEngine 實作了 Drop 特徵，當實例離開作用域時會自動呼叫底層 ez_db_close()，保證無記憶體與 Handle 洩漏。

* **分發隔離與自包含執行：** 編譯完成後，二進位檔與對應的動態函式庫統一收斂在 run_linux/ 與 run_win/ 中，開箱即用。

* **零不安全程式碼外溢：** 所有 unsafe 裸指標操作皆嚴密封裝在 src/ez_dbengine.rs 內部模組，上層呼叫端直接操作強型別的 Result 與結構體。