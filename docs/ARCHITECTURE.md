# Architecture

A single-user, offline, native macOS app. No server, no container, no account,
no network dependency in the default configuration.

That constraint is the architecture. The previous attempt
(`Jatin18012000/AURA-HealthOS`) was a Turborepo with a NestJS API, PostgreSQL,
Redis, magic-link auth and a patient/provider/admin consent system — a sensible
shape for a multi-tenant clinical product, and the wrong shape for one person's
health data on their own laptop. Everything here is chosen to keep the running
system to **one process and one folder**.

## Shape

```
┌──────────────────────────────────────────────────────────┐
│  App/AURA            SwiftUI · the only UI layer          │
│    Dashboard · Chat · Character stage · Import            │
└───────┬──────────────────────────────┬───────────────────┘
        │                              │
┌───────▼─────────┐  ┌─────────────────▼──────────────────┐
│  AURADesign     │  │  AURACharacter   AURAVoice          │
│  themes, charts │  │  renderer seam   TTS / STT seam     │
└─────────────────┘  └─────────────────┬──────────────────┘
                                       │ audio level
┌──────────────────────────────────────▼──────────────────┐
│  AURAIntelligence     LanguageModel · HealthBrief        │
│                       OutputGuard                        │
└──────────────────────┬───────────────────────────────────┘
                       │ finished figures only, never raw data
┌──────────────────────▼───────────────────────────────────┐
│  AURAAnalytics        trends · correlations · scores      │
│                       ALL arithmetic lives here           │
└──────────────────────┬───────────────────────────────────┘
┌──────────────────────▼───────────────────────────────────┐
│  AURAIngest           streaming export.xml parser         │
│                       + the import coordinator            │
└──────────────────────┬───────────────────────────────────┘
┌──────────────────────▼───────────────────────────────────┐
│  AURAStore            SQLite (GRDB) + Parquet archive     │
└──────────────────────┬───────────────────────────────────┘
┌──────────────────────▼───────────────────────────────────┐
│  AURACore             metrics · units · days · dedup      │
└──────────────────────────────────────────────────────────┘
```

Dependencies point downward only. `AURACore` depends on nothing.

## Three rules that do the structural work

**1. All arithmetic is in `AURAAnalytics`, never in a prompt.**
The language model receives a `HealthBrief` of finished figures and writes prose
about them. It never averages, never computes a delta, never judges a
correlation. See `HealthBrief` for the full reasoning — the short version is that
a companion that misreports your own resting heart rate is not a bug, it's
misinformation about your body.

**2. The renderer, the voice and the model are all behind protocols.**
`CharacterRenderer`, `VoiceEngine`, `TranscriptionEngine` and `LanguageModel`
each have a cheap first implementation and a better second one. Sprites become
Live2D; system TTS becomes neural TTS; MLX swaps for Ollama. Each upgrade
touches one module and nothing above it.

**3. Nothing below the app shell imports AppKit or SwiftUI where it can be
avoided.** This is what makes the future iOS companion (the only route to
automatic HealthKit sync — see `VERDICT.md` §3) a matter of adding a target
rather than a rewrite.

## Storage

One folder, under `~/Library/Application Support/AURA/`:

```
AURA/
  aura.sqlite          canonical store -- samples, daily rollups, nights
  archive/
    2022.parquet       raw samples by year, compressed
    ...
  imports/             a record of every export ingested
  character/           sprite sheets, later Live2D model
  models/              local LLM and TTS weights
  memory.sqlite        conversation history and what she's noted about you
```

**On the Parquet tier, honestly:** at your current scale it earns nothing.
SQLite holds all 664,515 samples in 34 MB and answers every dashboard query in
under 10 ms. Parquet is worth adding when the archive grows past a few million
samples or when you want DuckDB to scan years at once for the AI layer — not
before. It's in the design so the seam exists; building it in M2 would be
overbuilding. See `docs/DATA_MODEL.md`.

## Concurrency

`AURAStore` is an actor over a GRDB database queue. Import runs off the main
actor and reports progress; the UI never blocks on a 293 MB parse. Swift 6
strict concurrency is on — every public type crossing a boundary is `Sendable`.

## What is deliberately not here

- **No server, no Docker, no Postgres, no Redis.** One process.
- **No auth, no accounts, no multi-user, no consent system.** One person, one
  machine, protected by the machine's own login and FileVault.
- **No hosted LLM in the default build.** Four years of health data is the most
  sensitive thing on the disk; the premise is that it stays there.
- **No `export_cda.xml` parsing.** Duplicate data in a clinical wrapper.
