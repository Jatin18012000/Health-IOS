#!/usr/bin/env python3
"""
AURA analytics — the executable specification for Sources/AURAAnalytics.

Every number the dashboard shows and every number AURA says comes from here.
None of it comes from the language model, which is unreliable at exactly these
operations and would be stating them about someone's own body.

    python3 tools/analytics.py aura.sqlite --day 2026-09-13
    python3 tools/analytics.py aura.sqlite --day 2026-09-13 --json

Two principles run through all of it:

  1. **Personal baselines, never population norms.** Every comparison is against
     this person's own history. A companion that says "your resting heart rate
     is above average for your age" is doing unlicensed medicine; one that says
     "it's higher than your own last year" is reporting a fact.

  2. **Say how much you know.** Every figure carries its sample size and every
     observation its confidence. With 1,450 days almost any two metrics
     correlate weakly, and surfacing r = 0.11 as an insight is how a health app
     starts telling people comforting nonsense.
"""

import argparse
import json
import math
import sqlite3
import statistics
from datetime import date, timedelta

# ── tunables ───────────────────────────────────────────────────────────────
# These are judgement calls, gathered here rather than scattered, because they
# are the things most likely to want changing once a real person uses this.

BASELINE_DAYS = 365       # window for personal percentiles

# Below this many readings, a percentile is not reported at all. Ranking a day
# against three others and calling it "the 100th percentile" is a number with no
# information in it, and widening BASELINE_DAYS makes this MORE likely to bite,
# not less: the window now advertises a year while a sensor that arrived last
# month still only has a month of data behind it.
MIN_BASELINE_SAMPLES = 14
COMPARISON_DAYS = 30      # window for "vs your average" deltas
MIN_CORRELATION_N = 30    # below this, a correlation is not reported at all
STRONG_CORRELATION = 0.5  # |r| at or above this is reported without hedging
OUTLIER_Z = 3.5           # modified z-score threshold for an anomaly
PARTIAL_DAY_THRESHOLD = 0.9   # below this share of a day elapsed, do not publish a score

# Composite score weights. PROVISIONAL — see docs/DECISIONS_PENDING.md.
SCORE_WEIGHTS = {"activity": 0.30, "sleep": 0.30, "heart": 0.20, "recovery": 0.20}

# Daily goals. A PREFERENCE, not a statistic — which is why it sits apart from
# the tunables above and why nothing here is derived from it. Percentiles and
# scores deliberately ignore goals entirely: a goal is a number someone picked,
# a percentile is a fact about the person.
#
# 8,000 rather than the customary 10,000. That figure comes from a 1960s
# Japanese pedometer marketing campaign, not from any clinical threshold, and
# the reference user's own 365-day mean is 6,340 — a goal cleared four days in
# ten motivates worse than one cleared eight days in ten.
GOALS = {
    "StepCount": 8000,
}

# Metrics where a LOWER value is the better one, so the percentile inverts.
LOWER_IS_BETTER = {"RestingHeartRate", "WalkingHeartRateAverage",
                   "AppleSleepingBreathingDisturbances"}


# ── primitives ─────────────────────────────────────────────────────────────

def series(db, metric, start, end):
    """Daily values for a metric over an inclusive day range, in order."""
    return [(d, v) for d, v in db.execute(
        "SELECT day, value FROM daily_metrics "
        "WHERE identifier = ? AND day BETWEEN ? AND ? AND value IS NOT NULL "
        "ORDER BY day", (metric, str(start), str(end)))]


def slope_per_day(values):
    """Least-squares slope, in units per day.

    Reported alongside the simple delta because the two answer different
    questions: a delta compares two endpoints and is at the mercy of both,
    a slope uses every point in between.
    """
    n = len(values)
    if n < 3:
        return None
    xs = list(range(n))
    mx, my = statistics.fmean(xs), statistics.fmean(values)
    denom = sum((x - mx) ** 2 for x in xs)
    if denom == 0:
        return None
    return sum((x - mx) * (y - my) for x, y in zip(xs, values)) / denom


def percentile_of(value, population):
    """Where `value` sits within `population`, 0..1.

    The fraction of the population below it, plus half the ties — so an exactly
    median value scores 0.5 rather than drifting with how many duplicates the
    person happens to have.
    """
    if not population:
        return None
    below = sum(1 for p in population if p < value)
    ties = sum(1 for p in population if p == value)
    return (below + ties / 2) / len(population)


