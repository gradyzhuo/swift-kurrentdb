import json
import sys
import re
from datetime import datetime
from pathlib import Path
from statistics import median

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

def aggregate_results_across_rounds(steps_by_round):
    """Aggregate step results across multiple rounds."""
    if not steps_by_round:
        return []

    max_steps = max(len(steps) for steps in steps_by_round)
    aggregated = []

    for step_idx in range(max_steps):
        step_data = [r[step_idx] for r in steps_by_round if step_idx < len(r)]
        if not step_data:
            continue

        # Aggregate this step across rounds
        agg_step = {}
        for key in step_data[0].keys():
            if key == "vus":
                agg_step[key] = step_data[0][key]
            elif key == "saturated":
                # If ANY round is saturated, the step is saturated
                agg_step[key] = any(s.get("saturated", False) for s in step_data)
            elif isinstance(step_data[0][key], dict):
                # Aggregate nested dict (write/read metrics)
                agg_step[key] = aggregate_dict([s[key] for s in step_data])
            else:
                # Median for numeric values
                values = [s[key] for s in step_data if isinstance(s.get(key), (int, float))]
                agg_step[key] = median(values) if values else step_data[0][key]

        aggregated.append(agg_step)

    return aggregated

def aggregate_dict(dicts):
    """Median for nested dict (write/read metrics)."""
    agg = {}
    for key in dicts[0].keys():
        values = [d[key] for d in dicts if isinstance(d.get(key), (int, float))]
        agg[key] = median(values) if values else dicts[0][key]
    return agg

def extract_summary_from_steps(steps):
    """Extract summary metrics from aggregated steps."""
    if not steps:
        return {
            "last_stable_vus": 0,
            "throughput": 0,
            "saturated_at": None
        }

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

    # Group result files by label
    results_by_label = {}
    pattern = re.compile(r"^(.+?)-round(\d+)\.json$")

    for json_file in sorted(results_dir.glob("*.json")):
        match = pattern.match(json_file.name)
        if not match:
            continue

        try:
            label = match.group(1)
            with open(json_file) as f:
                data = json.load(f)
                if label not in results_by_label:
                    results_by_label[label] = []
                results_by_label[label].append(data.get("steps", []))
        except Exception as e:
            print(f"ERROR reading {json_file}: {e}", file=sys.stderr)
            sys.exit(1)

    # Aggregate and extract summaries
    aggregated_summaries = {}
    for label, steps_by_round in results_by_label.items():
        aggregated_steps = aggregate_results_across_rounds(steps_by_round)
        summary = extract_summary_from_steps(aggregated_steps)
        aggregated_summaries[label] = summary

    # Add new run
    if aggregated_summaries:
        new_run = {
            "date": datetime.utcnow().isoformat() + "Z",
            "results": aggregated_summaries
        }
        history["runs"].append(new_run)

        # Keep only last 50 runs
        history["runs"] = history["runs"][-50:]

        save_history(history["runs"], history_file)
        print(f"Updated {history_file} with {len(aggregated_summaries)} label(s)")
    else:
        print("WARNING: No results found in " + str(results_dir))
        sys.exit(1)

if __name__ == "__main__":
    main()
