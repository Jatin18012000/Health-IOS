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

### M0 — Foundations (done)

- Repository structure, module boundaries, Swift package graph
- Metric catalog derived from a real export: 40 types, units, aggregation rules
- `SourceResolver` deduplication algorithm
- `tools/reference_pipeline.py` — executable specification, validated against
  664,515 real records
- Architecture and data-model documentation

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

### M4 — She appears · ~2–3 weeks

- `SpriteRenderer`: pose cross-fade, breathing, blink, parallax, mouth frames
- `MoodResolver` wired to the day's real figures
- Entrance and idle-settle transitions
- **Done when** she is on screen, reacting to your cursor and to your data, and
  still looks alive after you've watched her for two minutes.

### M5 — She thinks · ~2 weeks

- MLX model loading, streaming completion
- `HealthBrief` construction from `AURAAnalytics`
- `OutputGuard`: clinical-language patterns and numeral cross-checking
- Chat UI with streaming
- **Done when** she answers "how has my sleep been this year?" correctly, and
  every figure she states can be traced to a computed value.

### M6 — She speaks and listens · ~2 weeks

- `SystemVoice` with the amplitude stream driving her mouth
- WhisperKit push-to-talk
- Interruption handling
- **Done when** you can hold a spoken conversation and she stops the moment you
  start talking.

### M7 — She remembers · ~1–2 weeks

- `memory.sqlite`: summarised conversation history, explicit noted facts
- Context annotations — sick, travelling, injured — so a dip has a reason
- Scheduled morning brief
- **Done when** she refers back to something from last week without being
  reminded.

### M8 — Polish · ongoing

- `NeuralVoice` — the TTS upgrade that makes her feel like a character
- Additional themes
- Doctor-facing PDF export
- Encrypted backup
- Golden tests pinned against the real export

### M9 — Live2D · when the rig lands

Slots in whenever the artwork is ready, not at a fixed point in the sequence.

- Objective-C++ bridge over the Cubism Native SDK (it is C++, with no official
  Swift wrapper), behind an `NSViewRepresentable` wrapping an `MTKView`
- A `Live2DRenderer` conforming to `CharacterRenderer`
- `ParamMouthOpenY` driven by the same audio amplitude stream the sprite
  renderer already uses — the pipeline is proven by then, only the consumer
  changes
- Hair and ponytail physics, real eye tracking via `ParamEyeBallX/Y`
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
