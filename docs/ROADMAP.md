# Roadmap

Ordered so that something works end-to-end early and each milestone is
independently useful. Estimates assume solo, evenings and weekends.

A note on sequencing, kept because it turned out to be right: **the Live2D rig
was treated as a parallel track starting at M0**, not at M9, because it was the
longest-lead item and the only one that could not be compressed later by working
harder. It landed while the software milestones were still going, which is the
outcome that note was aiming for.

Live2D is the decided destination (`docs/CHARACTER.md`); 3D was evaluated and
rejected. The procedural renderer at M4 was a placeholder to keep the character
track unblocked until the rig existed, not a competing approach — and it stays
as the fallback for a build with no SDK linked.

**The sequencing assumption that did not hold** is worth recording next to it:
this was written expecting code to be compiled as it was produced. It was not —
there is no Swift toolchain in the environment it was written in — so "written"
below never means "working". That has moved essentially all the integration
risk to a single future event, `swift build`, which is the opposite of what the
milestone-by-milestone structure was for.

---

## Where this actually is

**Every milestone through M9 is written, and the rig has landed.** The app is
reachable end to end on paper: import an export, read the dashboard, talk to
her, confirm what she remembers, export a report, back it up.

**None of the Swift has ever been compiled.** There is no toolchain in the
environment it was written in. `swift build` on the Mac is the gate on all of
it, and remains the single most informative thing that can happen to this
project. ~10,500 lines of Swift and ~430 of Objective-C++ are waiting on it.

### What is actually verified, because it runs

| Check | Result | Where |
|---|---|---|
| `tools/conformance.py` | **81/81** against the edge-case fixture | CI |
| `tools/output_guard.py --self-test` | **13/13** worked examples | CI |
| `tools/check_character.py` | **30/30** on the installed rig | CI |
| `tools/setup_cubism.sh` | correct when the SDK is absent, complete, or partial | local |
| `tools/reference_pipeline.py` on the real export | 664,397 samples, 1,450 days, 33.9 MB | local |
| `tools/analytics.py` on the real export | score 62.8 for 13 Sep, components sane across 14 days | local |

`.github/workflows/checks.yml` runs the first three on every push and pull
request. It deliberately does **not** build the Swift: no Swift here has
compiled, so a macOS job added today would go red with a backlog rather than
report anything useful. Add it once `swift build` passes — it is one job, and
from then on it is the gate this workflow cannot be.

### What is written but unverified

**119 test cases across all ten targets**, none of which has executed. They
encode intent — that staged and in-bed-only sleep never pool, that a NaN never
reaches her mouth, that `dataSeries[4]` needs a fifth colour — and that intent
is worth having written down. It is not the same as passing.

| Suite | Cases | | Suite | Cases |
|---|---|---|---|---|
| AURAIntelligence | 35 | | AURAMemory | 10 |
| AURACore | 14 | | AURAVoice | 10 |
| AURADesign | 13 | | AURAAnalytics | 8 |
| AURAReport | 13 | | AURAIngest | 6 |
| AURACharacter | 6 | | AURAStore | 4 |

### Bugs found without a compiler

The Python tools are not scratch work — they are the specification the Swift is
a port of, and `Tests/AURAIngestTests/ConformanceTests.swift` asserts against
the same `expected.json` the Python suite does, so the two cannot drift apart
without one side going red.

**Four found by building the reference implementations first:**

1. XML entities were not decoded, so the Apple Watch ranked as an unknown
   source and every deduplicated total silently inverted.
2. Ingest was not idempotent — re-importing would have doubled every day.
3. A relative tolerance in the output guard let a fabricated resting heart rate
   of 58 bpm through, for a metric that was not in the brief at all.
4. Untyped derivations in the same guard let a fabricated HRV of 31.2 ms
   through, via a score component's remainder.

**Four more by reading the uncompiled Swift adversarially:**

