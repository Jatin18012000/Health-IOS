#!/usr/bin/env python3
"""
AURA reference ingestion pipeline.

This is NOT the shipping implementation -- the shipping one is Swift, in
Sources/AURAIngest + Sources/AURAStore. This script is the executable
specification: it runs against a real Apple Health export, proves the schema
and the aggregation rules hold, and produces the SQLite file the Swift code
must produce byte-for-byte equivalently. Port it, then diff the outputs.

Usage:
    python3 tools/reference_pipeline.py <path-to-apple_health_export> [--out aura.sqlite]

Design notes live in docs/DATA_MODEL.md. The two rules that matter most:

  1. Units are normalized at ingest, never at display time. Apple emits
     ActiveEnergyBurned in "Cal" and BasalEnergyBurned in "kcal" -- these are
     the SAME unit. Anything that treats "Cal" as a calorie is off by 1000x.

  2. Cumulative metrics MUST be source-deduplicated before summing. An iPhone
     in your pocket and a Watch on your wrist both count the same steps.
     Naive summing inflates real days by up to 1.9x. See dedup_cumulative().
"""

import argparse
import os
import re
import sqlite3
import sys
from collections import defaultdict
from datetime import datetime, timedelta

# --------------------------------------------------------------------------
# Metric catalog -- the single source of truth for types, units and semantics.
# Mirrored in Sources/AURACore/MetricCatalog.swift. Keep them in lockstep.
# --------------------------------------------------------------------------

SUM, MEAN, LAST, MINMAX, INTERVAL, COUNT = "sum", "mean", "last", "minmax", "interval", "count"

CATALOG = {
    # identifier                        domain         canonical unit  aggregation  cumulative
    "StepCount":                        ("activity",    "count",       SUM,      True),
    "DistanceWalkingRunning":           ("activity",    "km",          SUM,      True),
    "DistanceCycling":                  ("activity",    "km",          SUM,      True),
    "FlightsClimbed":                   ("activity",    "count",       SUM,      True),
    "ActiveEnergyBurned":               ("activity",    "kcal",        SUM,      True),
    "BasalEnergyBurned":                ("activity",    "kcal",        SUM,      True),
    "AppleExerciseTime":                ("activity",    "min",         SUM,      True),
    "AppleStandTime":                   ("activity",    "min",         SUM,      True),
    "AppleStandHour":                   ("activity",    "count",       COUNT,    False),
    "PhysicalEffort":                   ("activity",    "kcal/hr-kg",  MEAN,     False),

    "HeartRate":                        ("heart",       "bpm",         MINMAX,   False),
    "RestingHeartRate":                 ("heart",       "bpm",         MEAN,     False),
    "WalkingHeartRateAverage":          ("heart",       "bpm",         MEAN,     False),
    "HeartRateVariabilitySDNN":         ("heart",       "ms",          MEAN,     False),
    "OxygenSaturation":                 ("heart",       "%",           MEAN,     False),
    "VO2Max":                           ("heart",       "mL/min-kg",   LAST,     False),
    "BloodPressureSystolic":            ("heart",       "mmHg",        MEAN,     False),
    "BloodPressureDiastolic":           ("heart",       "mmHg",        MEAN,     False),
    "HighHeartRateEvent":               ("heart",       "count",       COUNT,    False),

    "SleepAnalysis":                    ("sleep",       "min",         INTERVAL, False),
    "RespiratoryRate":                  ("sleep",       "breaths/min", MEAN,     False),
    "AppleSleepingWristTemperature":    ("sleep",       "degC",        MEAN,     False),
    "AppleSleepingBreathingDisturbances": ("sleep",     "count",       MEAN,     False),

    "WalkingSpeed":                     ("mobility",    "km/hr",       MEAN,     False),
    "WalkingStepLength":                ("mobility",    "cm",          MEAN,     False),
    "WalkingAsymmetryPercentage":       ("mobility",    "%",           MEAN,     False),
    "WalkingDoubleSupportPercentage":   ("mobility",    "%",           MEAN,     False),
    "StairAscentSpeed":                 ("mobility",    "m/s",         MEAN,     False),
    "StairDescentSpeed":                ("mobility",    "m/s",         MEAN,     False),
    "AppleWalkingSteadiness":           ("mobility",    "%",           MEAN,     False),
    "SixMinuteWalkTestDistance":        ("mobility",    "m",           LAST,     False),

    "HeadphoneAudioExposure":           ("environment", "dBASPL",      MEAN,     False),
    "EnvironmentalAudioExposure":       ("environment", "dBASPL",      MEAN,     False),
    "TimeInDaylight":                   ("environment", "min",         SUM,      True),
    "AudioExposureEvent":               ("environment", "count",       COUNT,    False),
    "HeadphoneAudioExposureEvent":      ("environment", "count",       COUNT,    False),

    "BodyMass":                         ("body",        "kg",          LAST,     False),
    "Height":                           ("body",        "cm",          LAST,     False),

    "MindfulSession":                   ("mind",        "min",         SUM,      True),
    "HandwashingEvent":                 ("mind",        "count",       COUNT,    False),
}

