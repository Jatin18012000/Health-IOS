#!/usr/bin/env python3
"""
Conformance suite for the AURA ingestion contract.

Runs the reference pipeline against Tests/Fixtures/edge-cases and asserts every
hand-computed expectation in that directory's expected.json.

This is the acceptance test for M1/M2. When the Swift store lands, point the
same expectations at its output: if AURAStore reproduces every row below on the
same fixture, the port is correct. Until then, this proves the reference
implementation itself has not drifted.

    python3 tools/conformance.py            # run it
    python3 tools/conformance.py --verbose  # print the reason behind each check

Exit status is 0 on a clean run, 1 if anything failed -- so CI can gate on it.
"""

import argparse
import json
import os
import sqlite3
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE = os.path.join(ROOT, "Tests", "Fixtures", "edge-cases")
PIPELINE = os.path.join(ROOT, "tools", "reference_pipeline.py")

GREEN, RED, DIM, RESET = "\033[32m", "\033[31m", "\033[2m", "\033[0m"


class Checks:
    def __init__(self, verbose):
        self.passed = 0
        self.failures = []
        self.verbose = verbose

    def check(self, label, actual, expected, why=None):
        ok = actual == expected
        if ok:
            self.passed += 1
            print(f"  {GREEN}pass{RESET}  {label}")
        else:
            self.failures.append((label, actual, expected, why))
            print(f"  {RED}FAIL{RESET}  {label}")
            print(f"        expected {expected!r}, got {actual!r}")
            if why:
                print(f"        {DIM}{why}{RESET}")
        if ok and self.verbose and why:
            print(f"        {DIM}{why}{RESET}")
        return ok


def approx(x, places=1):
    return None if x is None else round(x, places)


def run_pipeline(out_path, append=False):
    cmd = [sys.executable, PIPELINE, FIXTURE, "--out", out_path]
    if append:
        cmd.append("--append")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout, r.stderr)
        sys.exit("pipeline failed")
    return r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    exp = json.load(open(os.path.join(FIXTURE, "expected.json")))
    c = Checks(args.verbose)

    with tempfile.TemporaryDirectory() as tmp:
        db_path = os.path.join(tmp, "conformance.sqlite")
        run_pipeline(db_path)
        db = sqlite3.connect(db_path)

        print("\nTotals")
        t = exp["totals"]
        c.check("samples stored",
                db.execute("SELECT COUNT(*) FROM samples").fetchone()[0],
                t["samples_stored"], t["_why"])
        c.check("daily metric rows",
                db.execute("SELECT COUNT(*) FROM daily_metrics").fetchone()[0],
                t["daily_metric_rows"])
        c.check("nights reconstructed",
                db.execute("SELECT COUNT(*) FROM sleep_nights").fetchone()[0],
                t["nights"])

        print("\nSource trust order")
        ranks = dict(db.execute("SELECT name, priority FROM sources"))
        for name, rank in exp["source_ranks"].items():
            if name == "_why":
                continue
            c.check(f"rank of {name!r}", ranks.get(name), rank,
                    exp["source_ranks"]["_why"] if rank == 0 else None)

        print("\nDaily metrics")
        for e in exp["daily_metrics"]:
            row = db.execute(
                "SELECT unit, value, value_min, value_max, sample_count, source_count, method "
                "FROM daily_metrics WHERE day=? AND identifier=?",
                (e["day"], e["metric"])).fetchone()
            label = f"{e['day']} {e['metric']}"
            if row is None:
                c.check(label, None, "a row", e.get("_why"))
                continue
            unit, value, vmin, vmax, n, nsrc, method = row
            c.check(f"{label} value", approx(value, 2), approx(e["value"], 2), e.get("_why"))
            c.check(f"{label} unit", unit, e["unit"])
            c.check(f"{label} method", method, e["method"])
            c.check(f"{label} sample_count", n, e["samples"])
            c.check(f"{label} source_count", nsrc, e["sources"])
            if "min" in e:
                c.check(f"{label} min", approx(vmin), approx(e["min"]))
                c.check(f"{label} max", approx(vmax), approx(e["max"]))

        print("\nRejections (must NOT appear)")
        for e in exp["absent_metrics"]:
            row = db.execute("SELECT 1 FROM daily_metrics WHERE day=? AND identifier=?",
                             (e["day"], e["metric"])).fetchone()
            c.check(f"{e['day']} {e['metric']} absent", row, None, e["_why"])

        print("\nSleep")
        for e in exp["sleep_nights"]:
            row = db.execute(
                "SELECT in_bed_min, asleep_min, core_min, deep_min, rem_min, awake_min, "
                "efficiency, staged FROM sleep_nights WHERE night_of=?",
                (e["night_of"],)).fetchone()
            label = f"night of {e['night_of']}"
            if row is None:
                c.check(label, None, "a row", e["_why"])
                continue
            keys = ["in_bed_min", "asleep_min", "core_min", "deep_min",
                    "rem_min", "awake_min", "efficiency", "staged"]
            for key, actual in zip(keys, row):
                c.check(f"{label} {key}", approx(actual), approx(e[key]),
                        e["_why"] if key == "in_bed_min" else None)

        print("\nIngest issues")
        issues = {d: n for _, d, n in db.execute("SELECT kind, detail, count FROM ingest_issues")}
        for detail, n in exp["issues"].items():
            if detail == "_why":
                continue
            c.check(f"issue {detail}", issues.get(detail), n, exp["issues"]["_why"])

        db.close()

        print("\nIdempotency")
        i = exp["idempotency"]
        run_pipeline(db_path, append=True)
        db = sqlite3.connect(db_path)
        c.check("samples after re-import",
                db.execute("SELECT COUNT(*) FROM samples").fetchone()[0],
                i["samples_after_second_import"], i["_why"])
        c.check("daily rows after re-import",
                db.execute("SELECT COUNT(*) FROM daily_metrics").fetchone()[0],
                i["daily_metric_rows_after_second_import"])
        c.check("StepCount 2025-03-10 after re-import",
                db.execute("SELECT value FROM daily_metrics WHERE day='2025-03-10' "
                           "AND identifier='StepCount'").fetchone()[0],
                i["step_count_2025_03_10_after_second_import"])
        db.close()

    total = c.passed + len(c.failures)
    print()
    if c.failures:
        print(f"{RED}{len(c.failures)} of {total} checks failed{RESET}")
        return 1
    print(f"{GREEN}all {total} checks passed{RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
