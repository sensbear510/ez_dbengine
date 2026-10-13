"""
Command Line Execution:
python -u test_ez_stress.py
"""
import os
import sys
import time
import glob
import threading
from dataclasses import dataclass
from typing import List, Optional
from pathlib import Path

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from ez_dbengine import EzDBEngine, EZ_FIELD_NODE

TEST_DB = os.path.join(BASE_DIR, "ez_full_stress.ebf")
CSV_FILE = os.path.abspath(os.path.join(BASE_DIR, "..", "..", "daily_2026-03-19.csv"))
NUM_THREADS = 4


def clean_all_db_files():
    """徹底刪除工作目錄下所有殘留的 .ebf 與 .edx 實體檔案"""
    for ext in ("*.ebf", "*.edx"):
        for f in glob.glob(os.path.join(BASE_DIR, ext)):
            try:
                os.remove(f)
                print(f"[CLEAN] 已清除殘留資料庫檔案: {os.path.basename(f)}")
            except OSError as e:
                print(f"[WARN] 無法刪除檔案 {f}: {e}")


@dataclass
class DailyRecord:
    date: str
    code: str
    name: str
    trade_volume: int
    trade_amount: float
    open: float
    high: float
    low: float
    close: float
    diff: float
    trade_count: int


def data_to_rec(raw_ebf: bytes) -> DailyRecord:
    def _parse_str(b_slice: bytes) -> str:
        return b_slice.decode('utf-8', errors='ignore').strip().rstrip('\x00')

    def _safe_int(b_slice: bytes) -> int:
        try:
            return int(_parse_str(b_slice))
        except ValueError:
            return 0

    def _safe_float(b_slice: bytes) -> float:
        try:
            return float(_parse_str(b_slice))
        except ValueError:
            return 0.0

    return DailyRecord(
        date=_parse_str(raw_ebf[0:10]),
        code=_parse_str(raw_ebf[10:22]),
        name=_parse_str(raw_ebf[22:58]),
        trade_volume=_safe_int(raw_ebf[58:68]),
        trade_amount=_safe_float(raw_ebf[68:80]),
        open=_safe_float(raw_ebf[80:88]),
        high=_safe_float(raw_ebf[88:96]),
        low=_safe_float(raw_ebf[96:104]),
        close=_safe_float(raw_ebf[104:112]),
        diff=_safe_float(raw_ebf[112:120]),
        trade_count=_safe_int(raw_ebf[120:128])
    )


def dump_daily_record(rec: DailyRecord):
    if not rec:
        return
    print(f"[DAILY_RECORD] Date: {rec.date} | Code: {rec.code} | Name: {rec.name} | Close: {rec.close}")


def ez_append_worker(engine: EzDBEngine, handle: int, bucket: List[str], thread_id: int, metrics: list):
    """Thread Worker: 無狀態原子 Append，共享 WorkArea Handle"""
    t_start = time.perf_counter()
    err_count = 0

    for line in bucket:
        st = engine.append(handle, line, delimiter=",")
        if st != 0:
            err_count += 1
            print(f"[Worker {thread_id} Error] {engine.get_detailed_error(st)}", file=sys.stderr)

    t_end = time.perf_counter()
    elapsed_ms = (t_end - t_start) * 1000.0
    metrics[thread_id] = (elapsed_ms, len(bucket), err_count)


