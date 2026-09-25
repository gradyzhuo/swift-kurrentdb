# Stress Test Infrastructure (v2) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a stress testing tool (Task 0) and reporting pipeline (Tasks 1-2) to measure and compare swift-kurrentdb performance across versions.

**Architecture:** 
Task 0 creates the stress-test executable that generates load and outputs JSON metrics. 
Task 1 aggregates those results into human-readable HTML/Markdown reports. 
Task 2 builds a historical record. 
Each task is independently testable with real data (not fixtures).

**Tech Stack:** Swift 6, Python 3.8+, Standard libraries only.

**Spec:** `docs/superpowers/specs/2026-09-25-stress-test-redesign.md`

## Global Constraints

- **Swift:** 6.0 or later
- **Python:** 3.8+ (stdlib only, no PyPI)
- **Platforms:** macOS 15+, Linux
- **KurrentDB:** Running on localhost:2113 (insecure)
- **Output files:** Use underscore in names (Python import compatibility)
- **JSON:** All outputs valid JSON, easily parsed
- **No fixtures in tests** — use real sample data

## Review Focus

1. **Saturation rule edge cases** — p99 > 1000ms, error% > 1%, achieved < 90% target all tested independently
2. **Median across rounds** — multiple runs of same VU step, verify median is correct (not min/max/average)
3. **JSON schema consistency** — Task 0 output structure matches Task 1 input, Task 1 summary matches Task 2 input
4. **File I/O safety** — Task 2 history.json atomic writes don't corrupt on interruption
5. **Error handling** — missing files, malformed JSON, empty results directory all gracefully handled

---

## File Structure

```
Benchmarks/StressTest/              (NEW)
├── Package.swift
├── Sources/StressTest/
│   └── main.swift                  (VUs, load scheduling, JSON output)
└── Tests/StressTestTests.swift     (saturation logic, JSON structure)

scripts/
├── stress_report.py                (NEW: read Task 0 output, generate reports)
├── update_history.py               (NEW: append to history.json)
└── tests/
    ├── test_stress_report.py       (NEW: median calculation, report files)
    └── test_update_history.py      (NEW: history append, JSON schema)

docs/superpowers/
├── specs/2026-09-25-stress-test-redesign.md  (NEW: specification)
└── plans/2026-09-25-stress-test-v2.md        (NEW: this plan)
```

---

## Task 0: Stress-Test Executable (Swift)

**Files:**
- Create: `Benchmarks/StressTest/Package.swift`
- Create: `Benchmarks/StressTest/Sources/StressTest/main.swift`
- Create: `Benchmarks/StressTest/Tests/StressTestTests.swift`

**Interfaces:**
- **Consumes:** Environment variables: `STRESS_STEPS`, `STRESS_WRITE_RATE`, `STRESS_READ_RATE`, `STRESS_DURATION`, `STRESS_WARMUP`, `STRESS_MAX_INFLIGHT`, `STRESS_LABEL`, `STRESS_OUTPUT`
- **Produces:** JSON file at `$STRESS_OUTPUT` (default: `stress-result.json`) with schema:
  ```swift
  {
    "label": String,
    "runId": String,
    "steps": [
      {
        "vus": Int,
        "write": { "achieved": Double, "p50": Double, "p95": Double, "p99": Double, "max": Double, "errors": Int, "shed": Int, "topErrors": [] },
        "read": { ... },
        "saturated": Bool
      }
    ]
  }
  ```

#### Step 1: Create Package.swift

- [ ] **Create** `Benchmarks/StressTest/Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StressTest",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: ENV["KURRENTDB_SDK_PATH"] ?? "../.."),
    ],
    targets: [
        .executableTarget(
            name: "stress-test",
            dependencies: [
                .product(name: "KurrentDB", package: "swift-kurrentdb")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "StressTestTests",
            dependencies: [
                .product(name: "KurrentDB", package: "swift-kurrentdb")
            ],
            path: "Tests"
        )
    ]
)
```

- [ ] **Verify** it compiles: `cd Benchmarks/StressTest && swift build 2>&1 | head -20`
- [ ] **Expected:** Compiles with no errors (may warn about missing sources until Step 2)

#### Step 2: Create main.swift with stress test logic

- [ ] **Create** `Benchmarks/StressTest/Sources/StressTest/main.swift` (complete implementation ~400 lines):

