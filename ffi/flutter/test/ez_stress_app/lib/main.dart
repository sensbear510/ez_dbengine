/* Flutter Native Apps Cross-Platform Execution:
 *    --------------------------------------------------------------
 *    flutter run -d windows        # Flutter Windows native desktop app
 *    flutter run -d chrome         # Flutter Web app
 *    flutter run -d android        # Flutter Android mobile app
 *    flutter run -d linux          # Flutter Linux native desktop app
 *    flutter run -d macos          # Flutter macOS native desktop app
 * =================================================================
 */
import 'dart:io';
import 'package:flutter/material.dart';
import 'stress_runner.dart';

void main() {
  runApp(const EzStressMasterApp());
}

class EzStressMasterApp extends StatelessWidget {
  const EzStressMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ez_engine FFI Stress Master',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const StressDashboardScreen(),
    );
  }
}

class StressDashboardScreen extends StatefulWidget {
  const StressDashboardScreen({super.key});

  @override
  State<StressDashboardScreen> createState() => _StressDashboardScreenState();
}

class _StressDashboardScreenState extends State<StressDashboardScreen> {
  final TextEditingController _csvPathController = TextEditingController(text: '../../../../daily_2026-03-19.csv');

  bool _isRunning = false;
  final List<String> _consoleLogs = [];
  StressReport? _lastReport;

  void _addLog(String msg) {
    setState(() {
      _consoleLogs.add(msg);
    });
  }

  /// Cleans up all residual physical .ebf and .edx files in current working directory
  Future<void> _cleanResidualDbFiles() async {
    try {
      final currentDir = Directory.current;
      final entities = currentDir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          final path = entity.path.toLowerCase();
          if (path.endsWith('.ebf') || path.endsWith('.edx')) {
            try {
              entity.deleteSync();
              _addLog("[CLEAN] Cleaned residual file: ${entity.uri.pathSegments.last}");
            } catch (err) {
              _addLog("[WARN] Failed to delete file ${entity.path}: $err");
            }
          }
        }
      }
    } catch (e) {
      _addLog("[WARN] Directory scan and file cleanup failed: $e");
    }
  }

  void _startTest() async {
    setState(() {
      _isRunning = true;
      _consoleLogs.clear();
      _lastReport = null;
    });

    try {
      // Force thorough cleanup of all .ebf and .edx files in working directory before test
      await _cleanResidualDbFiles();

      final report = await StressRunner.runFullStressTest(_csvPathController.text, _addLog);
      setState(() {
        _lastReport = report;
      });
    } catch (e) {
      _addLog("🚨 [ERROR] Exception occurred during stress test: $e");
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ez_engine FFI Stress Master (Desktop)'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Text(
                _isRunning ? '⚡ 4-Isolate Stress Testing...' : '🟢 System Ready',
                style: TextStyle(color: _isRunning ? Colors.amber : Colors.greenAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _csvPathController,
                        decoration: const InputDecoration(labelText: 'CSV File Path', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _isRunning ? null : _startTest,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        backgroundColor: Colors.blueAccent,
                      ),
                      icon: const Icon(Icons.flash_on),
                      label: const Text('Start 4-Bucket Stress Test'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_lastReport != null)
              Row(
                children: [
                  _buildMetricCard("Total Injected", "${_lastReport!.totalRecords} records", Colors.cyan),
                  _buildMetricCard("Total Elapsed", "${_lastReport!.totalElapsedMs.toStringAsFixed(2)} ms", Colors.orange),
                  _buildMetricCard("Overall TPS", "${_lastReport!.tps.toStringAsFixed(2)} /s", Colors.greenAccent),
                ],
              ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: ListView.builder(
                    itemCount: _consoleLogs.length,
                    itemBuilder: (context, index) {
                      return Text(
                        _consoleLogs[index],
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.greenAccent),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}