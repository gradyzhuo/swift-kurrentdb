import json
import sys
from pathlib import Path
from statistics import median

def aggregate_results(results_per_round):
    """Aggregate across rounds: median for numeric fields, ANY for saturated."""
    if not results_per_round:
        return {}

    aggregated = {}
    for key in results_per_round[0].keys():
        if key == "vus":
            # VUs is same across all rounds for a given step
            aggregated[key] = results_per_round[0][key]
        elif key == "saturated":
            # For saturated: if ANY round is saturated, the step is saturated
            aggregated[key] = any(r.get("saturated", False) for r in results_per_round)
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