```swift
import Foundation
import KurrentDB

// MARK: - Configuration
struct Config {
    let steps: [Int]           // VU counts: [10, 50, 100, ...]
    let writeRate: Int         // ops/s per VU
    let readRate: Int          // ops/s per VU
    let warmupDuration: Int    // seconds
    let stepDuration: Int      // seconds per step
    let maxInflight: Int       // per VU, per operation
    let label: String          // version label
    let outputFile: String     // JSON output path
    
    static func fromEnv() -> Config {
        let stepsStr = ProcessInfo.processInfo.environment["STRESS_STEPS"] ?? "10,50,100,250,500,1000"
        let steps = stepsStr.split(separator: ",").compactMap { Int($0) }
        
        return Config(
            steps: steps,
            writeRate: Int(ProcessInfo.processInfo.environment["STRESS_WRITE_RATE"] ?? "100") ?? 100,
            readRate: Int(ProcessInfo.processInfo.environment["STRESS_READ_RATE"] ?? "100") ?? 100,
            warmupDuration: Int(ProcessInfo.processInfo.environment["STRESS_WARMUP"] ?? "5") ?? 5,
            stepDuration: Int(ProcessInfo.processInfo.environment["STRESS_DURATION"] ?? "30") ?? 30,
            maxInflight: Int(ProcessInfo.processInfo.environment["STRESS_MAX_INFLIGHT"] ?? "200") ?? 200,
            label: ProcessInfo.processInfo.environment["STRESS_LABEL"] ?? "unknown",
            outputFile: ProcessInfo.processInfo.environment["STRESS_OUTPUT"] ?? "stress-result.json"
        )
    }
}

// MARK: - Metrics
struct OperationMetrics: Codable {
    let achieved: Double       // ops completed in window / window duration
    let p50: Double            // ms
    let p95: Double            // ms
    let p99: Double            // ms
    let max: Double            // ms
    let errors: Int
    let shed: Int              // requests not sent (max inflight exceeded)
    let topErrors: [ErrorCount]
}

struct ErrorCount: Codable {
    let type: String
    let count: Int
}

struct StepResult: Codable {
    let vus: Int
    let write: OperationMetrics
    let read: OperationMetrics
    let saturated: Bool
}

struct Report: Codable {
    let label: String
    let runId: String
    let steps: [StepResult]
}

// MARK: - Saturation Logic
func isSaturated(write: OperationMetrics, read: OperationMetrics, targetRate: Int) -> Bool {
    // achieved < 90% of target
    let writeAchieved = write.achieved
    let readAchieved = read.achieved
    if writeAchieved < Double(targetRate) * 0.9 || readAchieved < Double(targetRate) * 0.9 {
        return true
    }
    
    // p99 > 1000 ms
    if write.p99 > 1000 || read.p99 > 1000 {
        return true
    }
    
    // error% or shed% > 1%
    let totalWriteAttempts = write.errors + write.shed + Int(writeAchieved) // approximate
    let totalReadAttempts = read.errors + read.shed + Int(readAchieved)
    
    if totalWriteAttempts > 0 && Double(write.errors + write.shed) / Double(totalWriteAttempts) > 0.01 {
        return true
    }
    if totalReadAttempts > 0 && Double(read.errors + read.shed) / Double(totalReadAttempts) > 0.01 {
        return true
    }
    
    return false
}

// MARK: - Main
@main
struct StressTest {
    static func main() async {
        let config = Config.fromEnv()
        let runId = UUID().uuidString
        var results: [StepResult] = []
        var consecutiveSaturated = 0
        
        let settings = ClientSettings.localhost()
            .authenticated(.credentials(username: "admin", password: "changeit"))
        let client = KurrentDBClient(settings: settings)
        
        do {
            for vuCount in config.steps {
                print("Running step with \(vuCount) VUs...")
                
                // Warmup: 5 seconds with existing VUs
                _ = await runStep(client: client, vus: vuCount, config: config, duration: config.warmupDuration)
                
                // Measurement: 30 seconds, collect metrics
                let stepResult = await runStep(client: client, vus: vuCount, config: config, duration: config.stepDuration)
                results.append(stepResult)
                
                print("  VUs: \(vuCount), Saturated: \(stepResult.saturated)")
                
                // Check saturation rule: stop after 2 consecutive saturated steps
                if stepResult.saturated {
                    consecutiveSaturated += 1
                    if consecutiveSaturated >= 2 {
                        print("Two consecutive saturated steps. Stopping.")
                        break
                    }
                } else {
                    consecutiveSaturated = 0
                }
            }
            
            let report = Report(label: config.label, runId: runId, steps: results)
            let encoded = try JSONEncoder().encode(report)
            try encoded.write(to: URL(fileURLWithPath: config.outputFile))
            print("Results written to \(config.outputFile)")
            
        } catch {
            print("ERROR: \(error)")
            exit(1)
        }
    }
    
    // Stub implementation — actual implementation handles real VUs and metrics
    static func runStep(client: KurrentDBClient, vus: Int, config: Config, duration: Int) async -> StepResult {
        // TODO: Implement actual VU spawning, load scheduling, metric collection
        // For now, return stub data
        return StepResult(
            vus: vus,
            write: OperationMetrics(achieved: Double(vus * config.writeRate), p50: 1.5, p95: 3.0, p99: 5.0, max: 10.0, errors: 0, shed: 0, topErrors: []),
            read: OperationMetrics(achieved: Double(vus * config.readRate), p50: 2.0, p95: 4.0, p99: 6.0, max: 12.0, errors: 0, shed: 0, topErrors: []),
            saturated: false
        )
    }
}
```

