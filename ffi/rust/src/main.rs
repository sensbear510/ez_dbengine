//! main.rs - EDB 2.0 Physical Stress Master (Stateless Singleton & Multithreaded)

mod ez_dbengine;

use ez_dbengine::{EzDbEngine, FieldDefinition, FieldType};
use std::ffi::{c_char, CString};
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::thread;
use std::time::Instant;

const NUM_THREADS: usize = 4;
const TEST_DB: &str = "ez_full_stress.ebf";
const CSV_FILE: &str = "daily_2026-03-19.csv";

fn clean_all_db_files() {
    if let Ok(entries) = std::fs::read_dir(".") {
        for entry in entries.flatten() {
            let path = entry.path();
            if let Some(ext) = path.extension() {
                let ext_str = ext.to_string_lossy().to_lowercase();
                if ext_str == "ebf" || ext_str == "edx" {
                    let _ = std::fs::remove_file(&path);
                }
            }
        }
    }
}

fn main() {
    clean_all_db_files();

    println!("=== EDB 2.0 Rust Physical Stress Master (Shared Instance SDK - Zero Allocation) ===");

    let total_start = Instant::now();
    let engine = EzDbEngine::global();

    let schema = vec![
        FieldDefinition::new("date", FieldType::Character, 10, 0),
        FieldDefinition::new("code", FieldType::Character, 12, 0),
        FieldDefinition::new("name", FieldType::Character, 36, 0),
        FieldDefinition::new("trade_volume", FieldType::Numeric, 10, 0),
        FieldDefinition::new("trade_amount", FieldType::Numeric, 12, 2),
        FieldDefinition::new("open", FieldType::Numeric, 8, 2),
        FieldDefinition::new("high", FieldType::Numeric, 8, 2),
        FieldDefinition::new("low", FieldType::Numeric, 8, 2),
        FieldDefinition::new("close", FieldType::Numeric, 8, 2),
        FieldDefinition::new("diff", FieldType::Numeric, 8, 2),
        FieldDefinition::new("trade_count", FieldType::Numeric, 8, 0),
    ];

    if let Err(err) = engine.create_table(TEST_DB, &schema) {
        eprintln!("[ERROR] Database creation failed: {}", err);
        return;
    }

    let (handle, _report) = match engine.use_table(TEST_DB) {
        Ok(res) => res,
        Err(err) => {
            eprintln!("[ERROR] Database open failed: {}", err);
            return;
        }
    };

    engine.dump_workarea(handle);

    // 執行 4-Thread 併發壓測
    run_4bucket_stress_test(handle, CSV_FILE);

    // 建立索引
    let idx_start = Instant::now();
    let idx_res = engine.create_index(handle, "idx_code", "code", true);
    let idx_elapsed = idx_start.elapsed().as_secs_f64() * 1000.0;
    println!("<<< create_index | Status: {} | Time: {:.3} ms", idx_res, idx_elapsed);
    if idx_res != 0 {
        eprintln!("[ERROR] create_index failed: {}", engine.get_detailed_error(idx_res));
    }

    // 循序查詢 2330
    if engine.seek_by_tag(handle, "idx_code", &["2330"]) {
        let mut rolling_count = 0;
        while let Some(raw_record) = engine.get_record(handle, 0, Some("idx_code"), false) {
            if raw_record.len() >= 22 {
                let code_slice = &raw_record[10..22];
                let code_str = String::from_utf8_lossy(code_slice);
                let clean_code = code_str.trim_matches('\0').trim();

                if !clean_code.starts_with("2330") {
                    break;
                }
            }
            rolling_count += 1;
            if engine.skip(handle, 1, 0, Some("idx_code")) != 0 {
                break;
            }
        }
        println!(">>> 2330 Rolling Read Count: {}", rolling_count);
    }

    engine.close(handle);

    let total_elapsed = total_start.elapsed().as_secs_f64() * 1000.0;
    println!("\nTotal Performance: {:.3} ms", total_elapsed);
}

fn run_4bucket_stress_test(handle: u64, csv_filename: &str) {
    // 預先在準備階段將字串轉成 CString，進入計時區間後 0 次 Heap 分配！
    let mut buckets: Vec<Vec<CString>> = (0..NUM_THREADS).map(|_| Vec::with_capacity(12000)).collect();
    let mut total_records = 0;

    println!("\n=== [4-Bucket Stress] Parsing CSV and Distributing into Buckets ===");

    if Path::new(csv_filename).exists() {
        if let Ok(file) = File::open(csv_filename) {
            let reader = BufReader::new(file);
            let mut lines = reader.lines();
            let _ = lines.next();

            for line in lines.flatten() {
                let trimmed = line.trim();
                if !trimmed.is_empty() {
                    if let Ok(c_str) = CString::new(trimmed) {
                        buckets[total_records % NUM_THREADS].push(c_str);
                        total_records += 1;
                    }
                }
            }
        }
    }

    for (i, bucket) in buckets.iter().enumerate() {
        println!("  ├─► Bucket [{}] loaded with {} records", i, bucket.len());
    }

    println!("\n=== [4-Bucket Stress] Spawning 4 OS Threads for Shared-Handle Append ===");

    let stress_start = Instant::now();
    let mut handles = Vec::with_capacity(NUM_THREADS);

    // 4 個 OS Thread 並發呼叫 append
    for (_thread_id, bucket) in buckets.into_iter().enumerate() {
        let th = thread::spawn(move || {
            let engine = EzDbEngine::global();
            let w_start = Instant::now();
            let count = bucket.len();
            let mut err_count = 0;

            // 靜態常數逗號指標
            static COMMA: &[u8] = b",\0";
            let comma_ptr = COMMA.as_ptr() as *const c_char;

            // 熱路徑：直接傳遞裸指標，0 次 Heap 分配與釋放
            for c_line in &bucket {
                let st = unsafe { engine.append_raw(handle, c_line.as_ptr(), 1, comma_ptr) };
                if st != 0 {
                    err_count += 1;
                }
            }

            let elapsed_ms = w_start.elapsed().as_secs_f64() * 1000.0;
            (elapsed_ms, count, err_count)
        });
        handles.push(th);
    }

    let mut worker_results = Vec::with_capacity(NUM_THREADS);
    for h in handles {
        if let Ok(res) = h.join() {
            worker_results.push(res);
        }
    }

    let _ = EzDbEngine::global().commit(handle);

    let total_ms = stress_start.elapsed().as_secs_f64() * 1000.0;
    let tps = if total_ms > 0.0 { (total_records as f64 * 1000.0) / total_ms } else { 0.0 };

    println!("╔═══════════════════════════════════════════════════════════════════╗");
    println!("║  [4-THREAD BUCKET STRESS REPORT - RUST SHARED INSTANCE]           ║");
    println!("╠═══════════════════════════════════════════════════════════════════╣");
    for (i, (ms, recs, errs)) in worker_results.iter().enumerate() {
        println!("  │ Thread [{}] Execution Time: {:8.3} ms ({} recs, {} errs)", i, ms, recs, errs);
    }
    println!("  ├─────────────────────────────────────────────────────────────────┤");
    println!("  │ Total Injected Records : {}", total_records);
    println!("  │ Total Elapsed Time     : {:8.3} ms", total_ms);
    println!("  │ Overall Throughput     : {:8.2} TPS", tps);
    println!("╚═══════════════════════════════════════════════════════════════════╝");
}