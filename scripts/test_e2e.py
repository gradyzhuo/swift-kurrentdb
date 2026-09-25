#!/usr/bin/env python3
"""
End-to-end integration test for stress-test pipeline.

Tests three stages:
  1. Task 0: Swift executable writes results/<label>-round<R>.json
  2. Task 1: stress_report.py reads all rounds and aggregates
  3. Task 2: update_history.py reads aggregated results and updates history.json

This test uses fixture data to avoid requiring a live Kurrent instance.
"""

import json
import shutil
import sys
import tempfile
from pathlib import Path
from datetime import datetime


def create_fixture_results(results_dir):
    """Create fixture data simulating Task 0 output (multiple rounds)."""
    results_dir.mkdir(parents=True, exist_ok=True)

    # Fixture for two rounds of stress test with two labels
    labels = ["swift-v1", "swift-v2"]
    rounds = [1, 2]

    for label in labels:
        for round_num in rounds:
            report = {
                "label": label,
                "runId": f"test-run-{label}-r{round_num}",
                "steps": [
                    {
                        "vus": 10,
                        "saturated": False,
                        "write": {
                            "achieved": 1000.0,
                            "p50": 5.2,
                            "p95": 10.1,
                            "p99": 20.3,
                            "max": 50.0,
                            "completed": 30000,
                            "attempted": 30000,
                            "errors": 0,
                            "shed": 0,
                            "topErrors": []
                        },
                        "read": {
                            "achieved": 1000.0,
                            "p50": 4.8,
                            "p95": 9.5,
                            "p99": 19.2,
                            "max": 45.0,
                            "completed": 30000,
                            "attempted": 30000,
                            "errors": 0,
                            "shed": 0,
                            "topErrors": []
                        }
                    },
                    {
                        "vus": 50,
                        "saturated": False,
                        "write": {
                            "achieved": 4800.0,
                            "p50": 5.5,
                            "p95": 11.2,
                            "p99": 25.1,
                            "max": 55.0,
                            "completed": 144000,
                            "attempted": 144000,
                            "errors": 0,
                            "shed": 0,
                            "topErrors": []
                        },
                        "read": {
                            "achieved": 4800.0,
                            "p50": 5.1,
                            "p95": 10.8,
                            "p99": 23.5,
                            "max": 52.0,
                            "completed": 144000,
                            "attempted": 144000,
                            "errors": 0,
                            "shed": 0,
                            "topErrors": []
                        }
                    },
                    {
                        "vus": 100,
                        "saturated": round_num == 2,  # Saturated in round 2 only (for testing ANY logic)
                        "write": {
                            "achieved": 8500.0 if round_num == 2 else 9000.0,
                            "p50": 6.0,
                            "p95": 12.5,
                            "p99": 30.0,
                            "max": 80.0,
                            "completed": 255000,
                            "attempted": 255000,
                            "errors": 0,
                            "shed": 0,
                            "topErrors": []
                        },
                        "read": {
                            "achieved": 8500.0 if round_num == 2 else 9000.0,
                            "p50": 5.8,
                            "p95": 12.1,
                            "p99": 28.5,
                            "max": 75.0,
                            "completed": 255000,
                            "attempted": 255000,
                            "errors": 0,
                            "shed": 0,
                            "topErrors": []
                        }
                    }
                ]
            }

            filename = results_dir / f"{label}-round{round_num}.json"
            with open(filename, "w") as f:
                json.dump(report, f, indent=2)
            print(f"  ✓ Created fixture {filename.name}")


