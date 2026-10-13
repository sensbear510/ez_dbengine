# EDB 2.0 Node.js High-Concurrency FFI Subsystem

本模組使用 Koffi FFI，對接 ez_dbengine 核心，為 Node.js 伺服器端環境提供無狀態與多工作區調度支援。

## 目錄結構說明

```text
ffi/node.js/
├── build_windows.bat           # Windows 執行腳本 (確保 DLL到位並跑測試)
├── build_linux.sh              # Linux 執行腳本 (確保 .so 到位並跑測試)
├── run_win/                    # Windows 執行目錄 (ez_dbengine.dll + 測試產物)
├── run_linux/                  # Linux 執行目錄 (libez_dbengine.so + 測試產物)
├── package.json                # npm 依賴設定 (固定 koffi 版本)
├── ez_dbengine.js              # 核心封裝模組 (Koffi FFI 宣告 + OOP 封裝)
├── ez_db_adapter.js            # 業務適配層 (Shared Instance 句柄池 + 欄位自動映射)
└── ez_stress_master.js         # 壓測主程式 (引入 ez_dbengine.js)
```

## 核心設計與角色分工

**ez_dbengine.js (無狀態單例驅動)：**

透過 EzDbEngine.getInstance() 取得常駐實體，所有 API 強制接收 handle。

不保存資料表狀態或游標，支援並行原子操作。

**ez_db_adapter.js (業務適配層)：**

專為 Express / Fastify 設計，快取 tableName -> handle，避免重複開關資料表。

ez_stress_master.js (驅動極限壓力測試)：

直接操作 EzDbEngine 單例並傳遞 Handle 壓測，不經由業務適配層。

## 執行方式

```text
node ez_stress_master.js
```

