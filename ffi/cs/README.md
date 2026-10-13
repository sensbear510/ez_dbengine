# EDB 2.0 C# (.NET) High-Concurrency FFI Subsystem

This module provides high-performance FFI interfaces and high-concurrency architecture support for the ez_dbengine native dynamic library (C-Core) under C# / .NET environments.

---

## Directory Structure

```text
ffi/cs/
├── build_windows.bat           # Dedicated Windows one-click build script (outputs to run_win)
├── build_linux.sh              # Dedicated Linux one-click build script (outputs to run_linux)
├── run_win/                    # Windows runtime environment (ez_dbengine.dll + ez_stress_master.exe)
├── run_linux/                  # Linux runtime environment (libez_dbengine.so + ez_stress_master)
├── ez_stress_master.csproj     # .NET project file
├── ez_dbengine.cs              # Core driver (Native P/Invoke declarations + EzDBEngine stateless singleton)
├── ez_db_adapter.cs            # Business adapter layer (Shared Instance handle pool + auto field mapping)
└── ez_stress_master.cs         # Core stress benchmark (direct EzDBEngine invocation + multi-threaded handle dispatch)
```

# Core Design & Architecture Roles

* 1. ez_dbengine.cs (Low-Level Stateless Singleton Driver)
Responsibility: Encapsulates all native C-API (P/Invoke) symbols, memory layout structures (EZ_FIELD_NODE, EZ_TAG_INFO), and the EzDBEngine.Instance stateless singleton.

Characteristics:
- Completely Stateless: All CRUD, navigation, and retrieval APIs require an explicit `ulong handle`; the driver itself retains no Table or Cursor state.
- Thread-Safe: Supports concurrent atomic Append and in-place Row Replace operations across multiple threads, interfacing directly with OS asynchronous queues (Windows IOCP / Linux io_uring).

* 2. ez_db_adapter.cs (Business Layer Shared Instance Adapter)
Responsibility: Designed specifically for WebAPI / SaaS (such as ASP.NET Core, microservices) data mapping and connection caching pools.

Characteristics:
- Handle Registry: Internally maintains a `ConcurrentDictionary<string, ulong>`, ensuring each table is opened only once during the process lifecycle to eliminate redundant Use/Close operations per request/session.
- Automatic Payload Packaging: Accepts high-level dictionaries (e.g., `Dictionary<string, string>`) and automatically constructs CSV payloads based on FDT schemas for atomic writes.

* 3. ez_stress_master.cs (Driver Stress Benchmark)
Note: `ez_stress_master` directly invokes `EzDBEngine.Instance` by default without going through `ez_db_adapter`.

Reason: The primary goal of the benchmark is to measure the raw throughput and hardware concurrency performance of the C-Core + FFI pipeline itself. The test runner manages 4 worker threads and passes the same `ulong handle` to each thread to verify atomic write TPS; to evaluate business-layer caching mechanisms, refer to `EzDbAdapter` instead.

# Execution Guide

* 1. Prepare Native Dynamic Libraries and Data Files
Ensure the project directory (`ffi/cs`) or output directory contains:
- `ez_dbengine.dll` (Windows) or `libez_dbengine.so` (Linux)
- `daily_2026-03-19.csv` (Real-world post-market test dataset)

* 2. Windows One-Click Build & Execution
```text
build_windows.bat
cd run_win
ez_stress_master.exe
```

* 3. Linux One-Click Build & Execution
```text
chmod +x build_linux.sh
./build_linux.sh
cd run_linux
./ez_stress_master
```

* 4. Run Directly via .NET CLI
```text
dotnet run -c Release
```

# FFI Overview & Setup
```text
 =================================================================
 ez_stress_master.cs - EDB 2.0 C# (.NET) Physical Stress Master & Benchmark
 
 =================================================================
 [C# / .NET Native P/Invoke Configuration & Execution Guide]
 
 1. Project Initialization & File Rename:
    --------------------------------------------------------------
    cd ffi/cs
    dotnet new console --force && ren Program.cs ez_stress_master.cs
 
 2. Native Library & Data Files Preparation:
    --------------------------------------------------------------
    Ensure the project directory (ffi/cs) includes:
    - ez_dbengine.dll (or libez_dbengine.so)
    - daily_2026-03-19.csv
 
 3. Execute High-Speed Stress Test (Release Run Mode):
    --------------------------------------------------------------
    dotnet run -c Release
 =================================================================
```