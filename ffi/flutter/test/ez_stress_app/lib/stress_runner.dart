// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ffi';
// Standard package import
import 'package:ez_dbengine/ez_dbengine.dart';

// Stress test report data model
class StressReport {
  final int totalRecords;
  final double totalElapsedMs;
  final double tps;
  final List<double> threadTimesMs;
  final List<String> logs;

  StressReport({
    required this.totalRecords,
    required this.totalElapsedMs,
    required this.tps,
    required this.threadTimesMs,
    required this.logs,
  });
}

// Arguments passed to worker isolate
class WorkerPayload {
  final int dbHandle;
  final List<String> lines;
  final int threadId;
  final SendPort replyPort;

  WorkerPayload(this.dbHandle, this.lines, this.threadId, this.replyPort);
}

// --- Worker Isolate (corresponds to C implementation ez_append_worker) ---
void _ezAppendWorker(WorkerPayload payload) {
  // Instantiate EzDB instance per isolate to invoke FFI APIs
  final ezDb = EzDB();
  final stopwatch = Stopwatch()..start();
  int errorCount = 0;

  for (final line in payload.lines) {
    // Invoke append API with CSV comma delimiter and verify status code
    final int st = ezDb.append(payload.dbHandle, line, delimiter: ',');
    if (st != 0) {
      errorCount++;
      // Output detailed error description returned by C-Core diagnostics
      stderr.writeln('[Worker ${payload.threadId} Error] ${ezDb.getDetailedError(st)}');
    }
  }

  stopwatch.stop();

  payload.replyPort.send({
    'threadId': payload.threadId,
    'elapsedMs': stopwatch.elapsedMicroseconds / 1000.0,
    'errorCount': errorCount,
  });
}

