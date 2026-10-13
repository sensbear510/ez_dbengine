/* =================================================================================
 * ez_stress_master.js - EDB 2.0 Node.js Physical Stress Master & Benchmark
 * ================================================================================= */

const fs = require('fs');
const readline = require('readline');
const { EzDbEngine, FieldDefinition, FieldType } = require('./ez_dbengine');

const NUM_THREADS = 4;
const TEST_DB = 'ez_full_stress.ebf';
const CSV_FILE = 'daily_2026-03-19.csv';

async function cleanOldFiles() {
    try {
        const dirFiles = await fs.promises.readdir(process.cwd());
        for (const file of dirFiles) {
            if (file.endsWith('.ebf') || file.endsWith('.edx')) {
                try {
                    await fs.promises.unlink(file);
                    console.log(`Cleaned residual file: ${file}`);
                } catch (e) {}
            }
        }
    } catch (err) {
        console.error('Error cleaning residual files:', err);
    }
}

async function run4BucketStressTest(engine, handle, csvFilename) {
    const buckets = Array.from({ length: NUM_THREADS }, () => []);
    let totalRecords = 0;

    console.log("\n=== [4-Bucket Stress] Parsing CSV and Distributing into Buckets ===");

    if (fs.existsSync(csvFilename)) {
        const fileStream = fs.createReadStream(csvFilename);
        const rl = readline.createInterface({ input: fileStream, crlfDelay: Infinity });

        let isHeader = true;
        for await (const line of rl) {
            if (isHeader) { isHeader = false; continue; }
            const trimmed = line.trim();
            if (trimmed) {
                buckets[totalRecords % NUM_THREADS].push(trimmed);
                totalRecords++;
            }
        }
    } else {
        console.log("[WARNING] CSV file not found, generating 10,000 mock records...");
        for (let i = 0; i < 10000; i++) {
            buckets[i % NUM_THREADS].push("2026-03-19,0050,Yuanta Taiwan Top 50,1523000,213220000.00,140.00,141.50,139.80,141.00,1.00,1250");
            totalRecords++;
        }
    }

    buckets.forEach((bucket, i) => {
        console.log(`  ├─► Bucket [${i}] loaded with ${bucket.length.toLocaleString()} records`);
    });

    console.log("\n=== [4-Bucket Stress] Executing Native ez_db_append via Shared Handle ===");

    const stressStart = performance.now();
    const workerTimes = new Array(NUM_THREADS);

    for (let t = 0; t < NUM_THREADS; t++) {
        const wStart = performance.now();
        const bucket = buckets[t];
        for (let i = 0; i < bucket.length; i++) {
            const st = engine.append(handle, bucket[i], 1, ',');
            if (st !== 0) {
                console.error(`[Worker ${t} Error] ${engine.getDetailedError(st)}`);
            }
        }
        workerTimes[t] = performance.now() - wStart;
    }

    engine.commit(handle);

    const totalMs = performance.now() - stressStart;
    const tps = totalMs > 0 ? (totalRecords * 1000.0) / totalMs : 0;

    console.log("╔═══════════════════════════════════════════════════════════════════╗");
    console.log("║  [4-THREAD BUCKET STRESS REPORT - NODE.JS STRICT ALIGNED SDK]     ║");
    console.log("╠═══════════════════════════════════════════════════════════════════╣");
    for (let i = 0; i < NUM_THREADS; i++) {
        console.log(`  │ Thread [${i}] Execution Time: ${workerTimes[i].toFixed(3).padStart(8)} ms (${buckets[i].length.toLocaleString()} recs)`);
    }
    console.log("  ├─────────────────────────────────────────────────────────────────┤");
    console.log(`  │ Total Injected Records : ${totalRecords.toLocaleString()}`);
    console.log(`  │ Total Elapsed Time     : ${totalMs.toFixed(3).padStart(8)} ms`);
    console.log(`  │ Overall Throughput     : ${tps.toFixed(2).padStart(8)} TPS`);
    console.log("╚═══════════════════════════════════════════════════════════════════╝");
}

async function main() {
    await cleanOldFiles();
    console.log("=== EDB 2.0 Node.js Physical Stress Master (Stateless Singleton) ===");

    const totalStart = performance.now();
    const engine = EzDbEngine.getInstance();

    const schema = [
        new FieldDefinition("date", FieldType.Character, 10, 0),
        new FieldDefinition("code", FieldType.Character, 12, 0),
        new FieldDefinition("name", FieldType.Character, 36, 0),
        new FieldDefinition("trade_volume", FieldType.Numeric, 10, 0),
        new FieldDefinition("trade_amount", FieldType.Numeric, 12, 2),
        new FieldDefinition("open", FieldType.Numeric, 8, 2),
        new FieldDefinition("high", FieldType.Numeric, 8, 2),
        new FieldDefinition("low", FieldType.Numeric, 8, 2),
        new FieldDefinition("close", FieldType.Numeric, 8, 2),
        new FieldDefinition("diff", FieldType.Numeric, 8, 2),
        new FieldDefinition("trade_count", FieldType.Numeric, 8, 0)
    ];

    const createSt = engine.createDatabase(TEST_DB, schema);
    if (createSt !== 0) {
        console.error(`[ERROR] createDatabase failed: ${engine.getDetailedError(createSt)}`);
        return;
    }

    const handle = engine.use(TEST_DB);
    engine.debugDumpWorkarea(handle);

    await run4BucketStressTest(engine, handle, CSV_FILE);

    const idxStart = performance.now();
    const idxSt = engine.createIndex(handle, "idx_code", "code", true);
    const idxElapsed = performance.now() - idxStart;
    console.log(`<<< ez_db_create_index | Status: ${idxSt} | Tag: idx_code | Time: ${idxElapsed.toFixed(3)} ms`);
    if (idxSt !== 0) {
        console.error(`[ERROR] createIndex failed: ${engine.getDetailedError(idxSt)}`);
    }

    if (engine.seekByTag(handle, "idx_code", "2330")) {
        let rollingCount = 0;
        while (true) {
            const rawBuf = engine.getRecord(handle, false, 0, "idx_code");
            if (!rawBuf) break;

            const codeStr = rawBuf.toString('utf8', 10, 22).replace(/\0/g, '').trim();
            if (!codeStr.startsWith("2330")) break;

            rollingCount++;
            if (engine.skip(handle, 1, 0, "idx_code") !== 0) break;
        }
        console.log(`>>> 2330 Rolling Read Count: ${rollingCount}`);
    } else {
        console.log("[INFO] Target '2330' not found");
    }

    engine.close(handle);

    const totalElapsed = performance.now() - totalStart;
    console.log(`\nTotal Performance: ${totalElapsed.toFixed(3)} ms`);
}

main().catch(console.error);