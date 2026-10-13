/* =================================================================================
 * 📁 FILE: ez_stress_master.cpp
 * ---------------------------------------------------------------------------------
 * C++ Shared-Instance Multi-Threaded Stress Test Benchmark for ez_dbengine  
 * ---------------------------------------------------------------------------------
 * MSVC Windows Build
 *  cl /std:c++17 /EHsc /O2 ez_stress_master.cpp ez_dbengine.cpp /I. /Fe:ez_stress_master.exe ez_engine.lib
 * ---------------------------------------------------------------------------------
 * Linux / macOS (GCC / Clang) Build
 *  g++ -std=c++17 -O3 ez_stress_master.cpp ez_dbengine.cpp \
 *    -I. -L. -lez_engine -lpthread \
 *    -o ez_stress_master
 * =================================================================================
 */ 
#define _CRT_SECURE_NO_WARNINGS

#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cstring>
#include <chrono>
#include <thread>
#include <iomanip>
#include <memory>

#include "ez_dbengine.hpp"
#include "ez_table_daily.h"

/* Physical Constant Definitions */
#define TEST_DB              "ez_full_stress.ebf"
#define CSV_FILE             "daily_2026-03-19.csv"
#define NUM_THREADS          4
#define MAX_LINES_PER_BUCKET 50000
#define LINE_BUF_SIZE        2048

using Clock = std::chrono::high_resolution_clock;

inline double get_elapsed_ms(Clock::time_point start, Clock::time_point end) {
    return std::chrono::duration<double, std::milli>(end - start).count();
}

// Concurrent Task Bucket: Passes Handle and Engine reference instead of binding to a simplex DB object
struct ThreadBucket {
    ez::EzDBEngine* engine{nullptr};
    u64 handle{0};
    char (*lines)[LINE_BUF_SIZE]{nullptr};
    uint32_t line_count{0};
    uint32_t thread_id{0};
    double elapsed_ms{0.0};
};

bool file_exists(const std::string& filename) {
    std::ifstream f(filename.c_str());
    return f.good();
}

void data_to_rec(const char* raw_ebf, DAILY_RECORD* rec) {
    if (!raw_ebf || !rec) return;
    std::memset(rec, 0, sizeof(DAILY_RECORD));

    EXTRACT_STR(rec->date, 0, 10);
    EXTRACT_STR(rec->code, 10, 12);
    EXTRACT_STR(rec->name, 22, 36);

    rec->trade_volume = static_cast<u32>(EXTRACT_NUM(58, 10));
    rec->trade_amount = static_cast<f64>(EXTRACT_NUM(68, 12));
    rec->open         = static_cast<f32>(EXTRACT_NUM(80, 8));
    rec->high         = static_cast<f32>(EXTRACT_NUM(88, 8));
    rec->low          = static_cast<f32>(EXTRACT_NUM(96, 8));
    rec->close        = static_cast<f32>(EXTRACT_NUM(104, 8));
    rec->diff         = static_cast<f32>(EXTRACT_NUM(112, 8));
    rec->trade_count  = static_cast<u32>(EXTRACT_NUM(120, 8));
}

void dump_daily_record(const DAILY_RECORD* rec) {
    if (!rec) return;

    std::cout << "╔═══════════════════════════════════════════════════════════════════╗\n";
    std::cout << "║  [DAILY_RECORD_VIEW] Daily Record Structure Dump                  ║\n";
    std::cout << "╠═══════════════════════════════════════════════════════════════════╣\n";
    std::cout << "  │ [00] Date             ➔ \"" << std::string(rec->date, strnlen(rec->date, 10)) << "\"\n";
    std::cout << "  │ [01] Code             ➔ \"" << std::string(rec->code, strnlen(rec->code, 12)) << "\"\n";
    std::cout << "  │ [02] Name             ➔ \"" << std::string(rec->name, strnlen(rec->name, 36)) << "\"\n";
    std::cout << "  ├─────────────────────────────────────────────────────────────────┤\n";
    std::cout << "  │ [03] Trade Volume     ➔ " << rec->trade_volume << "\n";
    std::cout << "  │ [04] Trade Amount     ➔ " << std::fixed << std::setprecision(2) << rec->trade_amount << "\n";
    std::cout << "  │ [05] Open Price       ➔ " << rec->open << "\n";
    std::cout << "  │ [06] High Price       ➔ " << rec->high << "\n";
    std::cout << "  │ [07] Low Price        ➔ " << rec->low << "\n";
    std::cout << "  │ [08] Close Price      ➔ " << rec->close << "\n";
    std::cout << "  │ [09] Price Diff       ➔ " << rec->diff << "\n";
    std::cout << "  │ [10] Trade Count      ➔ " << rec->trade_count << "\n";
    std::cout << "  ╚═══════════════════════════════════════════════════════════════════╝" << std::endl;
}

