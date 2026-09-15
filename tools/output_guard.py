#!/usr/bin/env python3
"""
Output guard — the spec for Sources/AURAIntelligence/OutputGuard.

Checks generated text before it is ever spoken. Two distinct failure modes, and
they are not the same problem:

  **Clinical overreach.** Diagnosis, prescription, "you should stop taking".
  She observes and encourages; she does not practise medicine.

  **Fabricated figures.** A number in the output that was not in the brief.
  This is the dangerous one, because it is plausible, specific and wrong — and
  it is about the reader's own body, where they have no way to check.

The second is the harder engineering problem, because a correct answer legitimately
contains numbers that are NOT literally in the brief. "455 minutes" becomes
"7h 35m"; "0.954" becomes "95%". So the guard has to recognise honest
derivations while rejecting invention.

    python3 tools/output_guard.py --self-test
"""

import argparse
import re
import sys

# Language that is out of bounds regardless of context. Deliberately short:
# a long list of banned words produces a companion that cannot discuss health
# at all, which is its own failure.
CLINICAL_PATTERNS = [
    (r"\byou (?:have|may have|might have|likely have)\b", "suggests a diagnosis"),
    (r"\b(?:diagnos|prognos)\w*\b", "diagnostic language"),
    (r"\b(?:prescrib|dosage|dose of)\w*\b", "prescriptive language"),
    (r"\b(?:stop|start|increase|reduce) (?:taking|your) (?:medication|dose|meds)\b",
     "medication advice"),
    (r"\bthis (?:is|could be) (?:a sign of|symptomatic of|indicative of)\b",
     "diagnostic inference"),
    (r"\byou (?:should|must) see a doctor immediately\b", "urgent medical direction"),
]

# Numbers that need no source: small counts, ordinals, days of the month, and
# the clock. These match EXACTLY -- see the tolerance note in `check`.
NUMERAL = re.compile(r"\d+(?:[.,]\d+)?")
FREE_NUMBERS = set(range(0, 32)) | {60, 90, 100, 180, 365, 1000}