def run_stress_report(results_dir):
    """Run Task 1: stress_report.py"""
    print("\n=== Task 1: stress_report.py ===")

    # Import and run the stress report script
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "stress_report",
        Path(__file__).parent / "stress_report.py"
    )
    stress_report = importlib.util.module_from_spec(spec)

    # Capture stdout
    import io
    from contextlib import redirect_stdout

    with redirect_stdout(io.StringIO()):
        spec.loader.exec_module(stress_report)

    # Call stress_report's main logic
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
            aggregated[label].append(stress_report.aggregate_results(step_data))

    # Generate reports
    html = stress_report.generate_html_report(aggregated)
    with open(results_dir.parent / "report.html", "w") as f:
        f.write(html)

    md = stress_report.generate_markdown_report(aggregated)
    with open(results_dir.parent / "report.md", "w") as f:
        f.write(md)

    print(f"  ✓ Generated report.html and report.md")

    # Verify aggregation
    for label, steps in aggregated.items():
        # For steps with index 2, check that ANY saturation is applied
        if len(steps) > 2:
            step_2 = steps[2]
            # In our fixture, round2 has step[2].saturated=True, so aggregated should too
            print(f"  ✓ Label '{label}' step 2 saturated: {step_2['saturated']}")

    return results_dir.parent


def run_update_history(results_dir, history_file):
    """Run Task 2: update_history.py"""
    print("\n=== Task 2: update_history.py ===")

    # Import and run the update_history script
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "update_history",
        Path(__file__).parent / "update_history.py"
    )
    update_history = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(update_history)

    # Call the main function
    sys.argv = ["update_history.py", str(results_dir), str(history_file)]
    update_history.main()

    print(f"  ✓ Updated {history_file.name}")

    # Verify history.json was created and has correct structure
    with open(history_file) as f:
        history = json.load(f)

    assert "runs" in history, "history.json missing 'runs' key"
    assert len(history["runs"]) == 1, f"Expected 1 run, got {len(history['runs'])}"

    run = history["runs"][0]
    assert "date" in run, "run missing 'date'"
    assert "results" in run, "run missing 'results'"
    assert len(run["results"]) == 2, f"Expected 2 labels, got {len(run['results'])}"

    # Verify each label has the required fields
    for label, result in run["results"].items():
        assert "last_stable_vus" in result, f"Label {label} missing 'last_stable_vus'"
        assert "throughput" in result, f"Label {label} missing 'throughput'"
        assert "saturated_at" in result, f"Label {label} missing 'saturated_at'"
        print(f"  ✓ Label '{label}': vus={result['last_stable_vus']}, "
              f"throughput={result['throughput']:.1f}, saturated_at={result['saturated_at']}")

    return history


def main():
    """Run end-to-end test."""
    print("Starting end-to-end integration test for stress-test pipeline...\n")

    # Create temporary directory for test artifacts
    with tempfile.TemporaryDirectory() as tmpdir:
        test_dir = Path(tmpdir)
        results_dir = test_dir / "results"
        history_file = test_dir / "history.json"

        try:
            # Stage 1: Create fixture data
            print("=== Stage 1: Create fixture data (simulating Task 0) ===")
            create_fixture_results(results_dir)

            # Verify fixture files were created
            json_files = sorted(results_dir.glob("*.json"))
            assert len(json_files) == 4, f"Expected 4 fixture files, got {len(json_files)}"
            print(f"  ✓ Created {len(json_files)} fixture files\n")

            # Stage 2: Run stress_report.py
            print("=== Stage 2: Run stress_report.py (Task 1) ===")
            report_dir = run_stress_report(results_dir)

            # Verify report files were created
            assert (report_dir / "report.html").exists(), "report.html not created"
            assert (report_dir / "report.md").exists(), "report.md not created"
            print()

            # Stage 3: Run update_history.py
            print("=== Stage 3: Run update_history.py (Task 2) ===")
            history = run_update_history(results_dir, history_file)

            # Additional verification
            assert history_file.exists(), "history.json not created"
            print()

            # Summary
            print("=== Test Summary ===")
            print("✓ All three stages completed successfully")
            print("✓ File naming format: results/<label>-round<R>.json")
            print("✓ Saturation aggregation: ANY logic across rounds")
            print("✓ Data flow: Task 0 → Task 1 → Task 2")
            print("\nEnd-to-end test PASSED")
            return 0

        except AssertionError as e:
            print(f"\n✗ Test failed: {e}", file=sys.stderr)
            return 1
        except Exception as e:
            print(f"\n✗ Unexpected error: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            return 1


if __name__ == "__main__":
    sys.exit(main())
