# AURA — working notes

A local-only macOS health companion. One person, one machine, no server, no
account, no network in the default build. Read `VERDICT.md` first, then
`docs/ARCHITECTURE.md`.

## Ground truth

**The reference implementations are the spec.** `tools/reference_pipeline.py`
defines ingestion and `tools/analytics.py` defines every computed figure. Both
run today and were validated against a real 4-year export (664,515 records).
The Swift in `Sources/` is a port of them, not an independent design. If they
disagree, the Python is right until deliberately changed on both sides.

**`Tests/Fixtures/edge-cases/expected.json` is the single definition of correct
ingestion.** Both `tools/conformance.py` and
`Tests/AURAIngestTests/ConformanceTests.swift` assert against that one file, so
the two implementations cannot drift apart silently. Change behaviour there
first; change it in one language only and a test goes red on the other side.

Before touching ingestion or aggregation:

```bash
python3 tools/conformance.py        # 81 checks, all must pass
```

## Invariants — breaking these silently corrupts the data

**Cumulative metrics must be source-deduplicated before summing.** An iPhone in
a pocket and a Watch on a wrist count the same steps. Naive summing inflates
real days by up to 1.9× — and only on days both devices were worn, so any trend
computed without it measures which devices were worn rather than the person.
`SourceResolver` does this at interval level. 471 day/metric combinations in the
reference export are affected.

**Unit aliasing is scoped per canonical unit, never global.** `count/min` means
beats per minute for `HeartRate` and breaths per minute for `RespiratoryRate`; a
single alias table maps one of them wrong. `Cal` in a HealthKit export is a
*kilo*calorie — reading it as a calorie is a silent 1000× error.

**XML entities must be decoded in attribute values.** Apple entity-encodes
device descriptors on nearly every wearable sample. Left encoded, a source name
fails its trust-order match, the Watch ranks as unknown, and every deduplicated
total inverts. Swift's `XMLParser` handles this; anything hand-rolled must.

**Staged and in-bed-only sleep are not the same quantity.** Only 53 of 819
nights in the reference data have real Core/Deep/REM staging. Charting both on
one axis shows a hardware upgrade and calls it a trend. `SleepNight.isStaged`
exists to keep them apart; percentiles rank a night only against its own kind.

**Sleep intervals are unioned, never summed.** The `InBed` interval contains
every stage inside it.

**All arithmetic lives in `AURAAnalytics`.** The language model receives a
finished `HealthBrief` and writes prose about it. It never averages, never
computes a delta, never judges a correlation. If a number appears in what she
says, it was computed in Swift and passed in. `OutputGuard` cross-checks every
numeral before anything is spoken.

**Goals never touch the analytics.** `Goals` in `AURACore` is a user preference
and `AnalyticsConfig` holds statistical tunables; they are separate types on
purpose. Percentiles and the composite score do not consult goals at all — a
goal is a number someone picked, a percentile is a fact about the person, and
letting the first move the second corrupts a figure meant to describe reality.
Goal progress *is* carried in the `HealthBrief`, so `OutputGuard` permits her to
state it.

**Personal baselines, never population norms.** "Higher than your own last year"
is a fact. "Above average for your age" is unlicensed medicine. The baseline is
365 days (`AnalyticsConfig.baselineDays`), and a percentile is suppressed below
14 readings rather than ranking a day against three others.

## Known limitation, not a bug

The composite score is percentile-based and therefore **centred on 50 by
construction** — sustained improvement is slow to show in it, because improving
moves the baseline too. The 365-day window slows that absorption rather than
removing it. Measured on real data: mean 54, sd 14. This is a deliberate trade
recorded in `docs/DECISIONS_PENDING.md` §1, along with the measurement showing
it moved one score component out of four. Don't "fix" it without reading that.

## Environment

- No Swift toolchain in the cloud session — Swift here is **written, not
  compiled**. `swift build` is the first thing to run on a Mac.
- Python tools need no dependencies beyond the standard library.
- The user's real export is not in the repo and never should be — `.gitignore`
  blocks `export.xml` and `*.sqlite`.

## Open questions

`docs/DECISIONS_PENDING.md` holds every judgement call that is the user's
rather than ours, each with a working provisional answer. Add to it rather than
guessing, and don't silently change one of the constants it lists.