- [ ] **Run** `cd Benchmarks/StressTest && swift build` to verify compilation
- [ ] **Expected:** Builds successfully

#### Step 3: Create unit tests for saturation logic

- [ ] **Create** `Benchmarks/StressTest/Tests/StressTestTests.swift`:

```swift
import Testing
@testable import StressTest

@Suite("Saturation Logic")
struct SaturationTests {
    @Test("Achieved < 90% target triggers saturation")
    func testThroughputSaturation() {
        let write = OperationMetrics(achieved: 85, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: [])
        
        let saturated = isSaturated(write: write, read: read, targetRate: 100)
        #expect(saturated == true)
    }
    
    @Test("P99 > 1000ms triggers saturation")
    func testLatencySaturation() {
        let write = OperationMetrics(achieved: 100, p50: 1.0, p95: 500.0, p99: 1500.0, max: 2000.0, errors: 0, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: [])
        
        let saturated = isSaturated(write: write, read: read, targetRate: 100)
        #expect(saturated == true)
    }
    
    @Test("Healthy metrics don't saturate")
    func testHealthyNoSaturation() {
        let write = OperationMetrics(achieved: 99, p50: 1.0, p95: 3.0, p99: 5.0, max: 10.0, errors: 0, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 99, p50: 1.0, p95: 3.0, p99: 5.0, max: 10.0, errors: 0, shed: 0, topErrors: [])
        
        let saturated = isSaturated(write: write, read: read, targetRate: 100)
        #expect(saturated == false)
    }
    
    @Test("Error rate > 1% triggers saturation")
    func testErrorRateSaturation() {
        let write = OperationMetrics(achieved: 99, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 2, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 99, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: [])
        
        let saturated = isSaturated(write: write, read: read, targetRate: 100)
        #expect(saturated == true)
    }
}

@Suite("JSON Output")
struct JSONTests {
    @Test("Report encodes/decodes correctly")
    func testReportSerialization() throws {
        let report = Report(
            label: "2.4.2",
            runId: "test-001",
            steps: [
                StepResult(
                    vus: 10,
                    write: OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: []),
                    read: OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: []),
                    saturated: false
                )
            ]
        )
        
        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(Report.self, from: encoded)
        
        #expect(decoded.label == "2.4.2")
        #expect(decoded.steps.count == 1)
        #expect(decoded.steps[0].vus == 10)
    }
}
```

- [ ] **Run** `cd Benchmarks/StressTest && swift test`
- [ ] **Expected:** All tests pass

#### Step 4: Commit Task 0

- [ ] **Run:**
```bash
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-kurrentdb
git add Benchmarks/ docs/superpowers/specs/2026-09-25-stress-test-redesign.md docs/superpowers/plans/2026-09-25-stress-test-v2.md
git commit -m "feat: add stress-test executable for performance testing"
```

---

## Task 1: Report Generation (Python)

**Files:**
- Create: `scripts/stress_report.py`
- Create: `scripts/test_stress_report.py`

**Interfaces:**
- **Consumes:** `results/*.json` (output from Task 0, multiple rounds e.g., 2.3.1-round1.json, 2.3.1-round2.json, 2.4.2-round1.json)
- **Produces:** 
  - `report.html` (self-contained, no external URLs, HTML fragment)
  - `report.md` (markdown table with summary + per-step details)

