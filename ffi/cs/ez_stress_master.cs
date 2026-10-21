/* =================================================================
 * ez_stress_master.cs - EDB 2.0 C# (.NET) Physical Stress Master & Benchmark
 * ================================================================= */

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using EzDbEngine;

namespace EzDbEngineBenchmark
{
    class Program
    {
        private const string TEST_DB = "ez_full_stress.ebf";
        private const string CSV_FILE = "daily_2026-03-19.csv";
        private const int NUM_THREADS = 4;

        static void Main(string[] args)
        {
            Console.WriteLine("=== EDB 2.0 C# (.NET) High-Concurrency Shared Instance Stress Test ===");

            // Ensure clean environment by deleting existing physical files
            try { if (File.Exists(TEST_DB)) File.Delete(TEST_DB); } catch { }
            try { if (File.Exists("ez_full_stress_idx_code.edx")) File.Delete("ez_full_stress_idx_code.edx"); } catch { }
            try { if (File.Exists("ez_full_stress_idx_date.edx")) File.Delete("ez_full_stress_idx_date.edx"); } catch { }

            Stopwatch totalSw = Stopwatch.StartNew();
            EzDBEngine engine = EzDBEngine.Instance;

            EZ_FIELD_NODE[] fdt = new EZ_FIELD_NODE[12];
            fdt[0]  = EZ_FIELD_NODE.Create("date",         'C', 10, 0);
            fdt[1]  = EZ_FIELD_NODE.Create("code",         'C', 12, 0);
            fdt[2]  = EZ_FIELD_NODE.Create("name",         'C', 36, 0);
            fdt[3]  = EZ_FIELD_NODE.Create("trade_volume", 'N', 10, 0);
            fdt[4]  = EZ_FIELD_NODE.Create("trade_amount", 'N', 12, 2);
            fdt[5]  = EZ_FIELD_NODE.Create("open",         'N',  8, 2);
            fdt[6]  = EZ_FIELD_NODE.Create("high",         'N',  8, 2);
            fdt[7]  = EZ_FIELD_NODE.Create("low",          'N',  8, 2);
            fdt[8]  = EZ_FIELD_NODE.Create("close",        'N',  8, 2);
            fdt[9]  = EZ_FIELD_NODE.Create("diff",         'N',  8, 2);
            fdt[10] = EZ_FIELD_NODE.Create("trade_count",  'N',  8, 0);
            fdt[11] = new EZ_FIELD_NODE(); // Terminator Node

            int createSt = engine.CreateTable(TEST_DB, fdt);
            Console.WriteLine($"[DEBUG] CreateTable Status: {createSt}");
            if (createSt != 0)
            {
                Console.Error.WriteLine($"[ERROR] CreateTable failed: {engine.GetDetailedError(createSt)}");
                return;
            }

            ulong handle = engine.Use(TEST_DB);
            Console.WriteLine($"[DEBUG] Mounted Table Handle: {handle}");

            Run4BucketStressTest(engine, handle, CSV_FILE);

            Stopwatch idxSw = Stopwatch.StartNew();
            int idxSt = engine.CreateIndex(handle, "idx_code", "code", true);
            idxSw.Stop();
            Console.WriteLine($"<<< CreateIndex | Res: {(idxSt == 0 ? "SUCCESS" : "FAILED")} | Time: {idxSw.Elapsed.TotalMilliseconds:F3} ms");
            if (idxSt != 0)
            {
                Console.Error.WriteLine($"[ERROR] CreateIndex failed: {engine.GetDetailedError(idxSt)}");
            }

            int seekSt = engine.SeekByTag(handle, "idx_code", "2330");
            if (seekSt == 0)
            {
                int rollingCount = 0;
                uint recSize = engine.GetRecordSize(handle);
                byte[] recBuf = new byte[recSize];

                while (engine.GetRecord(handle, recBuf, 0, "idx_code") == 0)
                {
                    string code = Encoding.UTF8.GetString(recBuf, 10, 12).TrimEnd('\0', ' ');
                    if (!code.StartsWith("2330")) break;

                    rollingCount++;
                    if (engine.Skip(handle, 1, 0, "idx_code") != 0) break;
                }
                Console.WriteLine($">>> 2330 Rolling Read Count: {rollingCount}");
            }
            else
            {
                Console.WriteLine($"[INFO] Seek target not found: {engine.GetDetailedError(seekSt)}");
            }

            engine.Close(handle);
            totalSw.Stop();

            Console.WriteLine($"\nTotal Performance: {totalSw.Elapsed.TotalMilliseconds:F3} ms");
        }