def derivations(value, kind="plain"):
    """Every honest way a brief figure can legitimately appear in prose.

    Anything here is a formatting or unit choice a writer would make, not a new
    claim. Anything NOT here is the model asserting a number nobody computed.

    `kind` matters more than it looks. An earlier version applied the
    minutes-to-hours derivation to every value, which meant a score component of
    91.4 quietly authorised "31" (91.4 % 60 = 31.4) and a fabricated HRV of
    31.2 ms sailed through. A derivation is only honest if the source value is
    actually the kind of quantity it claims to convert.
    """
    out = {value, round(value), round(value, 1)}

    if kind == "duration_minutes":
        # "455" -> "7h 35m"
        if value >= 60:
            out |= {int(value // 60), round(value % 60),
                    round(value / 60, 1), round(value / 60, 2)}

    elif kind == "fraction":
        # "0.88" -> "88%"
        out |= {round(value * 100), round(value * 100, 1)}

    elif kind == "percent":
        # "95.4" -> "0.95"
        out.add(round(value / 100, 2))

    elif kind == "count":
        # "10172" -> "10.2k"
        if value >= 1000:
            out |= {round(value / 1000, 1), round(value / 1000)}

    return {float(v) for v in out}


def allowed_numbers(brief):
    """Every number the text may contain, with the kind of each source value.

    Getting the kinds right is the whole job: too narrow and honest prose gets
    blocked, too broad and fabrication gets through.
    """
    allowed = {float(n) for n in FREE_NUMBERS}

    def add(value, kind):
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            allowed.update(derivations(abs(float(value)), kind))

    for figure in brief.get("figures", []):
        metric = figure.get("metric", "")
        # Only genuinely minute-valued metrics get the h/m treatment.
        kind = "duration_minutes" if metric in {
            "AppleExerciseTime", "AppleStandTime", "TimeInDaylight", "MindfulSession"
        } else "count"
        add(figure.get("value"), kind)
        add(figure.get("baseline_mean"), kind)
        add(figure.get("change_percent"), "percent")
        add(figure.get("personal_percentile"), "fraction")
        add(figure.get("baseline_n"), "plain")

    sleep = brief.get("sleep") or {}
    for key in ("asleep_min", "core_min", "deep_min", "rem_min", "awake_min"):
        add(sleep.get(key), "duration_minutes")
    add(sleep.get("efficiency"), "percent")
    add(sleep.get("personal_percentile"), "fraction")
    add(sleep.get("baseline_n"), "plain")

    score = brief.get("score") or {}
    add(score.get("value"), "plain")
    for v in (score.get("components") or {}).values():
        add(v, "plain")

    # Coefficients and sample sizes already quoted in the observations.
    for obs in brief.get("observations", []):
        for match in NUMERAL.finditer(obs.get("text", "")):
            try:
                add(abs(float(match.group().replace(",", ""))), "plain")
            except ValueError:
                pass

    day = brief.get("day", "")
    if len(day) >= 4 and day[:4].isdigit():
        year = int(day[:4])
        allowed |= {float(y) for y in range(year - 10, year + 2)}

    return allowed


def check(text, brief, tolerance=0.051):
    """Return a list of problems. Empty means the text may be spoken."""
    problems = []

    for pattern, why in CLINICAL_PATTERNS:
        m = re.search(pattern, text, re.IGNORECASE)
        if m:
            problems.append({"kind": "clinical", "detail": why,
                             "evidence": m.group()})

    allowed = allowed_numbers(brief)
    for match in NUMERAL.finditer(text):
        raw = match.group().replace(",", "")
        try:
            value = float(raw)
        except ValueError:
            continue
        # ABSOLUTE tolerance, deliberately. A relative one turns every free
        # number into a wide accepting band -- at 5%, "60" alone authorised
        # anything from 57 to 63, which is how a fabricated resting heart rate
        # of 58 bpm got through. Rounding is already covered by `derivations`.
        if any(abs(value - a) <= tolerance for a in allowed):
            continue
        problems.append({"kind": "fabricated_figure", "detail": raw,
                         "evidence": context(text, match.start())})

    return problems


def context(text, at, width=36):
    lo = max(0, at - width)
    hi = min(len(text), at + width)
    return ("..." if lo else "") + text[lo:hi].strip() + ("..." if hi < len(text) else "")


# ── self-test ──────────────────────────────────────────────────────────────

BRIEF = {
    "day": "2026-09-13",
    "figures": [
        {"metric": "StepCount", "value": 10171.6, "baseline_mean": 7344.9,
         "baseline_n": 90, "personal_percentile": 0.79, "change_percent": 18.3},
        {"metric": "HeartRateVariabilitySDNN", "value": 23.797, "baseline_mean": 36.8,
         "baseline_n": 62, "personal_percentile": 0.06, "change_percent": -6.5},
    ],
    "sleep": {"asleep_min": 455.0, "efficiency": 95.4, "deep_min": 76.0,
              "rem_min": 113.0, "personal_percentile": 0.88, "baseline_n": 53},
    "score": {"value": 62.8, "components": {"activity": 91.4, "recovery": 5.6}},
    "observations": [{"text": "StepCount and HRV move oppositely (r=-0.30, n=62)",
                      "confidence": 0.6}],
}

# (text, expected_kind or None, the numeral that must be named, why)
CASES = [
    ("You slept 7h 35m at 95% efficiency, better than 88% of comparable nights.",
     None, None, "minutes as hours, fraction as percentage — honest derivations"),
    ("Your HRV was 23.8 ms against a 90-day mean of 36.8.",
     None, None, "figures quoted directly"),
    ("You walked 10,172 steps, about 10.2k, against your 7,345 average.",
     None, None, "thousands shorthand and rounding"),
    ("Steps and HRV move oppositely (r=-0.30 across 62 days).",
     None, None, "a correlation carried from the observations"),
    ("Your score is 62.8, with activity at 91 and recovery at 6.",
     None, None, "score and components, rounded"),

    ("Your HRV was 31.2 ms last night.",
     "fabricated_figure", "31.2", "plausible, specific, computed by nobody"),
    ("Your resting heart rate averaged 58 bpm this week.",
     "fabricated_figure", "58", "the brief has no resting heart rate at all"),
    ("You averaged 12,400 steps over the last fortnight.",
     "fabricated_figure", "12400", "a confident figure for a window nobody computed"),

    ("You have sleep apnea.", "clinical", None, "a diagnosis"),
    ("You should reduce your dose of the medication.", "clinical", None, "prescriptive"),
    ("This could be a sign of an underlying condition.", "clinical", None, "diagnostic inference"),
]


def self_test():
    GREEN, RED, DIM, RESET = "\033[32m", "\033[31m", "\033[2m", "\033[0m"
    failures = 0

    for text, kind, numeral, why in CASES:
        problems = check(text, BRIEF)
        kinds = {p["kind"] for p in problems}
        flagged = {p["detail"] for p in problems}

        if kind is None:
            ok = not problems
        else:
            ok = kind in kinds and (numeral is None or numeral in flagged)

        failures += 0 if ok else 1
        print(f"  {GREEN + 'pass' + RESET if ok else RED + 'FAIL' + RESET}  "
              f"{DIM}{why}{RESET}")
        print(f'        "{text}"')
        for p in problems:
            print(f"        -> {p['kind']}: {p['detail']}")
        if not ok:
            print(f"        {RED}expected {kind or 'no problems'}"
                  f"{' naming ' + numeral if numeral else ''}{RESET}")
        print()

    print(f"{RED if failures else GREEN}{len(CASES) - failures}/{len(CASES)} "
          f"cases passed{RESET}")
    return 1 if failures else 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    sys.exit(self_test() if a.self_test else ap.print_help())
