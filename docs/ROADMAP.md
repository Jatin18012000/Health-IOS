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

**Every milestone through M9 is written, `swift build` and `swift test` both
pass clean on a real Mac, and the app is reachable end to end**: import an
export, read the dashboard, talk to her, confirm what she remembers, export a
report, back it up. The character on screen is the procedural renderer, not
the Live2D rig — see M9.

**The first real compile found 11 things**, all fixed and merged: a dropped
unresolvable dependency, Swift 6 concurrency errors (several genuine, one a
real deadlock risk caught incidentally), an SDK API whose async overload would
have hung or stuttered playback if used naively, a real correctness bug in
`SourceResolver`'s unknown-source sentinel (diverged from the Python
reference), and two test bugs asserting exact `Double` equality on
non-bit-exact arithmetic. None of it touched the core health-data logic —
dedup, unit aliasing, or the sleep-staging split were all correct on the first
compile. Whether `CubismBridge` itself has compiled depends on whether the
Cubism SDK is present at `Vendor/CubismSDK/` locally, which is a separate,
unconfirmed step from the build run that got everything else green.

### What is actually verified, because it runs

| Check | Result | Where |
|---|---|---|
| `swift build` | clean, all targets | local (Mac) |
| `swift test` | **all suites pass**, zero failures | local (Mac) |
| `tools/conformance.py` | **81/81** against the edge-case fixture | CI |
| `tools/output_guard.py --self-test` | **13/13** worked examples | CI |
| `tools/check_character.py` | **30/30** while the rig was active; now reports "procedural, no rig to check" | CI |
| `tools/setup_cubism.sh` | correct when the SDK is absent, complete, or partial | local |
| `tools/reference_pipeline.py` on the real export | 664,397 samples, 1,450 days, 33.9 MB | local |
| `tools/analytics.py` on the real export | score 62.8 for 13 Sep, components sane across 14 days | local |
| Cubism Editor, `ParamMouthOpenY` scrubbed 0→1 in 21 steps | **failed** — mouth mesh doesn't deform; see M9 | local (Windows) |

`.github/workflows/checks.yml` still runs only the Python suite — it has not
been extended to run `swift build`/`swift test` in CI yet, so the green build
above is a point-in-time local result, not a standing guarantee on every push.
Adding that job is still open (see "What is left").

### Test coverage, now executed rather than merely written

**119 test cases across all ten targets, all passing** as of the first clean
`swift test` run. They encode intent — that staged and in-bed-only sleep never
pool, that a NaN never reaches her mouth, that `dataSeries[4]` needs a fifth
colour — and it is now backed by a real run, not just the writing.

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

### M1 — Store · written and compiled, `swift test` passes

- GRDB schema matching the reference pipeline
- `SQLiteHealthStore` implementing `HealthStore`
- `RollupBuilder` — daily aggregation and sleep reconstruction
- Idempotent ingest by index probe; rollup rebuild scoped to affected days
- **Acceptance:** `Tests/AURAIngestTests/ConformanceTests.swift` reads the same
  `expected.json` that `tools/conformance.py` asserts, so the two
  implementations cannot drift apart silently. Passing on both sides.
- **Remaining:** a run against the real 293 MB export was not part of this
  build pass — see M2.

### M2 — Import · written and compiled, `swift test` passes

- `AppleHealthImporter` via streaming `XMLParser`
- `ImportSession` — parse, store, rebuild, with real counts throughout
- Progress reporting; the parse runs off the main actor
- Unit validation that rejects loudly rather than assuming
- ~~Drag-and-drop UI~~ **written** — drop target and file panel, taking the
  unzipped folder or `export.xml`. Reports counts rather than a spinner, and
  says plainly that a second import being ~99% duplicates is the pipeline
  working rather than a fault
- **Remaining:** a run against the real 293 MB export to confirm the parse
  holds up at scale. Two things that can only be measured there: whether
  memory stays flat now that batches are written inside the parse, and
  whether the progress estimate — line number times a measured average line
  length, since `XMLParser` exposes no byte offset — tracks closely enough to
  be worth showing.

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

### M4 — She appears · renderer written and compiled, currently the active one

- ~~`ProceduralRenderer`: breathing, sway, blink, parallax, amplitude-driven
  mouth, mood as light and posture~~ **written**
- ~~`MoodResolver` wired to the day's real figures~~ **written**
- ~~The artwork~~ **the plan again, for now** — the Live2D rig landed and was
  meant to replace this, but its mouth mesh doesn't deform (see M9), so
  `manifest.json` points back at `.procedural` and this is what actually
  ships. It draws whenever the manifest says `.procedural`, no SDK is linked,
  or a rig is missing a required parameter, and says which case it's in.
- Entrance and idle-settle transitions
- **Done when** she is on screen, reacting to your cursor and to your data, and
  still looks alive after you've watched her for two minutes.

### M5 — She thinks · written and compiled, `swift test` passes

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
- **Remaining:** a first real generation to measure actual first-token latency
  against the ~0.5 s the voice budget assumes. That number is the one
  assumption in this milestone that cannot be checked from a build/test run
  alone.
- **Done when** she answers "how has my sleep been this year?" correctly, and
  every figure she states can be traced to a computed value.

### M6 — She speaks and listens · written and compiled, `swift test` passes

- ~~`SystemVoice` with the amplitude stream driving her mouth~~ **written**,
  rendering to buffers and tapping the playing node so levels are emitted in
  step with what is audible rather than as the synthesiser renders ahead.
  `AudioPlayback`'s `scheduleBuffer` call needed a fix for a new SDK async
  overload during the build pass — see the roadmap's opening section.
- ~~WhisperKit push-to-talk~~ **written** — hold to talk, release to send, with
  microphone resampling and a silence floor
