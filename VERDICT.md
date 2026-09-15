# Verdict: can this be built?

**Yes — all of it, on the hardware you have, with no cloud service and no subscription.**

Nothing you described requires a capability that doesn't exist. The parts that
are hard are not the parts that usually sound hard, so this document separates
them honestly, and ends with the things your plan is currently missing.

This is written after actually reading your export (`export.xml`, 293 MB,
**664,515 records, 2022-09-27 → 2026-09-15**) and running a full ingestion
pipeline over it — `tools/reference_pipeline.py`. Every number below is measured
on your real data, not estimated.

---

## 1. The short version

| Component | Verdict | Real difficulty |
|---|---|---|
| Parse your Apple Health export | **Solved** | Low — already demonstrated end-to-end |
| Local file storage of 4+ years | **Solved** | Low — 293 MB XML → **34 MB** queryable database |
| Dashboard, trends, health score | **Straightforward** | Low–medium — every query benchmarks **under 10 ms** |
| Local LLM writing your reports | **Straightforward** | Medium — the work is in *what you feed it*, not running it |
| She speaks (voice-over) | **Straightforward** | Low to start, medium to sound good |
| She listens (you talk back) | **Straightforward** | Low — Whisper on-device is a solved problem |
| Anime figurine, animated, on-screen | **Achievable** | **Medium–high — and it's an art problem, not a code problem** |
| True Live2D lipsync + physics | **Achievable** | High — needs rigged artwork, which is money or months |
| Automatic sync (no manual export) | **Needs an iOS companion** | Medium — see §3 |

The honest summary: **the health engineering is the easy half.** The character
is where this project will actually live or die, and it will be decided by art
assets, not by Swift.

---

## 2. What the data told us

Your export is unusually good, and that changes what's possible.

**Coverage is effectively complete.** 1,450 distinct days across 49 months, with
**zero sparse months**. There is no gap to apologise for. Four-year trends are
genuinely trustworthy.

**The metrics AURA-HealthOS had to fake are all really there.** That repo's
README lists HRV, Recovery and Breathing as "demo data, no backing model". Your
export contains 666 HRV (SDNN) readings, 2,096 respiratory-rate readings, 12,525
sleep records, 67 resting-heart-rate readings, VO2 Max, blood oxygen, wrist
temperature and walking steadiness. **Every card in your mockup can be backed by
real data.** That was the single biggest thing wrong with the old project.

**Your activity genuinely declined and is recovering.** Average daily steps by
year: 2022 → 9,008 · 2023 → 8,132 · 2024 → 7,979 · 2025 → 5,836 · 2026 → 6,478.
That's a real four-year narrative, and exactly the kind of thing a companion
with long memory should be raising with you.

### Two traps in your data that will silently corrupt everything

These are worth understanding, because I suspect at least the first one
contributed to the original project "having issues".

**Trap 1 — double counting.** Your iPhone and your Apple Watch both record the
same steps, the same distance, the same active energy. So does FitCloudPro. If
you sum the samples, you get nonsense. On 2026-09-13 the naive sum is **15,496
steps; the true figure is ~10,172** — a 1.5x inflation. **471 day/metric
combinations in your data are affected**, with inflation up to **1.9x**.

Worse, it's not a constant error you could shrug off: it only occurs on days you
wore both devices. So any trend computed naively is measuring *which devices you
wore*, not your activity. The fix is implemented in `SourceResolver` — interval-
level source prioritisation, the same approach Apple's own Health app uses.

**Trap 2 — two different sleep eras.** Of 819 reconstructed nights, only **53
have real sleep staging** (Core/Deep/REM). The other 766 predate the Watch and
carry in-bed intervals only, where "asleep" means "the phone thought you were in
bed". Charting both on one axis invents a trend that is really a hardware
upgrade. The schema records `staged` per night so the two are never blended
silently.

A third, smaller one: Apple emits active energy in `Cal` and basal energy in
`kcal`. **These are the same unit.** Anything that treats `Cal` as a calorie is
off by 1000x. Handled via per-metric unit aliasing.

---

## 3. The one thing that doesn't work the way you hoped

**HealthKit does not exist on macOS.** There is no Health app and no HealthKit
framework on a Mac, native app or not. So on the MacBook, the manual export you
described isn't a limitation of the approach — it's the only option that exists.

That's fine for now (you said you were happy to do it manually), and re-importing
is designed to be cheap and idempotent: every export contains all history, so the
second import is ~99% duplicates and must be a no-op, not a disaster.

**If you later want it automatic, the route is a small iOS companion app** that
reads HealthKit directly and pushes new samples to the Mac over your local
network. This is exactly why the code is structured as Swift packages with no
AppKit dependency below the app shell — that companion reuses `AURACore`,
`AURAStore` and `AURAAnalytics` unchanged. It needs an Apple Developer account
($99/yr) to stay installed on your phone long-term.

---

## 4. What's genuinely hard

### The character (this is the real project risk)

Making her *feel alive* is not a rendering problem. A static PNG with a glow is
obviously a static PNG within about four seconds. What sells it is a small set of
unglamorous things:

