import json
import tempfile
from pathlib import Path
from stress_report import aggregate_results, generate_html_report, generate_markdown_report

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