def modified_z(value, population):
    """Outlier score using the median and MAD rather than mean and SD.

    Health data is skewed and full of its own outliers — one 25,000-step day
    inflates the mean and the standard deviation together, which hides the very
    anomalies this is meant to find. The median and MAD do not move.
    """
    if len(population) < 10:
        return None
    med = statistics.median(population)
    mad = statistics.median([abs(p - med) for p in population])
    if mad == 0:
        return None
    return 0.6745 * (value - med) / mad


def pearson(xs, ys):
    n = len(xs)
    if n < 3:
        return None
    mx, my = statistics.fmean(xs), statistics.fmean(ys)
    sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    sy = math.sqrt(sum((y - my) ** 2 for y in ys))
    if sx == 0 or sy == 0:
        return None
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy)


# ── the analyses ───────────────────────────────────────────────────────────

def trend(db, metric, end_day, days=None):
    """A window against the equivalent window immediately before it."""
    # Resolved here, not in the signature: a default argument binds at function
    # DEFINITION time, which silently froze every constant in this file at
    # import and made them impossible to change.
    days = days if days is not None else COMPARISON_DAYS
    end = date.fromisoformat(end_day)
    cur_start = end - timedelta(days=days - 1)
    prev_end = cur_start - timedelta(days=1)
    prev_start = prev_end - timedelta(days=days - 1)

    cur = series(db, metric, cur_start, end)
    prev = series(db, metric, prev_start, prev_end)
    cur_v = [v for _, v in cur]
    prev_v = [v for _, v in prev]

    cur_mean = statistics.fmean(cur_v) if cur_v else None
    prev_mean = statistics.fmean(prev_v) if prev_v else None
    change = None
    if cur_mean is not None and prev_mean:
        change = (cur_mean - prev_mean) / abs(prev_mean) * 100

    return {
        "metric": metric,
        "window_days": days,
        "current": cur_mean,
        "previous": prev_mean,
        "change_percent": change,
        "slope_per_day": slope_per_day(cur_v),
        "covered_days": len(cur_v),
        # Reported, never silently averaged over. "I only have four days of this
        # week" is a better answer than a confident mean of four days.
        "missing_days": days - len(cur_v),
    }


def correlation(db, a, b, end_day, days=None):
    """Pearson's r between two metrics on days where both have a value."""
    days = days if days is not None else BASELINE_DAYS
    end = date.fromisoformat(end_day)
    start = end - timedelta(days=days - 1)
    da, dbv = dict(series(db, a, start, end)), dict(series(db, b, start, end))
    common = sorted(set(da) & set(dbv))
    if len(common) < MIN_CORRELATION_N:
        return {"a": a, "b": b, "n": len(common), "r": None,
                "reportable": False, "reason": "too few overlapping days"}

    r = pearson([da[d] for d in common], [dbv[d] for d in common])
    return {
        "a": a, "b": b, "n": len(common), "r": r, "reportable": r is not None,
        # Carried out with the finding so she can hedge honestly rather than
        # either dropping a real signal or overselling a coincidence.
        "confidence": min(1.0, abs(r) / STRONG_CORRELATION) if r is not None else 0.0,
    }


def baseline(db, metric, end_day, days=None):
    days = days if days is not None else BASELINE_DAYS
    end = date.fromisoformat(end_day)
    return [v for _, v in series(db, metric, end - timedelta(days=days - 1), end)]


def figure(db, metric, end_day):
    """One metric's value for a day, with its personal context."""
    row = db.execute(
        "SELECT value, unit FROM daily_metrics WHERE day = ? AND identifier = ?",
        (end_day, metric)).fetchone()
    if row is None or row[0] is None:
        return None
    value, unit = row

    pop = baseline(db, metric, end_day)
    pct = percentile_of(value, pop) if len(pop) >= MIN_BASELINE_SAMPLES else None
    if pct is not None and metric in LOWER_IS_BETTER:
        pct = 1 - pct

    t = trend(db, metric, end_day)
    return {
        "metric": metric, "value": value, "unit": unit,
        "personal_percentile": pct,
        "baseline_mean": statistics.fmean(pop) if pop else None,
        "baseline_n": len(pop),
        "change_percent": t["change_percent"],
        "anomaly_z": modified_z(value, pop),
    }


