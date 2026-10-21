# ez_dbengine Python FFI 模組

本模組提供 `ez_dbengine` 高效能 C 核心引擎的標準 PHP FFI 綁定與物件導向封裝，並提供命令列（CLI）與網頁儀表板（Web UI）兩種壓測與整合驗證工具。

---

## 📁 目錄結構

```text
ffi/python/
├── ez_dbengine.py              # 核心 SDK 封裝（ctypes 綁定 + 物件導向抽象）
├── ez_db_adapter.py            # 業務適配層 (Shared Instance 句柄池 + 欄位自動映射)
├── test_ez_stress.py           # 壓測主程式（直接 import ez_dbengine）
├── daily_2026-03-19.csv        # 基準測試資料來源
├── build_linux.sh              # 快速環境準備腳本（自動確保 .so 與資料就位）
├── build_windows.bat           # 快速環境準備腳本（自動確保 .dll 與資料就位）
└── README.md                   # 模組使用與說明

```

## ⚙️ 環境需求
* Python 3.8+（內建標準庫 ctypes，無需安裝第三方 pip 套件）
* 已編譯完成的核心動態函式庫（Windows 為 ez_dbengine.dll，Linux 為 libez_dbengine.so）


## 核心設計與角色分工

**ez_dbengine.py (無狀態單例驅動)：**

* 透過 EzDBEngine.get_instance() 取得常駐實體，所有 API 顯式傳入 handle。

* 完全無狀態，支援多 Worker 同時向同一個 Handle 進行原子寫入。

**ez_db_adapter.py (業務適配層)：**

* 專為 FastAPI / Flask / Celery 設計，快取 table_name -> handle，避免每個 Request 重複 open/close。

**test_ez_stress.py (驅動極限壓力測試)：**

* 直接操作 EzDBEngine 單例並傳遞 Handle 進行 4-Thread 壓力測試，不經由業務適配層。

## 🚀 執行與測試方式
* **1. 一鍵環境準備（自動同步動態庫與測試資料）**
* Linux:
```text
cd ffi/python
./build_linux.sh
```
* Windows:
```text
cd ffi\python
build_windows.bat
```
* **2. 執行壓力測試** 
```text
python3 test_ez_stress.py
```

## 💡 架構特點
* **零第三方依賴：** 完全採用 Python 內建的 ctypes 模組，不需依賴 Cython 或額外安裝套件。

* **原生記憶體自動管理：** 透過 Python 的 with EzDBEngine(...) 上下文管理器與析構函數（__del__），自動管理底層 C WorkArea 的關閉與資源釋放。

* **全 UTF-8 與緊密對齊：** 所有字串結構嚴格走 UTF-8 編碼與 1-Byte 結構對齊，防止跨平台記憶體位移與亂碼問題。

```text

### 清理指令建議

終端機停在 Linux 時，可以直接在 `ffi/python` 下執行以下指令將多餘的舊目錄與副本清除：

cd /home/bear/ez_dbengine/ffi/python
rm -rf debug release
rm -f ez_engine.h ez_relation_mgr.h ez_dbengine.lib
  
```