5. `ImportSession` captured a non-Sendable `AppleHealthImporter` in a detached
   task — a hard error under strict concurrency.
6. `Preferences` persisted through `didSet` inside `@Observable`. The macro
   rewrites stored properties into computed ones, which cannot carry a property
   observer; at worst no preference would ever have persisted, visible only
   after a relaunch.
7. `CubismModelHandle` exposed a `failureReason` set only on the paths that
   returned nil — unreachable by construction.
8. A rig-load failure was recovered by casting `NSError` to `LocalizedError`,
   which fails, swallowing the one useful sentence — including "your SDK is too
   old", the likeliest failure of all.

**And one by CI, on its first execution:** `.gitignore`'s unanchored
`export.xml` had been silently excluding the conformance fixture since the
repository was created. A fresh clone could run neither the Python suite nor
the Swift one, so the guarantee that the two cannot drift held only on the one
machine that happened to have the file.

---

### M0 — Foundations · done

- Repository structure, module boundaries, Swift package graph
- Metric catalog derived from a real export: 40 types, units, aggregation rules
- `SourceResolver` deduplication algorithm
- `tools/reference_pipeline.py` and `tools/analytics.py` — executable
  specifications, validated against 664,515 real records
- `Tests/Fixtures/edge-cases` + `tools/conformance.py` — 81 hand-computed
  assertions, asserted by both languages
- Architecture, data-model, character, voice, intelligence and cost docs

### M1 — Store · written, not yet compiled

- GRDB schema matching the reference pipeline
- `SQLiteHealthStore` implementing `HealthStore`
- `RollupBuilder` — daily aggregation and sleep reconstruction
- Idempotent ingest by index probe; rollup rebuild scoped to affected days
- **Acceptance:** `Tests/AURAIngestTests/ConformanceTests.swift` reads the same
  `expected.json` that `tools/conformance.py` asserts, so the two
  implementations cannot drift apart silently.
- **Remaining:** `swift build`, then run the suite on the Mac.

### M2 — Import · written, not yet compiled

- `AppleHealthImporter` via streaming `XMLParser`
- `ImportSession` — parse, store, rebuild, with real counts throughout
- Progress reporting; the parse runs off the main actor
- Unit validation that rejects loudly rather than assuming
- ~~Drag-and-drop UI~~ **written** — drop target and file panel, taking the
  unzipped folder or `export.xml`. Reports counts rather than a spinner, and
  says plainly that a second import being ~99% duplicates is the pipeline
  working rather than a fault
- **Remaining:** `swift build`, and a run against the real 293 MB export to
  confirm the parse holds up at scale. Two things that can only be measured
  there: whether memory stays flat now that batches are written inside the
  parse, and whether the progress estimate — line number times a measured
  average line length, since `XMLParser` exposes no byte offset — tracks
  closely enough to be worth showing.

### M3 — Dashboard · analytics done, views remaining

- ~~`TrendEngine`: deltas, slopes, correlations with sample sizes~~ **done**
- ~~`HealthScoreEngine` with an explainable breakdown~~ **done**
- ~~Design published and built on real figures~~ **done** — every number in it
  is computed
- ~~Theme tokens, glass panels, neon treatment~~ **written** — four themes
- ~~Sparklines, bars, donuts, radial gauges~~ **written**
- ~~Honest empty states for sparse metrics~~ **written** — and an empty
  dashboard now routes to the import screen rather than being a dead end
- ~~Settings~~ **written** — theme, goals, the morning-brief schedule, the
  clinical PDF, the encrypted backup, and a component list that reports what is
  *working* rather than what is configured
- **Done when** the dashboard in the mockups is on screen with real numbers from
  four years of data, and nothing displayed is invented.

### M4 — She appears · renderer written

- ~~`ProceduralRenderer`: breathing, sway, blink, parallax, amplitude-driven
  mouth, mood as light and posture~~ **written**
