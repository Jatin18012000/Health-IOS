# Decisions waiting on you

Judgement calls I made to keep moving, each with what I chose, why, and what
changes if you choose otherwise. **Nothing here blocks progress** — every one has
a working provisional answer in the code. They are gathered here so they get
decided deliberately rather than by default.

Ordered by how much the answer changes.

---

## 1. The health score is self-referential, so it centres on 50

**This is the most consequential one, and it is a product decision rather than a
technical one.**

Every score component is your own percentile against your last 90 days. That
makes it honest — no population norms, no invented thresholds, no pretending to
know what your heart rate "should" be. But percentiles are self-referential, so
**the score is centred on 50 by construction.** Measured across your last
14 days: mean 50.9, standard deviation 16.4, range 16.9–72.3.

The consequence: **you can never have a good month.** If you improve steadily
for eight weeks, your baseline improves with you and the score stays around 50.
It measures "today versus recent you", and it always will.

| Option | What you get | What you lose |
|---|---|---|
| **A. Keep it as-is** *(current)* | Honest, personal, no invented norms | Sustained improvement never shows |
| **B. Blend in absolute targets** | A good month reads as a good month | You pick the targets, and they are arbitrary |
| **C. Widen the baseline to 365 days** | Improvement registers over months | Slow to react; your first year has no baseline |

I chose A because it cannot lie to you. But B is a legitimate preference and
plenty of people would rather have a number that rewards progress. **C is
probably the best compromise** and is a one-constant change
(`BASELINE_DAYS` in `tools/analytics.py`).

---

## 2. Score weights

Currently `activity 0.30 · sleep 0.30 · heart 0.20 · recovery 0.20`, with the
weights redistributed over whatever components have data that day.

These are mine, not derived from anything. They are defensible but not
authoritative — if recovery matters more to you than raw activity, say so and
they move. The breakdown is always shown alongside the composite, so a
mis-weighted score is visible rather than hidden.

---

## 3. Your step goal

The dashboard assumes **10,000**. Worth knowing before you confirm it: your
actual 90-day mean is **7,345**, and your four-year average has ranged from
9,008 (2022) down to 5,836 (2025) and back to 6,478 this year.

10,000 is a marketing number from a 1960s pedometer campaign, not a clinical
threshold. A goal you clear four days in ten is arguably worse than one you
clear eight days in ten. **8,000 would fit your actual life better.** Your call.

---

## 4. The low-trust sources

Your export carries **20,885 samples from FitCloudPro** and 44 from NoiseFit,
alongside the iPhone and Watch. They currently rank below Apple devices, so they
only contribute where nothing better covered the time.

Three options: keep them ranked last *(current)*, exclude them entirely, or
promote them for periods when you genuinely wore that device and not the Watch.
If FitCloudPro was a band you wore for a stretch in 2025, option three is
materially more accurate for that window — but I have no way to know that from
the data. **You know which device was on your wrist when; I don't.**

---

## 5. Who is she?

Not asked yet, and it shapes the writing more than any other choice:

- **Her name.** AURA is the app. Is it also her?
- **Her register.** The current drafts are warm but factual — "worth watching
  rather than acting on". A more familiar voice is entirely possible, but the
  further it drifts the more a wrong figure would sting.
- **What she does with bad news.** Your HRV was at the 6th percentile on the
  13th. Should she lead with that, mention it once, or wait for a pattern?

---

## 6. The rig: commission or do it yourself

From `docs/CHARACTER.md`. Commissioning costs a few hundred pounds and takes it
off your plate; Inochi Creator is free and makes it an art project. **This is
the longest-lead item on the whole project** — whichever you pick, starting it
is worth more than any week of code.

---

## 7. Smaller constants, all one-liners

| Constant | Current | Note |
|---|---|---|
| `BASELINE_DAYS` | 90 | percentile window — see §1 |
| `COMPARISON_DAYS` | 30 | "vs your average" deltas |
| `MIN_CORRELATION_N` | 30 | below this, no correlation is reported |
| Correlation report threshold | \|r\| ≥ 0.2 | your steps × HRV is −0.30, so it reports |
| `OUTLIER_Z` | 3.5 | modified z-score for "unusual for you" |
| `PARTIAL_DAY_THRESHOLD` | 0.9 | below this share of a day elapsed, no score |
| `SLEEP_DAY_CUTOFF_HOUR` | 18:00 | a session ending before this belongs to the previous night |

---

## Already decided (recorded so they don't get reopened)

- **Local-only, no App Store** — `docs/COST.md`
- **Native SwiftUI, not Tauri or web** — your call, session start
- **SQLite as canonical store, Parquet deferred** — `docs/ARCHITECTURE.md`;
  at 34 MB and sub-10 ms queries, Parquet currently earns nothing
- **Qwen3.x 14B 4-bit for prose, Apple Foundation Models for structured output**
  — `docs/INTELLIGENCE.md`
- **Live2D over 3D, sprites as placeholder** — `docs/CHARACTER.md`
- **Idempotency by index probe, not a unique index** — `docs/DATA_MODEL.md`;
  measured, the index cost 21.9 MB to enforce what a probe does for free