def sleep_figure(db, night_of):
    row = db.execute(
        "SELECT asleep_min, efficiency, staged, deep_min, rem_min "
        "FROM sleep_nights WHERE night_of = ?", (night_of,)).fetchone()
    if row is None:
        return None
    asleep, eff, staged, deep, rem = row

    end = date.fromisoformat(night_of)
    start = end - timedelta(days=BASELINE_DAYS - 1)
    # Staged and unstaged nights are not comparable, so a staged night is only
    # ever ranked against other staged nights.
    pop = [a for a, in db.execute(
        "SELECT asleep_min FROM sleep_nights "
        "WHERE night_of BETWEEN ? AND ? AND staged = ? AND asleep_min IS NOT NULL",
        (str(start), str(end), staged))]

    return {
        "asleep_min": asleep, "efficiency": eff, "staged": bool(staged),
        "deep_min": deep, "rem_min": rem,
        "personal_percentile": (percentile_of(asleep, pop)
                                if len(pop) >= MIN_BASELINE_SAMPLES else None),
        "baseline_n": len(pop),
    }


def day_completeness(db, day):
    """How much of a day the store actually has, 0..1.

    The last day of any import is almost always a partial one — this export was
    taken at 08:48, so the 15th has eight hours in it. Scoring that day against
    full days produces an alarming number for no reason, and a companion that
    tells you your health collapsed because you exported before lunch has
    destroyed its own credibility.

    Measured from the day's last sample rather than from a clock, because the
    store may be read long after the import.
    """
    row = db.execute(
        "SELECT MAX(end_at) FROM samples WHERE start_at >= strftime('%s', ?) "
        "AND start_at < strftime('%s', ?, '+1 day')", (day, day)).fetchone()
    if row is None or row[0] is None:
        return 0.0
    last = row[0] - int(date.fromisoformat(day).strftime("%s") or 0)
    from datetime import datetime, timezone
    midnight = datetime.fromisoformat(day + "T00:00:00").timestamp()
    elapsed = (row[0] - midnight) / 86400.0
    return max(0.0, min(1.0, elapsed))


def health_score(db, day):
    """A composite 0–100, with every component carried out alongside it.

    Each component is this person's own percentile for that day, so the score
    answers "how does today compare with my recent self" and nothing else.

    A component with no data is `None` and its weight is redistributed over the
    components that do have data — a missing metric must never read as a failing
    one.
    """
    components, detail = {}, {}

    activity = [figure(db, m, day) for m in
                ("StepCount", "ActiveEnergyBurned", "AppleExerciseTime")]
    activity = [f["personal_percentile"] for f in activity
                if f and f["personal_percentile"] is not None]
    if activity:
        components["activity"] = statistics.fmean(activity) * 100
        detail["activity"] = {"from": "steps, active energy, exercise minutes",
                              "n_metrics": len(activity)}

    s = sleep_figure(db, day)
    if s and s["personal_percentile"] is not None:
        score = s["personal_percentile"] * 100
        # Efficiency only means something on a staged night; on an in-bed-only
        # night it is an artefact of when the phone thought you went to bed.
        if s["staged"] and s["efficiency"] is not None:
            score = 0.7 * score + 0.3 * min(100.0, s["efficiency"])
        components["sleep"] = score
        detail["sleep"] = {"staged": s["staged"], "baseline_n": s["baseline_n"]}

    hr = figure(db, "RestingHeartRate", day)
    if hr and hr["personal_percentile"] is not None:
        components["heart"] = hr["personal_percentile"] * 100
        detail["heart"] = {"resting_hr": hr["value"], "baseline_n": hr["baseline_n"]}

    hrv = figure(db, "HeartRateVariabilitySDNN", day)
    if hrv and hrv["personal_percentile"] is not None:
        components["recovery"] = hrv["personal_percentile"] * 100
        detail["recovery"] = {"hrv": hrv["value"], "baseline_n": hrv["baseline_n"]}

    completeness = day_completeness(db, day)

    if not components:
        return {"value": None, "components": {}, "weights": {}, "detail": {},
                "partial": completeness < PARTIAL_DAY_THRESHOLD,
                "completeness": round(completeness, 2)}

    total_w = sum(SCORE_WEIGHTS[k] for k in components)
    applied = {k: SCORE_WEIGHTS[k] / total_w for k in components}
    value = sum(components[k] * applied[k] for k in components)

    return {
        "value": round(value, 1),
        "components": {k: round(v, 1) for k, v in components.items()},
        "weights": {k: round(w, 3) for k, w in applied.items()},
        "missing": [k for k in SCORE_WEIGHTS if k not in components],
        "detail": detail,
        # The UI must show "day in progress" rather than this number when
        # partial is true. The components are still meaningful; the composite
        # is not comparable with a full day's.
        "partial": completeness < PARTIAL_DAY_THRESHOLD,
        "completeness": round(completeness, 2),
    }


