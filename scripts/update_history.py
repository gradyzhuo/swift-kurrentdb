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
