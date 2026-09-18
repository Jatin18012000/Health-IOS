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

## 4. Should annotated periods be excluded from baselines?

Currently **no** — an annotation explains a dip, it does not remove it. A week
you marked as illness still counts toward your 365-day baseline, and she says
"your steps dropped, and you had that week marked as illness" rather than
quietly pretending the week did not happen.

The argument for excluding it is real: a bad fortnight drags your baseline down,
which makes the following normal weeks score better than they deserve. Your
percentiles are measured against a version of you that was ill.

The argument against is that it is a slope. Once illness is excluded, so is
travel, then a stressful month, and the baseline becomes a record of your good
weeks — flattering, and no longer a description of your life. It also breaks the
invariant that nothing a person *types* can move a computed figure, which is
what currently makes the numbers trustworthy.

Kept as-is on that basis. Worth revisiting if you find yourself distrusting a
percentile after a long illness.

## 5. The backup key derivation is fast, and arguably should not be

`Backup` derives its key with HKDF-SHA256, which is the right tool for
high-entropy input and the wrong one for a human-chosen passphrase: it is fast,
so a brute-force attempt is cheap. A deliberately slow KDF — scrypt or Argon2 —
would be materially stronger, and neither ships in CryptoKit.

Right now the 12-character minimum is doing more work than it should have to.

Options: leave it (the backup still needs the passphrase, and the threat model
is a lost USB stick rather than a targeted attacker); add a small scrypt
dependency; or raise the minimum and say plainly that the passphrase is the
whole defence. Worth deciding before you put a backup anywhere you do not
control.

## 6. The low-trust sources

Your export carries **20,885 samples from FitCloudPro** and 44 from NoiseFit,
alongside the iPhone and Watch. They currently rank below Apple devices, so they
only contribute where nothing better covered the time.

Three options: keep them ranked last *(current)*, exclude them entirely, or
promote them for periods when you genuinely wore that device and not the Watch.
If FitCloudPro was a band you wore for a stretch in 2025, option three is
materially more accurate for that window — but I have no way to know that from
the data. **You know which device was on your wrist when; I don't.**

---

## 7. Who is she?

Not asked yet, and it shapes the writing more than any other choice:

- **Her name.** AURA is the app. Is it also her?
- **Her register.** The current drafts are warm but factual — "worth watching
  rather than acting on". A more familiar voice is entirely possible, but the
  further it drifts the more a wrong figure would sting.
- **What she does with bad news.** Your HRV was at the 6th percentile on the
  13th. Should she lead with that, mention it once, or wait for a pattern?

---

## 8. The rig: commission or do it yourself

From `docs/CHARACTER.md`. Commissioning costs a few hundred pounds and takes it
off your plate; Inochi Creator is free and makes it an art project. **This is
the longest-lead item on the whole project** — whichever you pick, starting it
is worth more than any week of code.

---

## 9. Smaller constants, all one-liners

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

## 10. Unzipping the export

The Health app gives you `export.zip`. AURA does not open it. Dropping one on
the import screen gets a prompt and an **Expand it now** button that hands the
file to Archive Utility — the same thing a double-click does — and then you
drop the resulting folder.

The two ways to do it in-app both cost something:

| Option | Cost |
|---|---|
| A zip library (ZIPFoundation) | A dependency, and its supply chain, in an app whose premise is that it is small, local and auditable |
| Shell out to `/usr/bin/ditto` | Requires turning **off** the App Sandbox, which is the thing keeping an app that reads four years of your health history away from the rest of your disk |
| **Current: one double-click** | One extra click, once per export |

Provisional answer: **keep the click.** Foundation has no zip reader, so there
is no free third option. If you import often enough that the click grates, the
library is the lesser of the two costs — the sandbox is worth more than the
convenience.

---

## 11. The percentage scale on synced data is unverified

`HKUnit.percent()` is a **fraction**: blood oxygen comes back as 0.97, not 97.
`HealthKitUnits` stores it as-is, reasoning that Apple's own XML exporter writes
canonical HealthKit values, so `unit="%" value="0.97"` is what the existing
years in the store already hold and the two paths agree by construction.

**Nothing in this repository pins that.** The reference export contained six
`OxygenSaturation` records in four years, the edge-case fixture has none, and
`tools/reference_pipeline.py` does not special-case percent. So the reasoning is
sound and untested, which is exactly the shape of the `Cal`-means-kilocalorie
bug that this project already has a comment warning about.

Provisional answer: **leave it, and check on the first real sync.** Import an
XML export covering a day the phone also synced, and compare the two blood
oxygen figures. If one reads 0.97 and the other 97, the fix is one line in
`HealthKitUnits.hkUnit(for:)` and a note in the fixture so it never comes back.

The cheap permanent fix, if you want it: add a percentage metric to
`Tests/Fixtures/edge-cases/export.xml` with a hand-checked value. Then both
implementations assert the scale and neither can drift.

---

## 12. The companion is the one thing that is not free

`docs/COST.md` commits to this project costing nothing, and everything else
honours that. The iOS companion cannot.

| Option | Cost | What you get |
|---|---|---|
| Free Apple ID | £0 | App expires after **7 days**, re-sign from Xcode each time |
| Apple Developer Program | **$99/year** | Stays installed, background delivery works |
| **Keep exporting by hand** | £0 | Two minutes a month, and the path that already works |

Provisional answer: **build it, do not pay for it yet.** The code is written and
the seven-day install is enough to find out whether automatic sync is worth
having. If after a month the manual export has not annoyed you, the answer is
that $99/year buys a convenience you do not need — and `VERDICT.md` was right
that manual import is not a limitation of the approach on macOS, it is the only
option that exists.

---

## 13. The neural voice is out, because it cannot be resolved

The first `swift build` on the Mac produced **exactly one error**, and it was
not a compile error — dependency resolution failed before a line of Swift was
read:

```
'kokoro-swift' is required using a stable-version but
'kokoro-swift' depends on an unstable-version package 'misaki'
```

`kokoro-swift` publishes one version, 0.1.0, which depends on a package with no
stable release. SwiftPM refuses that combination and there is no newer version
to move to. So one small unavailable package was hiding the entire project from
the compiler.

It has been removed from `Package.swift`. This cost the neural voice and
nothing else: `NeuralVoice` sits behind `#if canImport(Kokoro)` and
`VoiceFactory.speech` falls back to `SystemVoice`, which is precisely what that
guard was written for. She still talks; she talks in Apple's voice.

| Option | Cost |
|---|---|
| **Current: removed** | System voice instead of Kokoro-82M |
| Pin to a branch or revision | Keeps the feature, but unreproducible builds against a moving target on an early-stage project |
| Fork and vendor it | Keeps the feature, adds a fork to maintain |
| Wait for a stable release | Free, and may never happen |

Provisional answer: **leave it out until the rest compiles.** The immediate
goal is to find out what else is broken across ~11,000 lines that have never
been near a compiler, and one unresolvable dependency should not go on hiding
all of it. Revisit once the build is clean — `docs/VOICE.md` records why the
neural voice was wanted, and adding it back is one line.

Worth noting for the record: this is the risk that was flagged *before* the
build ran. Of the four dependencies, `kokoro-swift` was the one called out as
the smallest and least established, and it is the one that failed.

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
- **Zip stays a double-click, sandbox stays on** — §10 above