def brief(db, day):
    """The compact object handed to the language model.

    A few hundred tokens, because the arithmetic already happened. The model's
    job is turning these into warm, specific language — never deriving them.
    """
    figures = [f for f in (figure(db, m, day) for m in (
        "StepCount", "ActiveEnergyBurned", "DistanceWalkingRunning",
        "AppleExerciseTime", "RestingHeartRate", "HeartRateVariabilitySDNN",
        "TimeInDaylight")) if f]

    observations = []
    for f in figures:
        z = f["anomaly_z"]
        if z is not None and abs(z) >= OUTLIER_Z:
            direction = "well above" if z > 0 else "well below"
            observations.append({
                "text": f"{f['metric']} is {direction} your usual range "
                        f"({f['value']:.0f} {f['unit']})",
                "confidence": min(1.0, abs(z) / (OUTLIER_Z * 2)),
            })

    for a, b in (("StepCount", "HeartRateVariabilitySDNN"),
                 ("StepCount", "RestingHeartRate"),
                 ("AppleExerciseTime", "HeartRateVariabilitySDNN")):
        c = correlation(db, a, b, day)
        if c["reportable"] and abs(c["r"]) >= 0.2:
            observations.append({
                "text": f"{a} and {b} move "
                        f"{'together' if c['r'] > 0 else 'oppositely'} "
                        f"(r={c['r']:.2f}, n={c['n']})",
                "confidence": round(c["confidence"], 2),
            })

    goals = []
    for metric, target in GOALS.items():
        row = db.execute(
            "SELECT value FROM daily_metrics WHERE day = ? AND identifier = ?",
            (day, metric)).fetchone()
        if row and row[0] is not None:
            goals.append({
                "metric": metric, "target": target, "value": row[0],
                "percent": round(row[0] / target * 100, 1),
                "met": row[0] >= target,
            })

    return {
        "day": day,
        "figures": figures,
        "goals": goals,
        "sleep": sleep_figure(db, day),
        "score": health_score(db, day),
        "observations": observations,
        "baseline_days": BASELINE_DAYS,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("db")
    ap.add_argument("--day", required=True)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    db = sqlite3.connect(a.db)
    b = brief(db, a.day)

    if a.json:
        print(json.dumps(b, indent=2))
        return

    print(f"\n=== {b['day']} ===")
    s = b["score"]
    flag = f"   [PARTIAL DAY — {s['completeness'] * 100:.0f}% elapsed, score suppressed in UI]" if s.get("partial") else ""
    print(f"\nHealth score: {s['value']}{flag}")
    for k, v in s["components"].items():
        print(f"   {k:10s} {v:5.1f}  x{s['weights'][k]:.2f}   {s['detail'].get(k, '')}")
    if s["missing"]:
        print(f"   (no data for: {', '.join(s['missing'])} — weight redistributed)")

    print("\nFigures:")
    for f in b["figures"]:
        pct = f"p{f['personal_percentile'] * 100:.0f}" if f["personal_percentile"] is not None else "  —"
        chg = f"{f['change_percent']:+.1f}%" if f["change_percent"] is not None else "    —"
        z = f"  z={f['anomaly_z']:+.1f}" if f["anomaly_z"] is not None else ""
        print(f"   {f['metric']:26s} {f['value']:9.1f} {f['unit']:12s} {pct:>5s}  "
              f"vs {f['baseline_mean']:8.1f} (n={f['baseline_n']:3d})  {chg}{z}")

    if b["sleep"]:
        sl = b["sleep"]
        print(f"\nSleep: {sl['asleep_min'] / 60:.2f} h  eff {sl['efficiency']}%  "
              f"staged={sl['staged']}  "
              f"p{sl['personal_percentile'] * 100:.0f} of {sl['baseline_n']} comparable nights")

    print("\nObservations:")
    for o in b["observations"]:
        print(f"   [{o['confidence']:.2f}] {o['text']}")
    if not b["observations"]:
        print("   (none above threshold)")


if __name__ == "__main__":
    main()