def run_4bucket_stress_test(engine: EzDBEngine, handle: int, csv_filename: str):
    if not os.path.exists(csv_filename):
        print(f"[ERROR] Cannot open CSV file: {csv_filename}")
        return

    buckets: List[List[str]] = [[] for _ in range(NUM_THREADS)]
    print("=== [4-Bucket Stress] Parsing CSV and Distributing into Buckets ===")
    total_records = 0

    with open(csv_filename, "r", encoding="utf-8") as f:
        header = f.readline()
        for line in f:
            clean_line = line.strip()
            if not clean_line:
                continue
            buckets[total_records % NUM_THREADS].append(clean_line)
            total_records += 1

    for i in range(NUM_THREADS):
        print(f"  ├─► Bucket [{i}] loaded with {len(buckets[i])} records")

    print("=== [4-Bucket Stress] Spawning 4 Worker Threads for Shared-Instance append ===")

    threads: List[threading.Thread] = []
    metrics = [None] * NUM_THREADS
    total_start = time.perf_counter()

    for t in range(NUM_THREADS):
        thread = threading.Thread(
            target=ez_append_worker,
            args=(engine, handle, buckets[t], t, metrics)
        )
        threads.append(thread)
        thread.start()

    for thread in threads:
        thread.join()

    total_end = time.perf_counter()
    total_ms = (total_end - total_start) * 1000.0

    print("╔═══════════════════════════════════════════════════════════════════╗")
    print("║  [4-THREAD BUCKET STRESS REPORT - PYTHON NATIVE FFI]              ║")
    print("╠═══════════════════════════════════════════════════════════════════╣")

    for i in range(NUM_THREADS):
        elapsed_ms, count, errs = metrics[i]
        print(f"  │ Thread [{i}] Execution Time: {elapsed_ms:8.3f} ms ({count} recs, {errs} errs)")

    tps = (total_records * 1000.0) / total_ms if total_ms > 0 else 0.0
    print("  ├─────────────────────────────────────────────────────────────────┤")
    print(f"  │ Total Injected Records : {total_records}")
    print(f"  │ Total Elapsed Time     : {total_ms:8.3f} ms")
    print(f"  │ Overall Throughput     : {tps:8.2f} TPS")
    print("╚═══════════════════════════════════════════════════════════════════╝")

    commit_st = engine.commit(handle)
    if commit_st != 0:
        print(f"[WARN] Commit 回傳非零狀態: {engine.get_detailed_error(commit_st)}")


def main():
    # 1. 壓測開始前徹底清除所有殘留資料庫檔案
    clean_all_db_files()

    t_start = time.perf_counter()

    fdt = [
        EZ_FIELD_NODE.create("date", "C", 10),
        EZ_FIELD_NODE.create("code", "C", 12),
        EZ_FIELD_NODE.create("name", "C", 36),
        EZ_FIELD_NODE.create("trade_volume", "N", 10, 0),
        EZ_FIELD_NODE.create("trade_amount", "N", 12, 2),
        EZ_FIELD_NODE.create("open", "N", 8, 2),
        EZ_FIELD_NODE.create("high", "N", 8, 2),
        EZ_FIELD_NODE.create("low", "N", 8, 2),
        EZ_FIELD_NODE.create("close", "N", 8, 2),
        EZ_FIELD_NODE.create("diff", "N", 8, 2),
        EZ_FIELD_NODE.create("trade_count", "N", 8, 0)
    ]

    print("=== EDB 2.0 Python Physical Stress Test (Stateless Singleton) ===")
    engine = EzDBEngine.get_instance()

    if not os.path.exists(TEST_DB):
        status = engine.create_table(TEST_DB, fdt)
        print(f"[DEBUG] ez_db_create: {status}")
        if status != 0:
            print(f"[ERROR] create_table failed: {engine.get_detailed_error(status)}", file=sys.stderr)
            sys.exit(-1)

    time.sleep(0.01)

    handle = engine.use(TEST_DB)
    try:
        engine.dump_workarea(handle)
        run_4bucket_stress_test(engine, handle, CSV_FILE)

        t_idx_start = time.perf_counter()
        res_idx = engine.create_index(handle, "idx_code", "code", is_unique=True)
        t_idx_end = time.perf_counter()
        idx_ms = (t_idx_end - t_idx_start) * 1000.0
        print(f"<<< ez_db_create_index | Status: {res_idx} | Time: {idx_ms:10.3f} ms")
        if res_idx != 0:
            print(f"[ERROR] create_index failed: {engine.get_detailed_error(res_idx)}", file=sys.stderr)

        if engine.seek_by_tag(handle, "idx_code", ["2330"]):
            count = 0
            while True:
                record_payload = engine.get_record(handle, tag_id=0, tag_name="idx_code")
                if not record_payload:
                    break

                rec = data_to_rec(record_payload)
                if not rec.code.startswith("2330"):
                    break

                dump_daily_record(rec)
                count += 1

                if engine.skip(handle, 1, tag_id=0, tag_name="idx_code") != 0:
                    break

            print(f">>> 2330 Rolling Read Count: {count}\n")
        else:
            print("[INFO] 搜尋 2330 未找到符合的紀錄")

    finally:
        engine.close(handle)

    total_time_ms = (time.perf_counter() - t_start) * 1000.0
    print(f"Total Performance: {total_time_ms:10.3f} ms")


if __name__ == "__main__":
    main()