- ~~`MoodResolver` wired to the day's real figures~~ **written**
- ~~The artwork~~ **superseded** — a full Live2D rig landed instead, so the
  procedural renderer is the fallback rather than the plan. It still draws when
  no rig is installed or no Cubism SDK is linked, and says which
- Entrance and idle-settle transitions
- **Done when** she is on screen, reacting to your cursor and to your data, and
  still looks alive after you've watched her for two minutes.

### M5 — She thinks · written, not yet compiled

- ~~MLX model loading, streaming completion~~ **written** against the current
  `mlx-swift-lm` API (the loading API moved out of `mlx-swift-examples`)
- ~~`HealthBrief` construction from `AURAAnalytics`~~ **written**
- ~~`OutputGuard`: clinical patterns and numeral cross-checking~~ **written**,
  with the two holes prototyping found kept as tests
- ~~Chat UI with streaming~~ **written** — transcript, interruption, honest
  notice when the guard withholds a sentence
- ~~`SentenceStream`: guards each sentence before it is spoken~~ **written**,
  resolving the conflict between speaking early and checking first
- ~~Citation chips~~ **written** — `OutputGuard` reports attributions, not just
  rejections, ranked so an ambiguous small number corroborates rather than
  mis-cites
- **Remaining:** `swift build`, then a first real generation to measure actual
  first-token latency against the ~0.5 s the voice budget assumes. That number
  is the one assumption in this milestone that cannot be checked from here.
- **Done when** she answers "how has my sleep been this year?" correctly, and
  every figure she states can be traced to a computed value.

### M6 — She speaks and listens · written, not yet compiled

- ~~`SystemVoice` with the amplitude stream driving her mouth~~ **written**,
  rendering to buffers and tapping the playing node so levels are emitted in
  step with what is audible rather than as the synthesiser renders ahead
- ~~WhisperKit push-to-talk~~ **written** — hold to talk, release to send, with
  microphone resampling and a silence floor
- ~~Interruption handling~~ **written** — pressing the talk key cancels
  generation and cuts audio together
- **Remaining:** `swift build`, the microphone entitlement and usage string
  (`App/README.md`), and a real conversation to find out whether the end-to-end
  latency is what the budget assumes.

### M7 — She remembers · written, not yet compiled

- ~~`memory.sqlite`: summarised conversation history, explicit noted facts~~
  **written** — its own database, because memory is the one thing here that a
  re-import cannot rebuild
- ~~Context annotations~~ **written** — matched by overlap, carried in the brief,
  and deliberately *not* excluded from baselines (see DECISIONS_PENDING §4)
- ~~Scheduled morning brief~~ **written** — with an explicit bar for what is
  worth interrupting a morning for, and a silent path that is the common one
- ~~A screen for reviewing and deleting everything she remembers~~ **written**
- **Remaining:** `swift build`, and living with it long enough to find out
  whether the fact proposals are useful or just noise.

### M8 — Polish · written, not yet compiled

- ~~`NeuralVoice`~~ **written** — Kokoro-82M on the Neural Engine, so it barely
  contends with the language model holding the GPU
- ~~Additional themes~~ **written** — four, including a light one that needs an
  actual look before it ships
- ~~Doctor-facing PDF export~~ **written** — deliberately containing no
  generated prose, no scores and no reference ranges
- ~~Encrypted backup~~ **written** — `VACUUM INTO` for a consistent snapshot,
  AES-GCM, with the KDF trade recorded rather than hidden
- ~~Golden snapshots against the real export~~ **written** and verified to
  catch a real regression; not committed, since it holds real figures

### M9 — Live2D · rig landed, bridge written, nothing compiled

The rig arrived on 17 September 2026 and lives in `Resources/Characters/aura/`.
Accepted on evidence rather than on the supplier's word — see
`docs/CHARACTER_DELIVERY_REPORT.md`.

