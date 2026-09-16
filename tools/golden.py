#!/usr/bin/env python3
"""
Golden snapshots against the real export.

The edge-case fixture (`tools/conformance.py`) proves the RULES are right on 32
hand-built records. This proves nothing has moved on 664,000 real ones — the
class of regression a small fixture cannot catch, where a change is correct on
every constructed case and quietly shifts a four-year trend.

    python3 tools/golden.py record <export-dir>   # take a snapshot
    python3 tools/golden.py check  <export-dir>   # compare against it

## Why the snapshot is not committed

It contains real figures from a real person's health history. Aggregates rather
than samples, but a year of someone's resting heart rate is still their medical
information, and a git repository is forever. `.gitignore` excludes it; anyone
cloning this runs `record` once against their own export and gets their own
baseline.

That makes this a *local* regression test rather than a CI gate, which is the
honest trade: the alternative is committing health data to make a build badge
green.
"""

import argparse
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GOLDEN = os.path.join(ROOT, "Tests", "Fixtures", "golden.json")


def snapshot(db_path):
    """Figures that must not move unless someone meant to move them."""
    db = sqlite3.connect(db_path)
    out = {}

    out["totals"] = dict(zip(
        ["samples", "daily_rows", "nights", "days"],
        [db.execute(q).fetchone()[0] for q in [
            "SELECT COUNT(*) FROM samples",
            "SELECT COUNT(*) FROM daily_metrics",
            "SELECT COUNT(*) FROM sleep_nights",
            "SELECT COUNT(DISTINCT day) FROM daily_metrics",
        ]]))

    out["range"] = list(db.execute(
        "SELECT MIN(day), MAX(day) FROM daily_metrics").fetchone())

    # Per-metric aggregates. A change to aggregation or deduplication moves one
    # of these even when every constructed test still passes.
    out["metrics"] = {
        identifier: {"n": n, "sum": round(total, 3), "mean": round(mean, 4)}
        for identifier, n, total, mean in db.execute("""
            SELECT identifier, COUNT(*), COALESCE(SUM(value), 0), COALESCE(AVG(value), 0)
            FROM daily_metrics GROUP BY identifier ORDER BY identifier
        """)
    }

    # Deduplication specifically: the count of affected days and their total is
    # the single most sensitive number in the pipeline.
    out["deduplicated"] = dict(zip(
        ["day_metric_pairs", "total"],
        db.execute("""
            SELECT COUNT(*), ROUND(COALESCE(SUM(value), 0), 3)
            FROM daily_metrics WHERE method = 'sum/deduped'
        """).fetchone()))

    out["sleep"] = dict(zip(
        ["staged", "unstaged", "mean_asleep", "mean_efficiency"],
        db.execute("""
            SELECT SUM(staged), SUM(1 - staged),
                   ROUND(AVG(asleep_min), 3), ROUND(AVG(efficiency), 3)
            FROM sleep_nights
        """).fetchone()))

    out["issues"] = {detail: count for _, detail, count in
                     db.execute("SELECT kind, detail, count FROM ingest_issues")}

    db.close()
    return out


def build(export_dir):
    tmp = tempfile.mkdtemp()
    db_path = os.path.join(tmp, "golden.sqlite")
    result = subprocess.run(
        [sys.executable, os.path.join(ROOT, "tools", "reference_pipeline.py"),
         export_dir, "--out", db_path],
        capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout, result.stderr)
        sys.exit("pipeline failed")
    return snapshot(db_path)


def diff(old, new, path=""):
    """Every difference, with its path. Not a boolean — knowing WHICH figure
    moved is the whole value of the exercise."""
    changes = []
    if isinstance(old, dict) and isinstance(new, dict):
        for key in sorted(set(old) | set(new)):
            changes += diff(old.get(key), new.get(key), f"{path}.{key}" if path else str(key))
    elif old != new:
        changes.append((path, old, new))
    return changes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["record", "check"])
    ap.add_argument("export_dir")
    a = ap.parse_args()

    current = build(a.export_dir)

    if a.command == "record":
        os.makedirs(os.path.dirname(GOLDEN), exist_ok=True)
        with open(GOLDEN, "w") as fh:
            json.dump(current, fh, indent=2, sort_keys=True)
        digest = hashlib.sha256(
            json.dumps(current, sort_keys=True).encode()).hexdigest()[:12]
        print(f"recorded {GOLDEN}")
        print(f"  {current['totals']['samples']:,} samples · "
              f"{current['totals']['days']:,} days · digest {digest}")
        print("  not committed — it holds real figures. See the module docstring.")
        return 0

    if not os.path.exists(GOLDEN):
        sys.exit(f"no snapshot at {GOLDEN} — run `record` first")

    with open(GOLDEN) as fh:
        recorded = json.load(fh)

    changes = diff(recorded, current)
    GREEN, RED = "\033[32m", "\033[31m"
    RESET = "\033[0m"

    if not changes:
        print(f"{GREEN}unchanged{RESET} — "
              f"{current['totals']['samples']:,} samples across "
              f"{current['totals']['days']:,} days")
        return 0

    print(f"{RED}{len(changes)} figure(s) moved{RESET}\n")
    for path, old, new in changes:
        print(f"  {path}")
        print(f"     was {old}")
        print(f"     now {new}")
    print("\nIf these changes were intended, re-run `record`.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