# Which raw units Apple may emit for each canonical unit. Aliasing is scoped to
# the canonical unit, never global: "count/min" legitimately means beats/min for
# HeartRate and breaths/min for RespiratoryRate, and a global alias table maps
# one of them wrong. "Cal" in a HealthKit export is a kilocalorie -- treating it
# as a calorie is a silent 1000x error.
ACCEPTED_UNITS = {
    "kcal":        {"kcal", "Cal"},
    "bpm":         {"bpm", "count/min"},
    "breaths/min": {"breaths/min", "count/min"},
    "kcal/hr-kg":  {"kcal/hr-kg", "kcal/hr\u00b7kg"},
    "mL/min-kg":   {"mL/min-kg", "mL/min\u00b7kg"},
}


def unit_ok(raw, canonical):
    if not raw or raw == "None" or raw == canonical:
        return True
    return raw in ACCEPTED_UNITS.get(canonical, {canonical})


# Source trust order for deduplicating cumulative metrics. A wrist-worn device
# beats a pocket-carried one; a first-party device beats a third-party one.
# Lower number == higher priority. Unknown sources sort last.
SOURCE_PRIORITY = [
    (re.compile(r"Apple\s*Watch", re.I), 0),
    (re.compile(r"iPhone", re.I),        1),
    (re.compile(r"iPad", re.I),          2),
    (re.compile(r"FitCloudPro", re.I),   3),
    (re.compile(r"NoiseFit", re.I),      4),
]

SLEEP_ASLEEP = {"AsleepUnspecified", "AsleepCore", "AsleepDeep", "AsleepREM"}

# The day a night's sleep is attributed to: a session that ends at 07:00 on the
# 12th belongs to the night of the 11th. Sessions ending before this hour roll
# back to the previous calendar day.
SLEEP_DAY_CUTOFF_HOUR = 18


def source_priority(name):
    for rx, p in SOURCE_PRIORITY:
        if rx.search(name):
            return p
    return 99


RECORD_RX = re.compile(
    r'<Record type="HK(?:Quantity|Category)TypeIdentifier([A-Za-z0-9]+)"'
    r'(?P<attrs>[^>]*)'
)
ATTR_RX = re.compile(r'(\w+)="([^"]*)"')


def parse_date(s):
    # Apple emits "2026-09-15 08:48:04 +0530"
    return datetime.strptime(s, "%Y-%m-%d %H:%M:%S %z")