// 4-Worker Concurrent Append: Directly writes to the shared WorkArea Handle via the stateless singleton driver
void ez_append_worker(ThreadBucket* bucket) {
    if (!bucket || !bucket->engine || bucket->handle == 0) return;

    auto ts = Clock::now();

    for (uint32_t i = 0; i < bucket->line_count; ++i) {
        // Atomic lock-free write;底层 handled concurrently via IOCP / io_uring
        bucket->engine->append(bucket->handle, bucket->lines[i], 1, ",");
    }

    auto te = Clock::now();
    bucket->elapsed_ms = get_elapsed_ms(ts, te);
}

void run_4bucket_stress_test(ez::EzDBEngine& engine, u64 handle, const std::string& csv_filename) {
    std::ifstream fp(csv_filename);
    if (!fp.is_open()) {
        std::cerr << "[ERROR] Cannot open CSV file: " << csv_filename << std::endl;
        return;
    }

    std::vector<ThreadBucket> buckets(NUM_THREADS);
    for (int i = 0; i < NUM_THREADS; ++i) {
        buckets[i].engine = &engine;
        buckets[i].handle = handle;
        buckets[i].line_count = 0;
        buckets[i].thread_id = i;
        buckets[i].elapsed_ms = 0.0;
        buckets[i].lines = static_cast<char(*)[LINE_BUF_SIZE]>(std::malloc(MAX_LINES_PER_BUCKET * sizeof(*buckets[i].lines)));
        if (!buckets[i].lines) {
            std::cerr << "[ERROR] Failed to allocate memory for bucket " << i << std::endl;
            return;
        }
    }

    std::string line_buf;
    if (!std::getline(fp, line_buf)) {
        fp.close();
        return;
    }

    std::cout << "=== [4-Bucket Stress] Parsing CSV and Distributing into Buckets ===" << std::endl;

    uint32_t total_records = 0;
    while (std::getline(fp, line_buf)) {
        uint32_t target_bucket = total_records % NUM_THREADS;
        uint32_t line_idx = buckets[target_bucket].line_count;

        if (line_idx < MAX_LINES_PER_BUCKET) {
            std::strncpy(buckets[target_bucket].lines[line_idx], line_buf.c_str(), LINE_BUF_SIZE - 1);
            buckets[target_bucket].lines[line_idx][LINE_BUF_SIZE - 1] = '\0';
            buckets[target_bucket].line_count++;
            total_records++;
        } else {
            std::cout << "[WARNING] Bucket " << target_bucket << " is full!" << std::endl;
            break;
        }
    }
    fp.close();

    for (int i = 0; i < NUM_THREADS; ++i) {
        std::cout << "  ├─► Bucket [" << i << "] loaded with " << buckets[i].line_count << " records" << std::endl;
    }

    std::cout << "=== [4-Bucket Stress] Spawning 4 Worker Threads for Shared-Instance append ===" << std::endl;

    auto total_start = Clock::now();

    std::vector<std::thread> worker_threads;
    worker_threads.reserve(NUM_THREADS);

    for (int t = 0; t < NUM_THREADS; ++t) {
        worker_threads.emplace_back(ez_append_worker, &buckets[t]);
    }

    for (auto& th : worker_threads) {
        if (th.joinable()) {
            th.join();
        }
    }

    auto total_end = Clock::now();
    double total_ms = get_elapsed_ms(total_start, total_end);

    std::cout << "╔═══════════════════════════════════════════════════════════════════╗\n";
    std::cout << "║  [4-THREAD BUCKET STRESS REPORT]                                  ║\n";
    std::cout << "╠═══════════════════════════════════════════════════════════════════╣\n";

    for (int i = 0; i < NUM_THREADS; ++i) {
        std::cout << "  │ Thread [" << i << "] Execution Time: "
                  << std::setw(8) << std::fixed << std::setprecision(3) << buckets[i].elapsed_ms
                  << " ms (" << buckets[i].line_count << " recs)\n";
    }

    std::cout << "  ├─────────────────────────────────────────────────────────────────┤\n";
    std::cout << "  │ Total Injected Records : " << total_records << "\n";
    std::cout << "  │ Total Elapsed Time     : " << std::setw(8) << std::fixed << std::setprecision(3) << total_ms << " ms\n";
    std::cout << "  │ Overall Throughput     : " << std::setw(8) << std::fixed << std::setprecision(2) << ((total_records * 1000.0) / total_ms) << " TPS\n";
    std::cout << "╚═══════════════════════════════════════════════════════════════════╝" << std::endl;

    engine.commit(handle);

    for (int i = 0; i < NUM_THREADS; ++i) {
        std::free(buckets[i].lines);
    }
}