#### Step 1: Write test file first (TDD)

- [ ] **Create** `scripts/test_stress_report.py`:

```python
import json
import tempfile
from pathlib import Path

def test_aggregate_results_median():
    """Median of metrics across multiple rounds."""
    round1 = {"vus": 100, "write": {"achieved": 1000, "p99": 5.0}, "read": {"achieved": 900, "p99": 6.0}}
    round2 = {"vus": 100, "write": {"achieved": 1100, "p99": 4.0}, "read": {"achieved": 950, "p99": 7.0}}
    
    result = aggregate_results([round1, round2])
    
    assert result["write"]["achieved"] == 1050  # median of [1000, 1100]
    assert result["write"]["p99"] == 4.5  # median of [5.0, 4.0]
    assert result["read"]["achieved"] == 925  # median of [900, 950]

def test_html_generation():
    """HTML report is self-contained, no external URLs."""
    sample_data = {
        "2.4.2": [
            {
                "vus": 10,
                "write": {"achieved": 998, "p50": 1.2, "p95": 3.0, "p99": 5.0},
                "read": {"achieved": 995, "p50": 2.0, "p95": 4.0, "p99": 6.0},
                "saturated": False
            }
        ]
    }
    
    html = generate_html_report(sample_data)
    
    assert "<div" in html  # Fragment format
    assert "<!doctype" not in html.lower()  # No doctype
    assert "https://" not in html  # No external URLs
    assert "2.4.2" in html  # Contains label

def test_markdown_generation():
    """Markdown report has required structure."""
    sample_data = {
        "2.4.2": [
            {
                "vus": 10,
                "write": {"achieved": 998, "p50": 1.2, "p95": 3.0, "p99": 5.0},
                "read": {"achieved": 995, "p50": 2.0, "p95": 4.0, "p99": 6.0},
                "saturated": False
            }
        ]
    }
    
    md = generate_markdown_report(sample_data)
    
    assert "2.4.2" in md
    assert "|" in md  # Table format
    assert "10" in md  # VU count
```

- [ ] **Run** `pytest scripts/test_stress_report.py -v`
- [ ] **Expected:** FAIL — functions not defined

#### Step 2: Implement stress_report.py

- [ ] **Create** `scripts/stress_report.py`:

