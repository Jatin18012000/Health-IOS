# Decisions waiting on you

Judgement calls I made to keep moving, each with what I chose, why, and what
changes if you choose otherwise. **Nothing here blocks progress** — every one has
a working provisional answer in the code. They are gathered here so they get
decided deliberately rather than by default.

Ordered by how much the answer changes.

---

## 1. ~~The health score baseline~~ — DECIDED: 365 days

**Resolved 15 Sep 2026. Baseline widened from 90 days to 365.**

The reasoning is recorded below because what it fixed is narrower than the
option promised, and that is worth knowing before anyone reopens it.

Every score component is your own percentile against your own history — no
population norms, no invented thresholds. Percentiles are self-referential, so
the score is centred on 50 by construction: improve for eight weeks and your
baseline improves with you. A year-long window does not remove that, it slows
it down, because an improvement takes a year rather than three months to be
absorbed into what it is measured against.

**Measured on your real data, the change moved one component out of four:**

| Component | 90-day | 365-day | Why |
|---|---|---|---|
| Activity | 91.4 | **93.7** | Steps went p79 → p86: the year behind you was less active than the quarter |
| Sleep | 90.0 | 90.0 | Only **53 staged nights exist**, all since 13 Jul 2026 |
| Heart | 36.1 | 36.1 | Resting HR has **61 readings**, first on 11 Aug 2025 |
| Recovery | 5.6 | 5.6 | HRV has **62 readings**, same start date |

Composite: 62.8 → **63.5**. Across 14 days, mean 53.3 → 54.2, sd 14.0 → 13.8.

The three that did not move are the ones your Apple Watch produces, and it has
not been worn for a year. **They will start benefiting as that history
accumulates** — the change is right, it just has not paid off yet.

Two things came out of making it:

- The constants in `tools/analytics.py` were **not actually configurable**.
  They were bound as default arguments, which Python evaluates at function
  definition time, so changing one had no effect at all. Fixed.
- A widened window makes a thin baseline *more* misleading, not less: it
  advertises a year while a new sensor has a month. `MIN_BASELINE_SAMPLES = 14`
  now suppresses a percentile rather than ranking a day against three others and
  calling it the 100th.

## 2. Score weights

Currently `activity 0.30 · sleep 0.30 · heart 0.20 · recovery 0.20`, with the
weights redistributed over whatever components have data that day.

These are mine, not derived from anything. They are defensible but not
authoritative — if recovery matters more to you than raw activity, say so and
they move. The breakdown is always shown alongside the composite, so a
mis-weighted score is visible rather than hidden.

---

## 3. ~~Your step goal~~ — DECIDED: 8,000

**Resolved 15 Sep 2026. Changed from 10,000 to 8,000.**

10,000 comes from a 1960s Japanese pedometer marketing campaign — *manpo-kei*,
"ten thousand step meter" — and has no clinical basis. Against your own 365-day
mean of 6,340, a 10,000 target is cleared roughly four days in ten; 8,000 is
reachable often enough that missing it means something.

On 13 September you walked 10,172 — **127% of 8,000**.

Implementing it turned out to be more than a constant, because the goal did not
previously exist anywhere except as a hardcoded string in the mockup:

- `Goals` in `AURACore` is a **preference**, deliberately separate from
  `AnalyticsConfig`'s statistical tunables. Nothing in the analytics layer
  consults it: percentiles and the composite score ignore goals entirely,
  because a goal is a number someone picked and a percentile is a fact about
  you. Letting an arbitrary target move a figure meant to describe reality is
  exactly the failure this separation prevents.
- Goal progress had to be carried in the **`HealthBrief`**, not just rendered.
  `OutputGuard` was verified to block "you passed your 8,000 step goal" — true,
  computed, and precisely what a companion should say. A safety check that
  rejects honest statements is a defect, not caution.

Exercise and sleep goals exist in the type but are **unset by default**: an
unset goal shows no ring rather than a target nobody chose, and sleep in
particular responds badly to being treated as a number to hit.

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
| `BASELINE_DAYS` | **365** | decided, see §1 |
| `MIN_BASELINE_SAMPLES` | 14 | below this, no percentile is reported |
| `COMPARISON_DAYS` | 30 | "vs your average" deltas |
| `MIN_CORRELATION_N` | 30 | below this, no correlation is reported |
| Correlation report threshold | \|r\| ≥ 0.2 | your steps × HRV is −0.30, so it reports |
| `OUTLIER_Z` | 3.5 | modified z-score for "unusual for you" |
| `PARTIAL_DAY_THRESHOLD` | 0.9 | below this share of a day elapsed, no score |
| `Goals.dailySteps` | **8,000** | decided, see §3 |
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
- **365-day percentile baseline** — §1 above
- **8,000 step goal, kept out of the analytics** — §3 above