int main() {
    auto t_start = Clock::now();

    std::remove(TEST_DB);
    std::remove("ez_full_stress_idx_code.edx");
    std::remove("ez_full_stress_idx_date.edx");
    
    std::vector<EZ_FIELD_NODE> fdt = {
        { "date",         'C', 10, 0 }, 
        { "code",         'C', 12, 0 }, 
        { "name",         'C', 36, 0 }, 
        { "trade_volume", 'N', 10, 0 }, 
        { "trade_amount", 'N', 12, 2 }, 
        { "open",         'N',  8, 2 }, 
        { "high",         'N',  8, 2 }, 
        { "low",          'N',  8, 2 }, 
        { "close",        'N',  8, 2 }, 
        { "diff",         'N',  8, 2 }, 
        { "trade_count",  'N',  8, 0 },
        { {0},              0,  0, 0 }
    };

    std::cout << "=== EDB 2.0 Physical Stress Test (Shared Instance C++ Version) ===" << std::endl;

    // Acquire global singleton driver
    ez::EzDBEngine& engine = ez::EzDBEngine::get_instance();

    if (!file_exists(TEST_DB)) {
        EZ_STATUS st = engine.create_table(TEST_DB, fdt);
        if (st != EZ_SUCCESS) {
            std::cerr << "[ERROR] create_table failed: " 
                      << engine.get_detailed_error(st) << std::endl;
            return -1;
        }    }

    std::this_thread::sleep_for(std::chrono::milliseconds(10));

    try {
        // Use the same persistent WorkArea Handle
        u64 handle = engine.use(TEST_DB);

        run_4bucket_stress_test(engine, handle, CSV_FILE);

        auto idx_start = Clock::now();
        EZ_STATUS idx_st = engine.create_index(handle, "idx_code", "code", true);
        auto idx_end = Clock::now();        

        std::cout << "<<< create_index | Res: " << (idx_st == EZ_SUCCESS ? "SUCCESS" : "FAILED");
        if (idx_st != EZ_SUCCESS) {
            std::cout << " (" << engine.get_detailed_error(idx_st) << ")";
        }
        std::cout << " | Time: " << std::fixed << std::setprecision(3) 
                  << get_elapsed_ms(idx_start, idx_end) << " ms\n";

        /* Index Seek & Sequential Retrieval: Explicitly pass handle and tag_name = "idx_code" for sequential read */
        EZ_STATUS seek_st = engine.seek_by_tag(handle, "idx_code", "2330");
        if (seek_st == EZ_SUCCESS) {
            DAILY_RECORD buf;
            int count = 0;
            uint32_t rec_size = engine.get_record_size(handle);

            if (rec_size > 0) {
                std::vector<char> record_payload(rec_size, '\0');

                while (engine.get_record(handle, record_payload.data(), rec_size, false, 0, "idx_code") == EZ_SUCCESS) {

                    // 🔍 Critical Debug 1: Invoke low-level analyzer to dump raw physical record slice
                    engine.dump_record(handle, record_payload.data());

                    data_to_rec(record_payload.data(), &buf);
                    // 🔍 Critical Debug 2: Print actual decoded buf.code content and length
                    std::cout << ">>> Decoded Code: [" << std::string(buf.code, 12) << "]" 
                      << " (Raw match check: " << std::strncmp(buf.code, "2330", 4) << ")" << std::endl;

                    if (std::strncmp(buf.code, "2330", 4) != 0) break;

                    dump_daily_record(&buf);
                    count++;

                    std::memset(record_payload.data(), 0, record_payload.size());
                    if (!engine.skip(handle, 1, 0, "idx_code")) break;
                }
                std::cout << ">>> 2330 Rolling Read Count: " << count << std::endl;
            }
        } else {
            std::cout << "[INFO] Seek target not found: " 
                      << engine.get_detailed_error(seek_st) << std::endl;
        }

        // Close Handle after testing
        engine.close(handle);

    } catch (const std::exception& e) {
        std::cerr << "[EXCEPTION] " << e.what() << std::endl;
        return -1;
    }

    auto t_end = Clock::now();
    std::cout << "Total Performance: " << std::fixed << std::setprecision(3) << get_elapsed_ms(t_start, t_end) << " ms" << std::endl;

    return 0;
}