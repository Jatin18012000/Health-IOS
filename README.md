# AURA — local AI health companion

A native macOS app that turns four years of Apple Health data into a dashboard
and a companion you can talk to. Everything runs on your own machine: local
storage, local language model, local speech. Nothing leaves the laptop.

> **Status: M0 — structure and specification.** The data pipeline is designed
> and validated against a real 664,515-record export; the Swift implementation
> is scaffolded with the module boundaries and algorithms in place, and the
> milestones in [`docs/ROADMAP.md`](docs/ROADMAP.md) fill it in. Nothing here
> has been compiled — it was written on Linux, with no Swift toolchain. The
> first thing to do on the Mac is `swift build`.

## Start here

- **[`VERDICT.md`](VERDICT.md)** — is this buildable, what's actually hard, what
  the plan is missing, and how long it takes. Read this first.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — the milestones.
- [`docs/APPLE_HEALTH_EXPORT.md`](docs/APPLE_HEALTH_EXPORT.md) — what an Apple
  Health export actually contains, measured rather than assumed.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — module boundaries and the
  three rules that hold them together.
- [`docs/CHARACTER.md`](docs/CHARACTER.md) — what makes an on-screen character
  feel alive.
- [`docs/INTELLIGENCE.md`](docs/INTELLIGENCE.md) — why the model never does
  arithmetic.
- [`docs/VOICE.md`](docs/VOICE.md) — the latency budget for conversation.
- [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md) — schema and measured performance.
- [`docs/COST.md`](docs/COST.md) — why this runs at zero cost, and the one thing that isn't free.

## Try the pipeline now

The Python reference pipeline runs today, on any machine, against a real export.
It is the executable specification the Swift store must match.

```bash
python3 tools/reference_pipeline.py ~/Downloads/apple_health_export --out aura.sqlite
```

On the reference export that produces:

```
parsed 664,515 usable samples
stored 664,515 samples across 6 sources and 2175 devices
built 14,597 daily metric rows (471 required multi-source deduplication)
reconstructed 819 nights (53 with real sleep staging, 766 in-bed only)
wrote aura.sqlite (34.1 MB)
covering 2022-09-27 -> 2026-09-15 (1,450 days)
```

293 MB of XML becomes a 34 MB database where every dashboard query returns in
under 10 ms.

## Layout

```
Package.swift          Swift package graph
Sources/
  AURACore/            metrics, units, calendar days, source deduplication
  AURAIngest/          streaming Apple Health export parser
  AURAStore/           SQLite persistence
  AURAAnalytics/       trends, correlations, scores -- all arithmetic
  AURAIntelligence/    local LLM, health briefs, output safety
  AURAVoice/           text-to-speech, speech-to-text, amplitude stream
  AURACharacter/       the companion: mood, renderer, Live2D seam
  AURADesign/          themes, chart styling
App/AURA/              the SwiftUI app
tools/                 reference pipeline and data-survey scripts
docs/
```

## Prior work

Supersedes [`Jatin18012000/AURA-HealthOS`](https://github.com/Jatin18012000/AURA-HealthOS),
which built a genuinely solid multi-tenant clinical dashboard — NestJS, Postgres,
Redis, consent system, 453 tests — and then found that shape doesn't fit one
person's data on one laptop. Two things carry over: the visual direction, and the
knowledge of where it got stuck. Its Apple Health XML parser was never written
for lack of a real export to validate against; that gap is now closed.
