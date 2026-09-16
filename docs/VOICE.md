# Voice

## The latency budget

For conversation to feel present rather than batch-processed, the gap between
you finishing a sentence and her starting to speak should be around
**1.5 seconds**:

| Stage | Budget |
|---|---|
| Speech-to-text finalises | ~0.3 s |
| First LLM token | ~0.5 s |
| First audio out | ~0.2 s |
| Slack | ~0.5 s |

All achievable on an M5 — **but only if she starts speaking while still
generating.** Waiting for a complete response before synthesising blows the
budget on its own. Hence `LanguageModel.complete` streams tokens, and speech
starts at the first sentence boundary.

## Text to speech

Three conformers, in build order:

**1. `SystemVoice` — AVSpeechSynthesizer.** Free, offline, zero setup, no
download. Ships first so she can talk in week three. It sounds like a system
voice, and it will not give you the companion feeling — but having her speak
early is what tells you whether the rest of the illusion is working.

**2. `NeuralVoice` — Kokoro-82M, via `kokoro-swift`.** Apache 2.0 for both the
model and the code. Still entirely offline, dramatically warmer, and the upgrade
that actually matters.

Adding a second model to a machine already holding a 14B LLM sounds reckless,
and it is not, for two reasons worth stating plainly:

- **82M parameters** — a few hundred megabytes against the language model's
  eight or nine gigabytes.
- **It runs on the Neural Engine, not the GPU.** The ANE sits idle while MLX
  holds the GPU, so the two barely contend. Around 100 ms to synthesise a
  sentence, well inside the budget.

It synthesises **per sentence**, which is not an optimisation but a consequence:
`SentenceStream` already releases one guarded sentence at a time, so a sentence
is exactly what arrives. Synthesising a whole response would mean waiting for
generation to finish — the thing the streaming design exists to avoid.

The engine is chosen by `VoiceFactory` on whether the weights are present, so
installing them later upgrades her with no code change.

**3. `RemoteVoice` — hosted API.** Best quality available, but it sends text off
the machine. Opt-in, off by default, and never the automatic fallback.

## The amplitude stream

`speak(_:onLevel:)` returns a 0...1 level at display rate, tapped from the audio
engine. This is not a nice-to-have: it is what drives her mouth and her glow, and
it is the difference between "character speaking" and "image with audio playing".
Any TTS conformer that cannot provide it is not usable.

## Speech to text

**WhisperKit** — Whisper compiled to Core ML, running on the Neural Engine.
MIT-licensed, fully on-device; no audio leaves the machine.

**No streaming partials, and the protocol says so.** An earlier draft here
promised interim text appearing as you speak. WhisperKit's open-source surface
does not do that — low-latency streaming transcription is in Argmax's paid tier,
and the free package transcribes a complete buffer. Faking partials by
re-transcribing a growing buffer several times a second would burn the Neural
Engine the language model needs, and still be wrong until you stopped talking.

So `TranscriptionEngine` reports an **audio level** while you hold the key, and
the text arrives when you let go. For push-to-talk that is the whole interaction
anyway.

**`base.en`, not `large-v3`.** A push-to-talk utterance is a few seconds of
clear, close-mic speech in one known language — the easiest case there is.
`base.en` handles it in a fraction of the time and ~150 MB instead of ~1.5 GB,
and that memory is contested: the language model, the TTS voice and the app are
all resident at once during a spoken exchange.

**Push-to-talk before wake-word.** A hotkey is a day's work and always correct.
An always-listening wake word is weeks of work, will misfire, and means a hot
microphone in your home. Start with the hotkey; revisit only if you find
yourself wanting it.

Two details that matter in practice:

- **The microphone will not be 16 kHz mono.** The input node hands back the
  hardware's format, usually 44.1 or 48 kHz and often stereo. Feeding that to
  Whisper unconverted does not fail — it transcribes gibberish, which is worse.
  Every buffer goes through an `AVAudioConverter` first.
- **Whisper hallucinates on silence.** A held key with nothing said comes back
  as "Thank you." or a stray subtitle line, confidently. Anything under a third
  of a second is discarded without transcribing.

## Interruption

She must stop talking the moment you start. A companion that talks over you is
immediately irritating, and `VoiceEngine.stop()` cuts the audio rather than
fading it politely.

**Push-to-talk makes this free.** Pressing the talk key stops her — it is an
unambiguous signal, and no acoustics are involved.

Interrupting by voice alone is a different and much larger problem: her own
output through the speakers is the loudest thing the microphone can hear, so
detecting that *you* started talking means echo cancellation. That is a real
project with real misfires, and the hotkey sidesteps it entirely. Worth
revisiting only if hands-free use turns out to matter.