- **Breathing and blinking on independent, slightly irregular timers.** Perfectly
  periodic motion reads as mechanical. Human-feeling idle motion is noisy.
- **A mouth driven by the actual audio amplitude**, not a timer. This is the
  single biggest difference between "character speaking" and "image with audio
  playing", and it's why `VoiceEngine.speak` streams a level rather than just
  playing a sound.
- **Reactive gaze.** Her looking toward your cursor costs almost nothing and
  disproportionately sells presence.
- **Mood that comes from your data, not from randomness.** A recovery score of
  92% must never produce a sympathetic expression. `MoodResolver` is rule-based
  and deterministic for exactly this reason — the LLM writes the words, the
  rules pick the face.

You chose sprites-now / Live2D-later, which is the right call. You get something
alive in week two instead of month four, and because everything goes through
`CharacterRenderer`, the Live2D upgrade touches one module.

**Be clear-eyed about the Live2D step when you get there:** it needs your artwork
separated into ~40 PSD layers and rigged in Cubism. That's either a commission
(typically a few hundred dollars) or a serious solo art project. It is the one
part of this that money solves faster than code.

### Voice quality

`AVSpeechSynthesizer` works offline, free, today — and sounds like a system
voice. It's the right thing to ship first so she can talk in week three, but it
will not give you the companion feeling. The upgrade that matters is a local
neural TTS (Kokoro/Piper class) on the Neural Engine: still fully offline,
dramatically warmer. Hence the `VoiceEngine` protocol.

### Conversational latency

For her to feel present rather than batch-processed, the budget from you
finishing a sentence to her starting to speak is roughly **1.5 seconds**. That
means speech-to-text ~0.3 s, first LLM token ~0.5 s, first audio ~0.2 s. All
achievable on an M5, but only if she **starts speaking while still generating** —
which is why `LanguageModel.complete` streams tokens instead of returning a
finished string.

### The LLM part is easy; feeding it is not

Running an 8B-class model at conversational speed on an M5 is unremarkable in
2026. The hard part is that **your data does not fit in a context window** —
664,515 samples is on the order of 40 million tokens. Nothing fits four years.

And language models are unreliable at exactly the operations that matter here:
averaging a few hundred numbers, computing a percentage change, judging a
correlation. A companion that tells you your resting heart rate improved when it
didn't isn't a bug, it's misinformation about your own body.

So the architecture enforces a rule: **all arithmetic happens in Swift, under
test; the model only ever receives finished figures** (`HealthBrief`), and its
job is turning correct numbers into warm, specific language. If a number appears
in what she says, it was computed in Swift and passed in.

---

## 5. What your plan is missing

Things that aren't in your description but that you'll want — roughly in order of
how much you'd regret skipping them.

1. **She needs a memory.** Without one, every conversation starts cold and she
   is a chatbot with a health dashboard bolted on. A persistent store of past
   conversations plus things she's noted about you ("training for something in
   March", "sleep is worse when travelling") is what turns her into a companion.
   This is the single highest-value thing not currently in your plan.

2. **Context annotations.** Let yourself log "sick", "travelling", "exam week".
   Without them, a two-week dip looks like decline instead of flu, and she will
   confidently tell you the wrong story about your own life.

3. **An output guard.** She must not diagnose, prescribe, or invent a figure.
   The fabricated-number case is the dangerous one — it's plausible, specific
   and wrong. `OutputGuard` cross-checks every numeral against the brief.

4. **Honesty about missing data.** "I only have four days of this week" instead
   of quietly averaging over a gap. `HealthBrief.missingDays` exists for this.

5. **Encryption and backup.** Four years of your health data will sit in one
   file. FileVault plus an encrypted backup, decided deliberately.

6. **Proactive moments.** The mockup says "Good Morning, Bhawna!" — that only
   works if she can initiate. A scheduled morning brief is what makes her feel
   like she's there when you're not looking.

7. **Push-to-talk before wake-word.** A hotkey is one day's work and always
   correct. An always-listening wake word is weeks and will misfire.

8. **A doctor-facing export.** A clean PDF of the last N months. The one thing
   here with obvious outside-the-app value.

9. **Golden tests against your real export.** You have 4 years of real data —
   use it as a test fixture. Any change to aggregation gets diffed against known
   outputs. This is how you avoid silently reintroducing the double-counting bug.

---

## 6. How long

Solo, evenings and weekends, honest estimates:

| Milestone | What you have at the end | Estimate |
|---|---|---|
| M0–M2 | Import works; 4 years queryable | 1–2 weeks |
| M3 | Real dashboard, real numbers, neon look | 3–4 weeks |
| M4 | She's on screen, animated, reacting | 2–3 weeks |
| M5 | Local LLM writing real insights | 2 weeks |
| M6 | She speaks and listens | 2 weeks |
| M7+ | Memory, annotations, reports, polish | ongoing |

**Roughly 10–12 weeks to something genuinely impressive**, with a usable
dashboard at around week five. Live2D is a separate track gated on artwork.

The riskiest assumption is not technical — it's whether the character assets get
made. Everything else is ordinary engineering on a dataset that, having now read
it properly, is in good shape.

See `docs/ROADMAP.md` for the milestone detail.
