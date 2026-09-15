# Roadmap

Ordered so that something works end-to-end early and each milestone is
independently useful. Estimates assume solo, evenings and weekends.

A note on sequencing: **the character artwork should be commissioned or started
at M0**, not at M4. It is the longest-lead item and the only one that can't be
compressed by working harder on it — everything else can proceed in parallel
while it's in progress.

---

### M0 — Foundations (done)

- Repository structure, module boundaries, Swift package graph
- Metric catalog derived from a real export: 40 types, units, aggregation rules
- `SourceResolver` deduplication algorithm
- `tools/reference_pipeline.py` — executable specification, validated against
  664,515 real records
- Architecture and data-model documentation

### M1 — Store · ~4 days

- GRDB schema matching the reference pipeline
- `SQLiteHealthStore` implementing `HealthStore`
- Idempotent ingest; rollup rebuild scoped to affected days
- **Done when** the Swift store reproduces the reference pipeline's output on
  the same export, diffed row for row.

### M2 — Import · ~4 days

- `AppleHealthImporter` via streaming `XMLParser`
- Progress reporting; import runs off the main actor
- Unit validation that rejects loudly rather than assuming
- Drag-and-drop import UI
- **Done when** a 293 MB export imports without blocking the UI, and importing
  it a second time changes nothing.

### M3 — Dashboard · ~3 weeks

- `TrendEngine`: deltas, slopes, correlations with sample sizes
- `HealthScore` with an explainable breakdown
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

### M9 — Live2D · gated on artwork

- Cubism SDK integration behind `CharacterRenderer`
- Viseme-based lipsync replacing mouth frames
- Hair and ponytail physics, real eye tracking
- **Done when** the renderer swap is a manifest change and no dashboard code
  moved.

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
| Live2D | + artwork lead time |
