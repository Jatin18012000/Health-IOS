# Cost

**Yes — this can be built and run for £0, permanently.** Every runtime component
has a free, license-clean option, and none of them is a crippled tier that you
outgrow.

There is exactly one line item that can cost money, and it is optional.

## Free, and genuinely free

| Component | Choice | Licence / cost |
|---|---|---|
| IDE and toolchain | Xcode, Swift, SPM | Free |
| Running the app on your own Mac | Local signing | **Free — no developer account needed** |
| Database | SQLite | Public domain |
| Swift DB layer | GRDB.swift | MIT |
| LLM runtime | MLX | MIT |
| LLM weights | Qwen3.x | Apache 2.0 — commercial use included |
| Structured extraction | Apple Foundation Models | Free, built into macOS 26 |
| Speech to text | WhisperKit | MIT |
| Text to speech (v1) | AVSpeechSynthesizer | Free, built into macOS |
| Text to speech (v2) | Kokoro / Piper | Apache 2.0 / MIT |
| Charts | Swift Charts | Free, built into macOS |
| Character rigging | Live2D Cubism SDK | **Free below ¥10M (~£50k) annual revenue** |
| Character rigging (alt) | Inochi2D / Inochi Creator | Open source, unrestricted |

### On the Apple Developer account

**You do not need the $99/year account to build and run this on your own Mac.**
Xcode signs local builds with your ordinary Apple ID and macOS runs them
indefinitely. The account is needed only for:

- installing the future **iOS companion** on your phone long-term (the free
  provisioning profile expires every 7 days, which is unusable for a background
  sync app)
- distributing a notarised build to anyone else

Neither is required for the project as scoped.

### On Live2D

Live2D's SDK Release License exempts individuals and small businesses with
annual revenue under **¥10 million** (roughly £50,000). You are comfortably
inside that, so the SDK itself costs nothing.

The nuance is the **editor**, not the SDK: Cubism Editor has a free tier with
feature limits, and the paid "PRO for indie" tier removes them. Whether the free
editor is sufficient depends on how complex the rig is — worth checking before
committing, and irrelevant if you commission the rigging (the artist uses their
own licence) or use **Inochi2D**, which is fully open source with no revenue
threshold at all.

## The one real cost

**Character artwork and rigging.** Free if you make it yourself or use artwork
you already have. A commissioned Live2D rig of the complexity in your reference
images is typically a few hundred pounds.

This is genuinely optional in the sense that the sprite renderer (M4) works with
flat artwork and costs nothing. It only becomes a question at M9.

## Deliberately excluded

Things that would introduce recurring cost and are therefore not in the default
build:

- **Hosted LLM APIs.** Also excluded on privacy grounds — four years of health
  data staying on the machine is the premise of the project.
- **Hosted TTS** (ElevenLabs and similar). Available behind `VoiceEngine` as an
  opt-in, never the default or the fallback.
- **Any cloud database, sync service or hosting.** There is no server.

## Running cost

Zero. No API calls, no subscriptions, no hosting. The only ongoing consumption
is disk (~34 MB of health data, plus 5–20 GB of model weights) and electricity.