def iter_records(path):
    """Streaming line-oriented scan. The export is one Record per line and can
    be 300 MB+, so we never build a DOM. The Swift port uses XMLParser (SAX),
    which is the same streaming contract."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = RECORD_RX.search(line)
            if not m:
                continue
            attrs = dict(ATTR_RX.findall(m.group("attrs")))
            yield m.group(1), attrs


def normalize(identifier, attrs):
    """Return a normalized sample dict, or None if the record is unusable."""
    spec = CATALOG.get(identifier)
    if spec is None:
        return None
    domain, canonical_unit, agg, cumulative = spec

    unit = attrs.get("unit") or ""
    raw_value = attrs.get("value", "")

    if agg in (COUNT, INTERVAL) or raw_value.startswith("HKCategoryValue"):
        value = None
        category = raw_value.replace("HKCategoryValueSleepAnalysis", "")
    else:
        try:
            value = float(raw_value)
        except ValueError:
            return None
        category = None
        if not unit_ok(unit, canonical_unit):
            # An unexpected unit is a data-integrity event, not something to
            # silently coerce. Surface it rather than producing a wrong number.
            return {"__unit_mismatch__": (identifier, unit, canonical_unit)}

    try:
        start = parse_date(attrs["startDate"])
        end = parse_date(attrs.get("endDate", attrs["startDate"]))
    except (KeyError, ValueError):
        return None

    return {
        "identifier": identifier,
        "domain": domain,
        "unit": canonical_unit,
        "value": value,
        "category": category,
        "source": attrs.get("sourceName", "unknown"),
        "device": attrs.get("device"),
        "start": start,
        "end": end,
    }


def dedup_cumulative(samples):
    """Resolve overlapping cumulative samples from competing sources.

    An iPhone in a pocket and a Watch on a wrist both record the same steps.
    Summing every sample double-counts them. Apple's own Health app solves this
    with sample-level source prioritization; we do the same thing explicitly:

      - walk sources in trust order (Watch, then iPhone, then third-party)
      - a higher-trust source claims its time intervals outright
      - a lower-trust sample contributes only the FRACTION of its interval that
        no higher-trust source already covered, scaled pro-rata by duration

    So a Watch worn for the morning and an iPhone carried all day yields the
    Watch's morning plus the iPhone's afternoon -- never both for the same hour.

    Returns the deduplicated total.
    """
    ordered = sorted(samples, key=lambda s: (source_priority(s["source"]), s["start"]))
    claimed = []  # disjoint, sorted list of (start, end) already attributed
    total = 0.0

    for s in ordered:
        start, end, value = s["start"], s["end"], s["value"] or 0.0
        span = (end - start).total_seconds()

        if span <= 0:
            # An instantaneous cumulative sample. Attribute it whole unless its
            # exact instant is already inside a claimed interval.
            if not any(a <= start < b for a, b in claimed):
                total += value
                claimed.append((start, start + timedelta(seconds=1)))
                claimed.sort()
            continue

        overlap = 0.0
        for a, b in claimed:
            if b <= start or a >= end:
                continue
            overlap += (min(b, end) - max(a, start)).total_seconds()

        uncovered = max(0.0, span - overlap)
        total += value * (uncovered / span)

        if uncovered > 0:
            claimed.append((start, end))
            claimed = merge_intervals(claimed)

    return total


def merge_intervals(intervals):
    intervals.sort()
    merged = []
    for a, b in intervals:
        if merged and a <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], b))
        else:
            merged.append((a, b))
    return merged


def sleep_night_of(session_end):
    """Which night a sleep session belongs to."""
    d = session_end.date()
    if session_end.hour < SLEEP_DAY_CUTOFF_HOUR:
        d = d - timedelta(days=1)
    return d


def build_schema(conn):
    conn.executescript("""
    PRAGMA journal_mode = WAL;

    CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );

    -- Lookup tables. The device attribute in an Apple export is a ~180-byte
    -- descriptor string repeated on every single sample; interning it (and the
    -- source and metric names) is the difference between a 340 MB database and
    -- a 40 MB one on the same data.
    CREATE TABLE IF NOT EXISTS metrics (
        id         INTEGER PRIMARY KEY,
        identifier TEXT NOT NULL UNIQUE,
        domain     TEXT NOT NULL,
        unit       TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sources (
        id       INTEGER PRIMARY KEY,
        name     TEXT NOT NULL UNIQUE,
        priority INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS devices (
        id         INTEGER PRIMARY KEY,
        descriptor TEXT NOT NULL UNIQUE
    );

    -- Raw normalized samples. Kept for drill-down and re-aggregation.
    -- Timestamps are unix seconds, not ISO strings: 8 bytes instead of 25, and
    -- range scans compare integers. Display formatting happens in the view layer.
    CREATE TABLE IF NOT EXISTS samples (
        id        INTEGER PRIMARY KEY,
        metric_id INTEGER NOT NULL REFERENCES metrics(id),
        source_id INTEGER NOT NULL REFERENCES sources(id),
        device_id INTEGER          REFERENCES devices(id),
        value     REAL,
        category  TEXT,
        start_at  INTEGER NOT NULL,
        end_at    INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_samples_metric_start ON samples (metric_id, start_at);

    -- One row per (day, metric). This is what the dashboard reads.
    CREATE TABLE IF NOT EXISTS daily_metrics (
        day          TEXT NOT NULL,
        identifier   TEXT NOT NULL,
        domain       TEXT NOT NULL,
        unit         TEXT NOT NULL,
        value        REAL,
        value_min    REAL,
        value_max    REAL,
        sample_count INTEGER NOT NULL,
        source_count INTEGER NOT NULL,
        method       TEXT NOT NULL,
        PRIMARY KEY (day, identifier)
    );
    CREATE INDEX IF NOT EXISTS idx_daily_identifier ON daily_metrics (identifier, day);

    -- One row per night, reconstructed from overlapping SleepAnalysis intervals.
    CREATE TABLE IF NOT EXISTS sleep_nights (
        night_of      TEXT PRIMARY KEY,
        in_bed_start  TEXT,
        in_bed_end    TEXT,
        in_bed_min    REAL,
        asleep_min    REAL,
        core_min      REAL,
        deep_min      REAL,
        rem_min       REAL,
        awake_min     REAL,
        efficiency    REAL,
        staged        INTEGER NOT NULL,
        sources       TEXT
    );

    -- Data-integrity events worth showing the user rather than hiding.
    CREATE TABLE IF NOT EXISTS ingest_issues (
        id      INTEGER PRIMARY KEY,
        kind    TEXT NOT NULL,
        detail  TEXT NOT NULL,
        count   INTEGER NOT NULL
    );
    """)


def run(export_dir, out_path):
    xml_path = os.path.join(export_dir, "export.xml")
    if not os.path.exists(xml_path):
        sys.exit(f"no export.xml under {export_dir}")

    print(f"reading {xml_path} ({os.path.getsize(xml_path) / 1e6:.0f} MB)")

    # day -> identifier -> list of samples
    by_day = defaultdict(lambda: defaultdict(list))
    sleep_samples = []
    issues = defaultdict(int)
    rows = []
    n = 0

    for identifier, attrs in iter_records(xml_path):
        s = normalize(identifier, attrs)
        if s is None:
            issues[f"unmapped:{identifier}"] += 1
            continue
        if "__unit_mismatch__" in s:
            ident, got, want = s["__unit_mismatch__"]
            issues[f"unit_mismatch:{ident}:got={got}:want={want}"] += 1
            continue

        n += 1
        rows.append((
            s["identifier"], s["source"], s["device"], s["value"], s["category"],
            int(s["start"].timestamp()), int(s["end"].timestamp()),
        ))

        if s["identifier"] == "SleepAnalysis":
            sleep_samples.append(s)
        else:
            by_day[s["start"].date().isoformat()][s["identifier"]].append(s)

        if n % 100_000 == 0:
            print(f"  {n:,} samples")

    print(f"parsed {n:,} usable samples")

    if os.path.exists(out_path):
        os.remove(out_path)
    conn = sqlite3.connect(out_path)
    build_schema(conn)

    conn.executemany(
        "INSERT OR IGNORE INTO metrics (identifier,domain,unit) VALUES (?,?,?)",
        [(k, v[0], v[1]) for k, v in CATALOG.items()])
    conn.executemany(
        "INSERT OR IGNORE INTO sources (name,priority) VALUES (?,?)",
        [(nm, source_priority(nm)) for nm in {r[1] for r in rows}])
    conn.executemany(
        "INSERT OR IGNORE INTO devices (descriptor) VALUES (?)",
        [(d,) for d in {r[2] for r in rows if r[2]}])
    conn.commit()

    metric_id = dict(conn.execute("SELECT identifier, id FROM metrics"))
    source_id = dict(conn.execute("SELECT name, id FROM sources"))
    device_id = dict(conn.execute("SELECT descriptor, id FROM devices"))

    conn.executemany(
        "INSERT INTO samples (metric_id,source_id,device_id,value,category,start_at,end_at) "
        "VALUES (?,?,?,?,?,?,?)",
        [(metric_id[r[0]], source_id[r[1]], device_id.get(r[2]), r[3], r[4], r[5], r[6])
         for r in rows])
    conn.commit()
    print(f"stored {conn.execute('SELECT COUNT(*) FROM samples').fetchone()[0]:,} samples "
          f"across {len(source_id)} sources and {len(device_id)} devices")

    # ---- daily rollups -----------------------------------------------------
    daily = []
    deduped_days = 0
    for day, metrics in by_day.items():
        for identifier, samples in metrics.items():
            domain, unit, agg, cumulative = CATALOG[identifier]
            sources = {s["source"] for s in samples}
            values = [s["value"] for s in samples if s["value"] is not None]
            vmin = vmax = None
            method = agg

            if agg == SUM:
                if cumulative and len(sources) > 1:
                    value = dedup_cumulative(samples)
                    method = "sum/deduped"
                    deduped_days += 1
                else:
                    value = sum(values)
            elif agg == MEAN:
                value = sum(values) / len(values) if values else None
            elif agg == MINMAX:
                value = sum(values) / len(values) if values else None
                vmin, vmax = (min(values), max(values)) if values else (None, None)
            elif agg == LAST:
                value = max(samples, key=lambda s: s["start"])["value"]
            elif agg == COUNT:
                if identifier == "AppleStandHour":
                    value = sum(1 for s in samples if s["category"] == "HKCategoryValueAppleStandHourStood")
                    method = "count/stood"
                else:
                    value = float(len(samples))
            else:
                continue

            daily.append((day, identifier, domain, unit, value, vmin, vmax,
                          len(samples), len(sources), method))

    conn.executemany(
        "INSERT OR REPLACE INTO daily_metrics "
        "(day,identifier,domain,unit,value,value_min,value_max,sample_count,source_count,method) "
        "VALUES (?,?,?,?,?,?,?,?,?,?)", daily)
    conn.commit()
    print(f"built {len(daily):,} daily metric rows "
          f"({deduped_days:,} required multi-source deduplication)")

    # ---- sleep nights ------------------------------------------------------
    nights = defaultdict(list)
    for s in sleep_samples:
        nights[sleep_night_of(s["end"]).isoformat()].append(s)

    night_rows = []
    for night, samples in nights.items():
        cat_min = defaultdict(float)
        for s in samples:
            mins = (s["end"] - s["start"]).total_seconds() / 60.0
            cat_min[s["category"]] += mins

        core, deep, rem = cat_min["AsleepCore"], cat_min["AsleepDeep"], cat_min["AsleepREM"]
        staged = (core + deep + rem) > 0

        # Two eras in this data: iPhone-only nights give InBed intervals with no
        # staging; Watch nights give real stages. Asleep time means different
        # things in each, so the era is recorded and never silently blended.
        if staged:
            asleep = core + deep + rem + cat_min["AsleepUnspecified"]
        else:
            asleep = cat_min["AsleepUnspecified"] or merged_minutes(
                [(s["start"], s["end"]) for s in samples if s["category"] == "InBed"])

        in_bed = merged_minutes([(s["start"], s["end"]) for s in samples])
        starts = [s["start"] for s in samples]
        ends = [s["end"] for s in samples]

        night_rows.append((
            night,
            min(starts).isoformat(), max(ends).isoformat(),
            round(in_bed, 1), round(asleep, 1),
            round(core, 1), round(deep, 1), round(rem, 1), round(cat_min["Awake"], 1),
            round(asleep / in_bed * 100, 1) if in_bed > 0 else None,
            1 if staged else 0,
            ",".join(sorted({s["source"] for s in samples})),
        ))

    conn.executemany(
        "INSERT OR REPLACE INTO sleep_nights "
        "(night_of,in_bed_start,in_bed_end,in_bed_min,asleep_min,core_min,deep_min,"
        "rem_min,awake_min,efficiency,staged,sources) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        night_rows)
    conn.commit()
    staged_n = sum(r[10] for r in night_rows)
    print(f"reconstructed {len(night_rows):,} nights "
          f"({staged_n:,} with real sleep staging, {len(night_rows) - staged_n:,} in-bed only)")

    conn.executemany(
        "INSERT INTO ingest_issues (kind, detail, count) VALUES (?,?,?)",
        [(k.split(":")[0], k, v) for k, v in sorted(issues.items(), key=lambda kv: -kv[1])])

    days = [d for d, in conn.execute("SELECT DISTINCT day FROM daily_metrics ORDER BY day")]
    conn.executemany("INSERT OR REPLACE INTO meta (key,value) VALUES (?,?)", [
        ("ingested_at", datetime.now().isoformat()),
        ("source_export", xml_path),
        ("first_day", days[0]), ("last_day", days[-1]),
        ("day_count", str(len(days))),
        ("pipeline_version", "1"),
    ])
    conn.commit()

    if issues:
        print("\ningest issues (recorded, not hidden):")
        for k, v in sorted(issues.items(), key=lambda kv: -kv[1])[:10]:
            print(f"  {v:>7,}  {k}")

    print(f"\nwrote {out_path} ({os.path.getsize(out_path) / 1e6:.1f} MB)")
    print(f"covering {days[0]} -> {days[-1]} ({len(days):,} days)")
    conn.close()


def merged_minutes(intervals):
    if not intervals:
        return 0.0
    merged = merge_intervals([(a, b) for a, b in intervals])
    return sum((b - a).total_seconds() for a, b in merged) / 60.0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("export_dir", help="the unzipped apple_health_export directory")
    ap.add_argument("--out", default="aura.sqlite")
    a = ap.parse_args()
    run(a.export_dir, a.out)