- ~~Interruption handling~~ **written** — pressing the talk key cancels
  generation and cuts audio together
- **Remaining:** the microphone entitlement and usage string
  (`App/README.md`), and a real conversation to find out whether the end-to-end
  latency is what the budget assumes.

### M7 — She remembers · written and compiled, `swift test` passes

- ~~`memory.sqlite`: summarised conversation history, explicit noted facts~~
  **written** — its own database, because memory is the one thing here that a
  re-import cannot rebuild
- ~~Context annotations~~ **written** — matched by overlap, carried in the brief,
  and deliberately *not* excluded from baselines (see DECISIONS_PENDING §4)
- ~~Scheduled morning brief~~ **written** — with an explicit bar for what is
  worth interrupting a morning for, and a silent path that is the common one
- ~~A screen for reviewing and deleting everything she remembers~~ **written**
- **Remaining:** living with it long enough to find out whether the fact
  proposals are useful or just noise.

### M8 — Polish · written and compiled, `swift test` passes

- ~~`NeuralVoice`~~ **written, and currently not linked** — Kokoro-82M on the
  Neural Engine, so it barely contends with the language model holding the GPU.
  `kokoro-swift`'s only published version depends on an unstable package and
  SwiftPM refuses the combination, so it was removed from `Package.swift` to
  let the rest of the project reach the compiler at all. The code stays behind
  `#if canImport(Kokoro)` and she falls back to the system voice. See
  `docs/DECISIONS_PENDING.md` §13.
- ~~Additional themes~~ **written** — four, including a light one that needs an
  actual look before it ships
- ~~Doctor-facing PDF export~~ **written** — deliberately containing no
  generated prose, no scores and no reference ranges
- ~~Encrypted backup~~ **written** — `VACUUM INTO` for a consistent snapshot,
  AES-GCM, with the KDF trade recorded rather than hidden
- ~~Golden snapshots against the real export~~ **written** and verified to
  catch a real regression; not committed, since it holds real figures

### M9 — Live2D · rig landed, mouth mesh unauthored, paused on a re-model

The rig arrived on 17 September 2026 and lives in `Resources/Characters/aura/`.
Accepted on evidence rather than on the supplier's word — see
`docs/CHARACTER_DELIVERY_REPORT.md`.

**The mouth check failed, and it's worse than the risk it was written to
catch.** `ParamMouthOpenY` was scrubbed 0.00 → 1.00 in Cubism Editor and the
mouth mesh is visually indistinguishable at both ends — not a snap between two
shapes, effectively no shape change at all. `ParamMouthForm` shows the same
non-response; `ParamEyeLOpen` works correctly in the same file, which rules
out a general rendering problem and localizes this to the mouth mesh's
keyforms specifically. Full finding in `docs/CHARACTER_DELIVERY_REPORT.md`.

This needs a re-sculpted mouth mesh, which is art-authoring work, not
something fixable in code. **Decision: defer it.** A new character model is
planned from a different source; the Live2D track is paused rather than
patched, and `Resources/Characters/aura/runtime/manifest.json`'s `renderer`
was switched from `"live2d"` back to `"procedural"` so the app ships today
using the renderer that actually animates a mouth — `CharacterStageView` was
always built to fall back this way for a missing SDK, and a rig with an
unauthored mouth is the same situation from the app's point of view. The rig
files and the Live2D-specific code all stay in place; switching back is a
one-line manifest change once a working rig lands.

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

**Paused. Not resumed by doing more work on this rig — resumed when a new
model exists.** What was left, for when that happens:

1. ~~Drag `ParamMouthOpenY` slowly in Cubism Viewer~~ **done, failed** — see
   above and `docs/CHARACTER_DELIVERY_REPORT.md`.
2. **Get a mouth mesh that actually deforms**, from whoever builds the next
   model. Not a rig re-tune — the open-mouth keyform needs sculpting from
   scratch.
3. **Download Cubism SDK for Native 5.3 or newer** to `Vendor/CubismSDK/`, then
   `tools/setup_cubism.sh`, if not already done. The floor is not optional:
   moc3 version 6 needs it, and an older Core refuses it with a message that
   never mentions SDK versions.
4. **Confirm `CubismBridge` compiles** once the SDK is in place — it was never
   confirmed as part of the clean `swift build`/`swift test` run, since that
   depends on whether `Vendor/CubismSDK/` is populated locally.
5. **Tune the physics** against what you can finally see, once the bridge
   renders.

- **Done when** the manifest goes back to `"live2d"` and no dashboard code
  moved.

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
kind of flattering arithmetic this project avoids elsewhere. `swift build` and
`swift test` are now clean, so the software rows can genuinely be called
reached; the Live2D row cannot — the rig landed but needs a re-sculpted mouth
before it is a shipped feature rather than a paused one.

## What is left

1. ~~`swift build` on the Mac~~ **done — clean, all targets, `swift test`
   passing.**
2. ~~The Cubism Viewer mouth check~~ **done — failed.** The character ships as
   the procedural renderer until a new model exists; see M9.
3. **Add a macOS CI job** running `swift build`/`swift test` — one job, and
   from then on it is the gate the Python-only workflow cannot be. The clean
   run so far is a local, point-in-time result, not yet a standing guarantee.
4. **Measure the two numbers that cannot be known from a build/test run
   alone:** first-token latency against the ~0.5 s the voice budget assumes,
   and whether the import holds flat memory across the real 293 MB export.
5. **Live with it** long enough to find out whether the fact proposals are
   useful or noise, and whether the composite score's centred-on-50 behaviour
   (`docs/DECISIONS_PENDING.md` §1) is tolerable in practice.
