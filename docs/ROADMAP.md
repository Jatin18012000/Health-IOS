# Roadmap

Ordered so that something works end-to-end early and each milestone is
independently useful. Estimates assume solo, evenings and weekends.

A note on sequencing: **the Live2D rig is a parallel track that starts now, at
M0** — not at M9. It is the longest-lead item on the project and the only one
that cannot be compressed later by working harder, because it is art labour
rather than engineering. Whether commissioned or self-made, it needs to be in
progress while the software milestones proceed.

Live2D is the decided destination (`docs/CHARACTER.md`); 3D was evaluated and
rejected. The sprite renderer at M4 is a placeholder that keeps the character
track unblocked until the rig exists, not a competing approach.

---

## Where this actually is

Everything below is written and committed. **None of the Swift has been
compiled** — there is no toolchain in the environment it was written in, so
`swift build` is the first thing to do on the Mac, and expect to fix things.

What *is* verified, because it runs here:

| Check | Result |
|---|---|
| `python3 tools/conformance.py` | **81/81** against the edge-case fixture |
| `python3 tools/output_guard.py --self-test` | **12/12** worked examples |
| `python3 tools/reference_pipeline.py` on the real export | 664,397 samples, 1,450 days, 33.9 MB |
| `python3 tools/analytics.py` on the real export | score 62.8 for 13 Sep, components sane across 14 days |

The Python tools are not scratch work — they are the specification the Swift is
a port of, and `Tests/AURAIngestTests/ConformanceTests.swift` asserts against
the same `expected.json` the Python suite does, so the two cannot drift apart
without one side going red.

**Four bugs were found by building the reference implementations first**, each
of which would have been expensive to find later:

1. XML entities were not decoded, so the Apple Watch ranked as an unknown
   source and every deduplicated total silently inverted.
2. Ingest was not idempotent — re-importing would have doubled every day.
3. A relative tolerance in the output guard let a fabricated resting heart rate
   of 58 bpm through, for a metric that was not in the brief at all.
4. Untyped derivations in the same guard let a fabricated HRV of 31.2 ms
   through, via a score component's remainder.

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
- **Remaining:** drag-and-drop UI (belongs with M3), and a run against the real
  293 MB export to confirm the parse holds up at scale.

### M3 — Dashboard · analytics done, views remaining

- ~~`TrendEngine`: deltas, slopes, correlations with sample sizes~~ **done**
- ~~`HealthScoreEngine` with an explainable breakdown~~ **done**
- Design published and built on real figures — every number in it is computed
- Theme tokens, glass panels, neon treatment
- Swift Charts: sparklines, bars, donuts, radial gauges
- Honest empty states for sparse metrics (VO2 Max, blood pressure, weight)
- **Done when** the dashboard in the mockups is on screen with real numbers from
  four years of data, and nothing displayed is invented.

### M4 — She appears · renderer written

- ~~`ProceduralRenderer`: breathing, sway, blink, parallax, amplitude-driven
  mouth, mood as light and posture~~ **written**
- ~~`MoodResolver` wired to the day's real figures~~ **written**
- Remaining: the artwork itself, and the three-layer parallax cut
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

### M9 — Live2D · seam written, rig still needed

Slots in whenever the artwork is ready. The integration is written; the rig is
not, and cannot be written from here.

**The bridge is the least verified code in the project.** Everything else was
either run or written against an API read from its own source. The Cubism SDK is
a proprietary download that is not in this repository, so the Objective-C++
bridge is written from the published API shape and its signatures need checking
on first build. `docs/LIVE2D_SETUP.md` says so plainly and lists what to check.

- Objective-C++ bridge over the Cubism Native SDK (it is C++, with no official
  Swift wrapper), behind an `NSViewRepresentable` wrapping an `MTKView`
- A `Live2DRenderer` conforming to `CharacterRenderer`
- `ParamMouthOpenY` driven by the same audio amplitude stream the sprite
  renderer already uses — the pipeline is proven by then, only the consumer
  changes
- Hair and ponytail physics, real eye tracking via `ParamEyeBallX/Y`
- ~~`MouthShaper`~~ **written and measured** — raw amplitude flutters, and the
  obvious fix (fast attack, slow release) leaves her mouth hanging open through
  70% of the gaps between words. A noise gate fixes both.
- ~~`CharacterManifest`~~ **written** — renderer selection plus a parameter
  check, so a rig missing `ParamMouthOpenY` is caught at install rather than
  the first time she speaks
- **Done when** the swap is a manifest change and no dashboard code moved.

### Later — iOS companion

The only route to automatic sync, since HealthKit does not exist on macOS.
Reuses `AURACore`, `AURAStore` and `AURAAnalytics` unchanged; needs an Apple
Developer account to stay installed.

---

## Rough totals

| Point | Elapsed |
|---|---|
| Usable dashboard, real data | ~5 weeks |
| She's on screen and animated | ~8 weeks |
| She talks, listens, remembers | ~12 weeks |
| Live2D | whenever the rig lands — commission it now |
