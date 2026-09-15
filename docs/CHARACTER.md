# The character

She is the reason this project exists rather than being a spreadsheet, and she
is also the part most likely to disappoint. This document is about what actually
makes an on-screen character feel present, because it is mostly not the things
people expect.

## What sells it

Not resolution, not art quality, not the number of poses. In rough order of
impact per hour of work:

1. **A mouth driven by real audio amplitude.** `VoiceEngine.speak` streams a
   0...1 level at display rate specifically so the mouth tracks the waveform.
   A mouth that flaps on a timer reads as a cartoon playing over audio; a mouth
   that tracks amplitude reads as someone talking. This is the single highest-
   leverage detail in the whole project.

2. **Irregular idle motion.** Breathing and blinking on independent timers with
   jitter. Perfectly periodic motion is the tell that something is a loop —
   randomised intervals cost nothing and fix it.

3. **Reactive gaze.** Her looking toward the cursor is a few lines of parallax
   and buys a disproportionate amount of presence.

4. **Mood that comes from the data.** A 92% recovery score must never produce a
   sympathetic expression. `MoodResolver` is deliberately rule-based and
   deterministic: her expression is a UI affordance that has to be stable and
   instant, and a face that flickers because a language model sampled
   differently is worse than no face at all. **The LLM writes the words; the
   rules pick the face.**

5. **Entrances and exits.** She should arrive when the app opens and settle when
   idle, not simply exist. Transitions are what make a figure inhabit a space.

## Version one: sprites

The five states in the design mockups — idle · stretch · cheer · focus ·
good night — cross-faded, with procedural motion layered on top:

- breathing: slow vertical scale, ~0.5% amplitude, 4–6 s period with jitter
- blink: 2-frame overlay, random 3–7 s interval
- parallax: layer offsets toward the cursor, clamped
- speech glow: rim light modulated by the audio level
- mouth: 3–4 frames selected by amplitude bands

That combination is convincing enough to ship, and it works with the artwork you
already have. Budget: keep the whole stage under ~2 ms per frame so it never
competes with the LLM for the GPU.

## Version two: Live2D

The real thing — hair and ponytail physics, genuine eye tracking, mouth shapes
rather than frames, breathing built into the rig. This is what the reference
images imply and what will make her feel alive rather than animated.

The Cubism SDK for Native renders via Metal and embeds into SwiftUI through
`NSViewRepresentable`. The code side is a new `CharacterRenderer` conformer and
nothing else — that's the entire point of the protocol.

**The cost is art, not code.** A Live2D model needs the illustration separated
into roughly 40 PSD layers (each eye, eyelid, pupil, mouth shape, hair strand
group, arm segment) and rigged with deformers in Cubism. Either commissioned —
typically a few hundred dollars for a model of this complexity — or a serious
solo project. This is the one part of the build that money solves faster than
effort, and it should be started early because it runs in parallel with
everything else.

## Asset layout

```
~/Library/Application Support/AURA/character/
  sprites/
    idle/ stretch/ cheer/ focus/ goodnight/
    mouth/       0.png 1.png 2.png 3.png
    blink/
  live2d/        model3.json, moc3, textures  (version two)
  manifest.json  which renderer, which assets, which moods map to which poses
```

The manifest is what lets the renderer be swapped without a rebuild.

## What to avoid

- **A single static image with a glow.** Obvious within about four seconds.
- **Random mood changes.** Presence comes from her reacting to *you*; randomness
  reads as broken.
- **Constant motion.** Stillness between movements is what makes movement mean
  something.
- **Blocking the UI on her.** If she stutters while the LLM generates, she
  becomes a progress indicator. Render on a display link, generate off-thread.