// --- Stress Test Master Controller ---
class StressRunner {
  static Future<StressReport> runFullStressTest(String csvPath, Function(String) onLog) async {
    final logs = <String>[];
    void log(String msg) {
      logs.add(msg);
      onLog(msg);
    }

    final ezDb = EzDB();
    const testDb = "ez_full_stress.ebf";
    const testedx1 = "ez_full_stress_idx_code.edx";
    const testedx2 = "ez_full_stress_idx_date.edx";
    final ebf_file = File(testDb);
    if (await ebf_file.exists()) {
      await ebf_file.delete();
    }
    final edx1_file = File(testedx1);
    if (await edx1_file.exists()) {
      await edx1_file.delete();
    }
    final edx2_file = File(testedx2);
    if (await edx2_file.exists()) {
      await edx2_file.delete();
    }

    log("=== EDB 2.0 Physical Stress Test (Flutter FFI Master) ===");

    // 1. Schema definition (aligned with fdt in ez_stress_master.c)
    final fields = [
      const EzField("date", 'C', 10),
      const EzField("code", 'C', 12),
      const EzField("name", 'C', 36),
      const EzField("trade_volume", 'N', 10),
      const EzField("trade_amount", 'N', 12, 2),
      const EzField("open", 'N', 8, 2),
      const EzField("high", 'N', 8, 2),
      const EzField("low", 'N', 8, 2),
      const EzField("close", 'N', 8, 2),
      const EzField("diff", 'N', 8, 2),
      const EzField("trade_count", 'N', 8),
    ];

    // 2. Create table schema via ezDb.create
    log("[DEBUG] Creating DB Schema: $testDb");
    final status = ezDb.create(testDb, fields);
    if (status != 0) {
      throw Exception("ezDb.create failed: ${ezDb.getDetailedError(status)}");
    }

    // 3. Open table via ezDb.use
    final dbHandle = ezDb.use(testDb, nullptr);
    if (dbHandle == 0) {
      throw Exception("ezDb.use failed to open database: ${ezDb.lastError()}");
    }

    ezDb.dumpWorkarea(dbHandle);

    // 4. Read CSV file and perform 4-bucket round-robin distribution
    final csvFile = File(csvPath);
    if (!csvFile.existsSync()) {
      throw Exception("CSV file not found: $csvPath");
    }

    final lines = await csvFile.readAsLines();
    if (lines.isEmpty) throw Exception("CSV file content is empty");

    // Skip CSV header and clean residual trailing whitespace
    final dataLines = lines.skip(1).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    log("=== [4-Bucket Stress] CSV parse complete: ${dataLines.length} records ===");

    final List<List<String>> buckets = List.generate(4, (_) => []);
    for (int i = 0; i < dataLines.length; i++) {
      buckets[i % 4].add(dataLines[i]);
    }

    for (int i = 0; i < 4; i++) {
      log("  ├─► Bucket [$i] loaded with ${buckets[i].length} records");
    }

    // 5. Spawn 4 worker isolates for concurrent ezDb.append
    log("=== [4-Bucket Stress] Spawning 4 worker isolates for concurrent append ===");
    final totalStopwatch = Stopwatch()..start();

    final List<Future<Map<String, dynamic>>> workerFutures = [];
    for (int t = 0; t < 4; t++) {
      final receivePort = ReceivePort();
      final payload = WorkerPayload(dbHandle, buckets[t], t, receivePort.sendPort);
      Isolate.spawn(_ezAppendWorker, payload);
      workerFutures.add(receivePort.first.then((res) => res as Map<String, dynamic>));
    }

    final results = await Future.wait(workerFutures);
    totalStopwatch.stop();

    final double totalMs = totalStopwatch.elapsedMicroseconds / 1000.0;
    final List<double> threadTimes = List.filled(4, 0.0);

    for (final res in results) {
      final tId = res['threadId'] as int;
      final eMs = res['elapsedMs'] as double;
      threadTimes[tId] = eMs;
      log("  │ Thread [$tId] Execution Time: ${eMs.toStringAsFixed(3)} ms (${buckets[tId].length} recs)");
    }

    final totalInjected = dataLines.length;
    final double overallTps = (totalInjected * 1000.0) / totalMs;

    log("╔═══════════════════════════════════════════════════════════════════╗");
    log("║  [4-THREAD BUCKET STRESS REPORT]                                  ║");
    log("╠═══════════════════════════════════════════════════════════════════╣");
    log("  │ Total Injected Records : $totalInjected");
    log("  │ Total Elapsed Time     : ${totalMs.toStringAsFixed(3)} ms");
    log("  │ Overall Throughput     : ${overallTps.toStringAsFixed(2)} TPS");
    log("╚═══════════════════════════════════════════════════════════════════╝");

    final int commitSt = ezDb.commit(dbHandle);
    if (commitSt != 0) {
      log("[WARN] ezDb.commit returned non-zero status: ${ezDb.getDetailedError(commitSt)}");
    }

    // 6. Build tag index (idx_code -> code)
    log("=== Building Tag Index (idx_code -> code) ===");
    final int idxSt = ezDb.createIndex(dbHandle, "idx_code", "code", isUnique: true);
    if (idxSt != 0) {
      log("[ERROR] createIndex failed: ${ezDb.getDetailedError(idxSt)}");
    }

    // 7. Locate record '2330' and parse payload via EzRecordReader
    log("=== Executing seekByName for '2330' ===");
    if (ezDb.seekByName(dbHandle, "idx_code", ["2330"])) {
      int count = 0;

      while (true) {
        // Read raw binary buffer directly using EzRecordReader
        final reader = ezDb.readRecord(dbHandle);
        if (reader == null) break;

        final code = reader.stringAt(10, 12);
        if (!code.startsWith("2330")) break;

        final date = reader.stringAt(0, 10);
        final name = reader.stringAt(22, 36);
        final closePrice = reader.doubleAt(104, 8);

        count++;
        log("  [FETCH SUCCESS #$count] Date: $date | Code: $code | Name: $name | Close: $closePrice");

        if (ezDb.skip(dbHandle, 1) != 0) break;
      }
      log(">>> 2330 rolling read complete, matched records: $count");
    } else {
      log("[INFO] Target '2330' not found");
    }

    // 8. Safely close database
    ezDb.closeAll();
    log("All operations completed successfully. WorkArea closed safely.");

    return StressReport(
      totalRecords: totalInjected,
      totalElapsedMs: totalMs,
      tps: overallTps,
      threadTimesMs: threadTimes,
      logs: logs,
    );
  }
}
