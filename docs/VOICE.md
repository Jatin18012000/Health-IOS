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

**2. `NeuralVoice` — local neural TTS.** A Kokoro/Piper-class model on the
Neural Engine. Still entirely offline, dramatically warmer, and the upgrade that
actually matters. This is the one to spend time on.

**3. `RemoteVoice` — hosted API.** Best quality available, but it sends text off
the machine. Opt-in, off by default, and never the automatic fallback.

## The amplitude stream

`speak(_:onLevel:)` returns a 0...1 level at display rate, tapped from the audio
engine. This is not a nice-to-have: it is what drives her mouth and her glow, and
it is the difference between "character speaking" and "image with audio playing".
Any TTS conformer that cannot provide it is not usable.

## Speech to text

**WhisperKit** — Whisper compiled to Core ML, running on the Neural Engine.
Fully on-device; no audio leaves the machine. Partial results stream so the UI
can show words appearing as you speak, which makes the wait feel shorter than it
is.

**Push-to-talk before wake-word.** A hotkey is a day's work and always correct.
An always-listening wake word is weeks of work, will misfire, and means a hot
microphone in your home. Start with the hotkey; revisit only if you find
yourself wanting it.

## Interruption

She must stop talking the moment you start. A companion that talks over you is
immediately irritating, and `VoiceEngine.stop()` has to cut the audio, not fade
it out politely.