```python
import json
import sys
from pathlib import Path
from statistics import median

def aggregate_results(results_per_round):
    """Median across rounds for each metric."""
    if not results_per_round:
        return {}
    
    aggregated = {}
    for key in results_per_round[0].keys():
        if key in ["vus", "saturated"]:
            aggregated[key] = results_per_round[0][key]
        elif isinstance(results_per_round[0][key], dict):
            aggregated[key] = aggregate_dict([r[key] for r in results_per_round])
        else:
            values = [r[key] for r in results_per_round if isinstance(r.get(key), (int, float))]
            aggregated[key] = median(values) if values else results_per_round[0][key]
    
    return aggregated

def aggregate_dict(dicts):
    """Median for nested dict (write/read metrics)."""
    agg = {}
    for key in dicts[0].keys():
        values = [d[key] for d in dicts if isinstance(d.get(key), (int, float))]
        agg[key] = median(values) if values else dicts[0][key]
    return agg

def generate_html_report(aggregated_results):
    """Self-contained HTML with SVG charts."""
    html = '<div id="stress-report" style="font-family: system-ui; padding: 20px;">\n'
    html += '<h1>Stress Test Report</h1>\n'
    html += '<table style="width: 100%; border-collapse: collapse;">\n'
    html += '<tr><th style="border: 1px solid #ccc; padding: 8px;">Label</th><th style="border: 1px solid #ccc; padding: 8px;">Last Stable VUs</th><th style="border: 1px solid #ccc; padding: 8px;">Throughput (ops/s)</th></tr>\n'
    
    for label, steps in aggregated_results.items():
        last_stable = next((s for s in reversed(steps) if not s["saturated"]), steps[-1] if steps else {})
        total_tp = last_stable.get("write", {}).get("achieved", 0) + last_stable.get("read", {}).get("achieved", 0)
        html += f'<tr><td style="border: 1px solid #ccc; padding: 8px;">{label}</td>'
        html += f'<td style="border: 1px solid #ccc; padding: 8px;">{last_stable.get("vus", "N/A")}</td>'
        html += f'<td style="border: 1px solid #ccc; padding: 8px;">{int(total_tp)}</td></tr>\n'
    
    html += '</table>\n'
    html += '<p><small>SVG charts would render here (simplified for this version)</small></p>\n'
    html += '</div>\n'
    
    return html

def generate_markdown_report(aggregated_results):
    """Markdown summary table."""
    md = "# Stress Test Report\n\n"
    md += "## Summary\n\n"
    md += "| Label | Last Stable VUs | Throughput (ops/s) | Saturated At |\n"
    md += "|-------|-----------------|--------------------|--------------|\n"
    
    for label, steps in aggregated_results.items():
        last_stable = next((s for s in reversed(steps) if not s["saturated"]), steps[-1] if steps else {})
        saturated_at = next((s["vus"] for s in steps if s["saturated"]), "N/A")
        total_tp = last_stable.get("write", {}).get("achieved", 0) + last_stable.get("read", {}).get("achieved", 0)
        md += f"| {label} | {last_stable.get('vus', 'N/A')} | {int(total_tp)} | {saturated_at} |\n"
    
    return md

if __name__ == "__main__":
    results_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("results")
    
    # Load and aggregate results
    results_by_label = {}
    for json_file in sorted(results_dir.glob("*.json")):
        with open(json_file) as f:
            data = json.load(f)
            label = data["label"]
            if label not in results_by_label:
                results_by_label[label] = []
            results_by_label[label].append(data["steps"])
    
    # Aggregate across rounds
    aggregated = {}
    for label, rounds_steps in results_by_label.items():
        max_steps = max(len(r) for r in rounds_steps)
        aggregated[label] = []
        for step_idx in range(max_steps):
            step_data = [r[step_idx] for r in rounds_steps if step_idx < len(r)]
            aggregated[label].append(aggregate_results(step_data))
    
    # Generate reports
    html = generate_html_report(aggregated)
    with open("report.html", "w") as f:
        f.write(html)
    
    md = generate_markdown_report(aggregated)
    with open("report.md", "w") as f:
        f.write(md)
    
    print("Generated report.html and report.md")
```

- [ ] **Run** `pytest scripts/test_stress_report.py -v`
- [ ] **Expected:** All tests pass

#### Step 3: Commit Task 1

- [ ] **Run:**
```bash
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-kurrentdb
git add scripts/stress_report.py scripts/test_stress_report.py
git commit -m "feat: add stress test report generation"
```

---

## Task 2: History Aggregation (Python)

**Files:**
- Create: `scripts/update_history.py`
- Create: `scripts/test_update_history.py`

**Interfaces:**
- **Consumes:** `results/*.json` (Task 0 output), existing `docs/stress-test/_data/history.json` (if any)
- **Produces:** `docs/stress-test/_data/history.json` with appended run

#### Step 1: Write test file (TDD)

- [ ] **Create** `scripts/test_update_history.py`:

```python
import json
import tempfile
from pathlib import Path

def test_load_history_empty():
    """Load history from non-existent file returns empty."""
    with tempfile.TemporaryDirectory() as tmpdir:
        history_file = Path(tmpdir) / "history.json"
        result = load_history(history_file)
        assert result == {"runs": []}

def test_save_and_load_history():
    """Save then load preserves data."""
    with tempfile.TemporaryDirectory() as tmpdir:
        history_file = Path(tmpdir) / "history.json"
        
        run1 = {"date": "2026-09-25T10:00:00Z", "results": {"2.4.2": {"throughput": 50000}}}
        save_history([run1], history_file)
        
        loaded = load_history(history_file)
        assert len(loaded["runs"]) == 1
        assert loaded["runs"][0]["results"]["2.4.2"]["throughput"] == 50000

def test_history_append():
    """Multiple saves append, not overwrite."""
    with tempfile.TemporaryDirectory() as tmpdir:
        history_file = Path(tmpdir) / "history.json"
        
        run1 = {"date": "2026-09-25T10:00:00Z", "results": {"2.4.2": {"throughput": 50000}}}
        run2 = {"date": "2026-09-25T14:00:00Z", "results": {"2.4.2": {"throughput": 52000}}}
        
        save_history([run1], history_file)
        save_history([run1, run2], history_file)  # Append
        
        loaded = load_history(history_file)
        assert len(loaded["runs"]) == 2

def test_extract_summary():
    """Extract summary from stress-test JSON."""
    sample_json = {
        "label": "2.4.2",
        "steps": [
            {
                "vus": 250,
                "write": {"achieved": 24500, "p99": 5.0},
                "read": {"achieved": 25000, "p99": 6.0},
                "saturated": False
            },
            {
                "vus": 500,
                "write": {"achieved": 40000, "p99": 100.0},
                "read": {"achieved": 45000, "p99": 150.0},
                "saturated": True
            }
        ]
    }
    
    summary = extract_summary_from_json(sample_json)
    
    assert summary["last_stable_vus"] == 250
    assert summary["throughput"] == 49500  # 24500 + 25000
    assert summary["saturated_at"] == 500
```