- ~~`MouthShaper`~~ **written and measured** — raw amplitude flutters, and the
  obvious fix (fast attack, slow release) leaves her mouth hanging open through
  70% of the gaps between words. A noise gate fixes both.
- ~~`CharacterManifest`~~ **written** — renderer selection plus a parameter
  check, so a rig missing `ParamMouthOpenY` is caught at install rather than
  the first time she speaks
- ~~The rig~~ **delivered and verified**: a real `.moc3` carrying 27 parameters,
  all 12 the renderer drives, a 1024² RGBA atlas, every reference resolving,
  and the editable `.cmo3` kept so it stays adjustable
- ~~Hair physics~~ **authored here, not delivered** — the rig defines
  `ParamHairFront/Side/Back` but shipped without a `physics3.json`, so the hair
  would have turned with the head as one rigid piece. Three pendulums now drive
  it. **The values are valid but untuned**: conventional starting points, not
  measurements against this rig's geometry
- ~~Objective-C++ bridge and the Metal render loop~~ **written** — a pure
  Objective-C header over C++ (Swift cannot import C++, so nothing C++ may
  cross it), and `Package.swift` *detects* the SDK rather than requiring it, so
  a machine without the proprietary download builds exactly as before
- ~~`tools/check_character.py`~~ **written and in CI** — references resolve,
  declared counts match, every parameter the physics names exists in the
  compiled `.moc3`, and no parameter is driven by two settings

**Remaining, in the order worth doing them:**

1. **Drag `ParamMouthOpenY` slowly in Cubism Viewer.** Five minutes, and the
   highest-risk unknown left. Her mouth is driven by a live amplitude stream
   and uses every intermediate value; a rig built for expression presets snaps
   between two shapes, which looks fine in any demo video and is wrong here.
   Worth knowing before the bridge exists rather than after.
2. **Download Cubism SDK for Native 5.3 or newer** to `Vendor/CubismSDK/`, then
   `tools/setup_cubism.sh`. The floor is not optional: the rig is moc3 version
   6 and an older Core refuses it with a message that never mentions SDK
   versions.
3. **`swift build`**, then work the errors. The bridge is the least verified
   code in the project — its call shapes were read from Live2D's published
   headers rather than recalled, but reading a header is not compiling against
   one. `docs/CHARACTER_DELIVERY_REPORT.md` lists the likely failures.
4. **Tune the physics** against what you can finally see.

- **Done when** the swap is a manifest change and no dashboard code moved.

### Later — iOS companion

The only route to automatic sync, since HealthKit does not exist on macOS.
Reuses `AURACore`, `AURAStore` and `AURAAnalytics` unchanged; needs an Apple
Developer account to stay installed.

---

## Rough totals

The original estimates, kept for comparison rather than deleted:

| Point | Estimated |
|---|---|
| Usable dashboard, real data | ~5 weeks |
| She's on screen and animated | ~8 weeks |
| She talks, listens, remembers | ~12 weeks |
| Live2D | whenever the rig lands — commission it now |

They are not comparable to what happened, and pretending otherwise would be the
kind of flattering arithmetic this project avoids elsewhere. Everything through
M9 is *written* and the rig has landed, but nothing has compiled, so none of
those rows can be called reached. The honest position: the writing is done and
the verifying has not started.

## What is left

1. **`swift build` on the Mac.** Everything else is downstream of it.
2. **The Cubism Viewer mouth check** — five minutes, and the only item on this
   list that cannot be done by anyone but a person looking at a screen.
3. **Measure the two numbers that cannot be known from here:** first-token
   latency against the ~0.5 s the voice budget assumes, and whether the import
   holds flat memory across the real 293 MB export.
4. **Live with it** long enough to find out whether the fact proposals are
   useful or noise, and whether the composite score's centred-on-50 behaviour
   (`docs/DECISIONS_PENDING.md` §1) is tolerable in practice.
5. **Add a macOS CI job** once `swift build` passes — one job, and from then on
   it is the gate the Python workflow cannot be.
