# Stress Test Infrastructure — Redesigned Specification

> **Date:** 2026-09-25  
> **Scope:** Task 0-2 only (stress-test tool + reporting). GitHub Pages deferred to v2.

## Goal

Create a stress testing harness to compare swift-kurrentdb versions under incremental load.
Find the **saturation point** where each version begins to degrade (throughput drops, latency spikes, errors rise).

## What We Learned (v1 → v2)

**v1 failures:**
1. Assumed stress-test executable already existed (it didn't)
2. Fixture tests instead of real data validation
3. Data computed in multiple places (median calculated 3 different ways)
4. Scattered "last stable" and "saturated at" logic

**v2 fixes:**
1. **Task 0 explicitly creates** the stress-test tool (new)
2. **Real data flows end-to-end** — verify each task's output against actual inputs
3. **Single source of truth** — median and saturation rules computed once
4. **Simpler scope** — Tasks 0-2 only; GitHub Pages in a future PR

---

## Architecture

### Task 0: Benchmarks/StressTest Executable

**Purpose:** Generate load and measure performance

**Input:** Environment variables (STRESS_* settings)

**Output:** `results/<label>-round<R>.json` (one file per run)

```json
{
  "label": "2.4.2",
  "runId": "abc123",
  "steps": [
    {
      "vus": 10,
      "write": {
        "achieved": 998,
        "p50": 1.2, "p95": 3.0, "p99": 5.0, "max": 12.0,
        "errors": 0, "shed": 0,
        "topErrors": []
      },
      "read": { ... },
      "saturated": false
    }
  ]
}
```

**Key details:**
- Virtual users share one `KurrentDBClient`
- 100 writes/s + 100 reads/s per VU
- Steps: 10, 50, 100, 250, 500, 1000 VUs
- Stop after 2 consecutive saturated steps
- Saturation rule: (achieved < 90% target) OR (p99 > 1000ms) OR (error% > 1%)

### Task 1: stress-report.py

**Purpose:** Aggregate results across runs, generate human-readable reports

**Input:** `results/*.json` (from Task 0, multiple rounds)

**Process:**
1. Group by label (e.g., 2.3.1, 2.4.2)
2. For each label, across all rounds, take **median** of each metric
3. Compute summary (last non-saturated step, throughput ratio)

**Output:**
- `report.html` — Self-contained HTML with SVG charts (throughput, latency, errors)
- `report.md` — Markdown table (summary + per-step details)

### Task 2: update-history.py

**Purpose:** Build historical record for trend analysis

**Input:** Results from Task 1, existing `history.json` (if any)

**Output:** `docs/stress-test/_data/history.json`

```json
{
  "runs": [
    {
      "date": "2026-09-25T14:30:00Z",
      "refs": ["2.3.1", "2.4.2"],
      "results": {
        "2.3.1": {
          "last_stable_vus": 250,
          "throughput": 49500,
          "saturated_at": 500
        }
      }
    }
  ]
}
```

**Key details:**
- Append to history (don't overwrite)
- Keep last 50 runs
- Atomic writes (temp file + rename)

---

## Global Constraints

- **Language:** Swift 6, Python 3.8+
- **Dependencies:** Standard libraries only
- **Platforms:** macOS 15+, Linux
- **No external APIs** (KurrentDB on localhost:2113)

---

## Success Criteria

1. ✓ Task 0 executable runs and produces valid JSON
2. ✓ Task 1 script reads Task 0 output and generates both report files
3. ✓ Task 2 script reads Task 1 output and produces history.json
4. ✓ All components tested with real data (not fixtures)
5. ✓ No data duplication or inconsistency
6. ✓ Can compare two versions and measure throughput improvement

---

## Out of Scope (for v2)

- GitHub Actions workflow (v3)
- GitHub Pages dashboard (v3)
- TLS/certificate auth
- Multi-node clusters
- Production deployment

---

## Files to Create

```
Benchmarks/
└── StressTest/
    ├── Package.swift              (new)
    ├── Sources/StressTest/
    │   └── main.swift             (new)
    └── Tests/
        └── StressTestTests.swift   (new)

scripts/
├── stress_report.py               (new, note: underscore)
└── update_history.py              (new, note: underscore)

tests/
└── StressReportTests/
    ├── test_stress_report.py       (new)
    └── test_update_history.py      (new)

docs/
└── superpowers/
    └── specs/
        └── 2026-09-25-stress-test-redesign.md  (this file)
```

---

## Key Decisions

| Decision | Why |
|----------|-----|
| One `KurrentDBClient` per run | Matches real backend usage pattern |
| Median across rounds | Reduces noise from individual variations |
| SVG charts (not Plotly) | Self-contained, no CDN dependency |
| Append-only history | Preserve trend data |
| Python 3.8+ only | No PyPI dependencies |
| Underscore in filenames | Valid Python import names |

---

## Testing Strategy

**Unit tests:** Each task validated with real sample data
- Task 0: JSON output structure, saturation rules
- Task 1: Median calculation, report files exist
- Task 2: History append, JSON schema

**Integration test:** Task 0 → Task 1 → Task 2 pipeline with sample data

**No fixtures** — all tests use real JSON mimicking actual stress-test output
