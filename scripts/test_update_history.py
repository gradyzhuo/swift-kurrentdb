import json
import tempfile
from pathlib import Path
from update_history import load_history, save_history, extract_summary_from_json

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