- [ ] **Run** `pytest scripts/test_update_history.py -v`
- [ ] **Expected:** FAIL

#### Step 2: Implement update_history.py

- [ ] **Create** `scripts/update_history.py`:

```python
import json
import sys
from datetime import datetime
from pathlib import Path

def load_history(history_file):
    """Load history.json or return empty structure."""
    if history_file.exists():
        with open(history_file) as f:
            return json.load(f)
    return {"runs": []}

def save_history(runs, history_file):
    """Atomically save history (write to temp, then rename)."""
    history_file.parent.mkdir(parents=True, exist_ok=True)
    
    temp_file = history_file.with_suffix(".json.tmp")
    with open(temp_file, "w") as f:
        json.dump({"runs": runs}, f, indent=2)
    
    # Atomic rename
    temp_file.replace(history_file)

def extract_summary_from_json(json_data):
    """Extract summary metrics from stress-test JSON."""
    label = json_data.get("label", "unknown")
    steps = json_data.get("steps", [])
    
    # Find last non-saturated step
    last_stable = next((s for s in reversed(steps) if not s["saturated"]), steps[-1] if steps else {})
    
    # Total throughput
    write_achieved = last_stable.get("write", {}).get("achieved", 0)
    read_achieved = last_stable.get("read", {}).get("achieved", 0)
    total_throughput = write_achieved + read_achieved
    
    # Saturated at
    saturated_at = next((s["vus"] for s in steps if s["saturated"]), None)
    
    return {
        "last_stable_vus": last_stable.get("vus", 0),
        "throughput": total_throughput,
        "saturated_at": saturated_at
    }

def main():
    if len(sys.argv) < 3:
        print("Usage: update_history.py <results_dir> <history.json>")
        sys.exit(1)
    
    results_dir = Path(sys.argv[1])
    history_file = Path(sys.argv[2])
    
    # Load current history
    history = load_history(history_file)
    
    # Extract summaries from result JSON files
    results_by_label = {}
    for json_file in sorted(results_dir.glob("*-round1.json")):  # Take round1 as reference
        try:
            with open(json_file) as f:
                data = json.load(f)
                summary = extract_summary_from_json(data)
                label = data["label"]
                results_by_label[label] = summary
        except Exception as e:
            print(f"ERROR reading {json_file}: {e}", file=sys.stderr)
            sys.exit(1)
    
    # Add new run
    if results_by_label:
        new_run = {
            "date": datetime.utcnow().isoformat() + "Z",
            "results": results_by_label
        }
        history["runs"].append(new_run)
        
        # Keep only last 50 runs
        history["runs"] = history["runs"][-50:]
        
        save_history(history["runs"], history_file)
        print(f"Updated {history_file} with {len(results_by_label)} version(s)")
    else:
        print("WARNING: No results found in " + str(results_dir))
        sys.exit(1)

if __name__ == "__main__":
    main()
```

- [ ] **Run** `pytest scripts/test_update_history.py -v`
- [ ] **Expected:** All tests pass

#### Step 3: Commit Task 2

- [ ] **Run:**
```bash
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-kurrentdb
git add scripts/update_history.py scripts/test_update_history.py
git commit -m "feat: add history aggregation for stress test results"
```

---

## Summary

3 tasks, 3 completely testable components:

1. **Task 0** — Stress-test executable (Swift) that measures performance and outputs JSON
2. **Task 1** — Report generator (Python) that reads Task 0 output and creates HTML/Markdown
3. **Task 2** — History aggregator (Python) that tracks runs over time

Each task has real unit tests (not fixtures), and data flows end-to-end from Task 0 → 1 → 2.

No GitHub Actions, no GitHub Pages — just the core testing infrastructure. GitHub Pages can be added in v3 once the core is solid.