        private static void Run4BucketStressTest(EzDBEngine engine, ulong handle, string csvFilename)
        {
            List<string>[] buckets = new List<string>[NUM_THREADS];
            for (int i = 0; i < NUM_THREADS; i++) buckets[i] = new List<string>();

            int totalRecords = 0;
            Console.WriteLine("\n=== [4-Bucket Stress] Parsing CSV and Distributing into Buckets ===");

            if (File.Exists(csvFilename))
            {
                using var reader = new StreamReader(csvFilename, Encoding.UTF8);
                reader.ReadLine(); // Skip header line
                string? line;
                while ((line = reader.ReadLine()) != null)
                {
                    line = line.TrimEnd('\r', '\n', ' ');
                    if (string.IsNullOrWhiteSpace(line)) continue;

                    buckets[totalRecords % NUM_THREADS].Add(line);
                    totalRecords++;
                }
            }

            for (int i = 0; i < NUM_THREADS; i++)
            {
                Console.WriteLine($"  ├─► Bucket [{i}] loaded with {buckets[i].Count:N0} records");
            }

            Console.WriteLine("\n=== [4-Bucket Stress] Spawning Parallel Threads for Append ===");

            Stopwatch stressSw = Stopwatch.StartNew();
            double[] workerTimes = new double[NUM_THREADS];

            Task[] tasks = new Task[NUM_THREADS];
            for (int t = 0; t < NUM_THREADS; t++)
            {
                int threadId = t;
                tasks[t] = Task.Run(() =>
                {
                    Stopwatch wSw = Stopwatch.StartNew();
                    foreach (var line in buckets[threadId])
                    {
                        int st = engine.Append(handle, line, 1, ",");
                        if (st != 0)
                        {
                            Console.Error.WriteLine($"[Worker {threadId} Error] {engine.GetDetailedError(st)}");
                        }
                    }
                    wSw.Stop();
                    workerTimes[threadId] = wSw.Elapsed.TotalMilliseconds;
                });
            }

            Task.WaitAll(tasks);
            stressSw.Stop();
            engine.Commit(handle);

            double totalMs = stressSw.Elapsed.TotalMilliseconds;
            double tps = totalMs > 0 ? (totalRecords * 1000.0) / totalMs : 0;

            Console.WriteLine("╔═══════════════════════════════════════════════════════════════════╗");
            Console.WriteLine("║  [4-THREAD BUCKET STRESS REPORT - C# .NET NATIVE]                 ║");
            Console.WriteLine("╠═══════════════════════════════════════════════════════════════════╣");
            for (int i = 0; i < NUM_THREADS; i++)
            {
                Console.WriteLine($"  │ Thread [{i}] Execution Time: {workerTimes[i],8:F3} ms ({buckets[i].Count:N0} recs)");
            }
            Console.WriteLine("  ├─────────────────────────────────────────────────────────────────┤");
            Console.WriteLine($"  │ Total Injected Records : {totalRecords:N0}");
            Console.WriteLine($"  │ Total Elapsed Time     : {totalMs,8:F3} ms");
            Console.WriteLine($"  │ Overall Throughput     : {tps,8:F2} TPS");
            Console.WriteLine("╚═══════════════════════════════════════════════════════════════════╝");
        }
    }
}