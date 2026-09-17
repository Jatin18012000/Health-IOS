# The character

She is the reason this project exists rather than being a spreadsheet, and she
is also the part most likely to disappoint. This document is about what actually
makes an on-screen character feel present, because it is mostly not the things
people expect.

## What sells it

Not resolution, not art quality, not the number of poses. In rough order of
impact per hour of work:

1. **A mouth driven by real audio amplitude — shaped, not raw.**
   `VoiceEngine.speak` streams a 0...1 level at display rate so the mouth tracks
   the waveform. A mouth that flaps on a timer reads as a cartoon playing over
   audio; a mouth that tracks amplitude reads as someone talking. This is the
   single highest-leverage detail in the whole project.

   But the raw level does not work either, and the obvious fix is wrong.
   Measured against a simulated speech envelope:

   | | flutter | closes between words |
   |---|---|---|
   | raw amplitude | 0.27 | 1.00 |
   | fast attack, slow release | 0.11 | **0.30** |
   | gated (attack 0.5, release 0.25, gate 0.12) | 0.15 | **0.95** |

   Fast attack with slow release is the standard shape for an audio compressor,
   and it is wrong here: a compressor uses a slow release to avoid pumping, but
   a mouth has to *close between words*, and the slow release leaves it hanging
   open through 70% of the gaps — continuous mumbling. An explicit **noise
   gate** buys the calm of a slow release without that. See `MouthShaper`.

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

## The placeholder (M4): one image, continuous motion

**Not a five-pose sprite sheet.** That was the original plan and it is wrong for
a specific reason worth recording.

### Why the pose sheet doesn't work

The five poses in the design mockup — idle / stretch / cheer / focus /
good night — were AI-generated, and they are **not quite the same character**.
The jacket detailing, hair fall and face proportions drift between them. That is
inherent to image generation: each render is a new image, not the same character
posed differently. Cutting between them reads as a glitch, not an animation, and
the drift is more noticeable in motion than side by side in a grid.

Regenerating more poses does not fix it. Consistency is the thing generation
cannot give you, and it is exactly what an animation needs.

### What to do instead

**Take the single strongest image and drive everything procedurally.** No pose
swaps at all:

- **Breathing** — slow vertical scale, ~0.5% amplitude, 4–6 s period with jitter
- **Idle sway** — small rotation and horizontal drift on a slower, independent
  cycle, so the two never visibly sync
- **Parallax depth** — even a rough three-layer cut (hair-back / body /
  hair-front) gives real depth on cursor movement, and is hours of work rather
  than the full 40-layer separation
- **Blink** — a single eyelid overlay on a random 3–7 s interval
- **Mouth** — a small overlay region driven by the audio amplitude
- **Glow and rim light** — modulated by her speech level and tinted by mood

**Mood becomes lighting and posture, not a different picture.** Concerned is a
cooler rim light and a slight forward lean; proud is a warmer glow and a lift.
Mood changes what the *same* image looks like, which sidesteps the consistency
problem entirely and is more convincing than a hard cut between two drawings.

### Why this is better preparation for Live2D

The pose-sheet approach and Live2D are different mental models — discrete frames
versus continuous parameters. Building the placeholder procedurally means you
are already thinking in the target model:

| Placeholder | Live2D |
|---|---|
| rotation / drift | `ParamAngleX/Y/Z` |
| amplitude → mouth overlay | amplitude → `ParamMouthOpenY` |
| eyelid overlay | `ParamEyeLOpen` / `ParamEyeROpen` |
| parallax offset | `ParamEyeBallX/Y` + `ParamBodyAngleX` |
| breathing scale | `ParamBreath` |

Every line maps. When the rig lands, the driving code barely changes — a new
`CharacterRenderer` conformer consumes the same signals. A sprite sheet would
have thrown all of that away.

## Decision: Live2D, not 3D

**Decided.** Live2D (or Inochi2D) is the target. 3D in Blender was evaluated and
rejected. Recording the reasoning here so it does not get re-litigated.

### The decisive reason

A 3D model built *from* the reference illustrations will not look like the
reference illustrations. It will look like a new character who resembles them.
Live2D uses the actual artwork — the real pixels — and makes it move. If the goal
is *that* character on the dashboard, 3D is the one approach that guarantees she
doesn't arrive.

### The supporting reasons

**Anime in 3D is among the hardest things in 3D.** The 2D anime look depends on
cheating that 3D cannot do natively: eyes painted flat on a curved face, hair
that reads as shapes rather than volumes, faces drawn differently per angle. A
geometrically honest 3D anime face looks wrong at three-quarter angles.

Guilty Gear Xrd is the reference point, and how they did it is the tell: the team
deliberately abandoned mathematical accuracy, hand-adjusted facial geometry and
hair per camera angle, and edited vertex normals by hand. That is a studio with a
full art team *fighting* the 3D pipeline to recover the 2D look. Doing that solo,
as a side quest on a health app, is not a realistic plan.

**Apple's renderer is pointed the other way.** SceneKit is deprecated; RealityKit
is the supported path, and RealityKit is built for photorealistic AR. Cel shading
with outlines means custom ShaderGraphMaterial work and inverted-hull tricks in a
framework designed to do the opposite. Custom vertex normals — the exact thing
the anime look depends on — also frequently fail to survive glTF export cleanly.

**The cost is misallocated.** 3D buys arbitrary camera angles, full-body motion,
dynamic lighting and AR reuse. This dashboard shows her from one angle, in a
fixed pose, talking. That is precisely what Live2D was invented for. Paying the
full cost of 3D for capabilities the app never uses is the wrong trade.

**Time.** For someone who is not already a rigging-capable 3D character artist,
the chain — model, UV, texture, rig, weight paint, blendshapes, toon shader,
outline pass, export, real-time renderer — is realistically 3 to 6 months. That
is longer than the entire health app.

### The one condition that would change this

If you are already comfortable rigging and weight-painting in Blender, the time
estimate is wrong and 3D becomes defensible. It was rejected on the assumption
that you are not. If that assumption is wrong, reopen it.

## Getting the rig made

This is the long-lead item on the whole project. **Start it at M0, in parallel
with everything else** — it is the only piece that cannot be compressed later by
working harder.

### The part people underestimate

You cannot just split the reference PNG into layers. **Everything currently
hidden has to be drawn from scratch** — the face behind the hair, the torso
behind the arms, the jaw behind the jawline. A flat illustration contains no
information about what is underneath, and a rig needs all of it, because every
one of those parts moves independently.

That is why this is real art labour rather than a Photoshop afternoon, and why
"I already have the image" does not mean the hard part is done.

### What a rig needs

Roughly 30–60 separated layers:

- **Face** — eyebrows (L/R), eye whites, irises, highlights, upper and lower
  eyelids, eyelashes, mouth shapes, nose, blush
- **Hair** — front, side, back, and the ponytail split into strand groups so
  physics can act on them independently
- **Body** — torso, upper and lower arms, hands
- **Clothing and accessories** — jacket, crop top, headphones, earrings

Then rigged with the standard Cubism parameters: `ParamAngleX/Y/Z`,
`ParamEyeLOpen`/`ParamEyeROpen`, `ParamEyeBallX/Y`, `ParamBrowLY/RY`,
`ParamMouthOpenY`, `ParamMouthForm`, `ParamBodyAngleX/Y/Z`, `ParamBreath`, plus
physics groups for hair and ponytail.

> **Superseded.** A rig was delivered on 17 September 2026 and lives in
> `Resources/Characters/aura/`. The two routes below are kept for the record.
> What is actually outstanding — the `CubismBridge` target, a missing
> `physics3.json`, and the unverified mouth range — is in
> `docs/CHARACTER_DELIVERY_REPORT.md`.

### Two routes

**Commission it.** An artist separates the layers, paints the occluded regions
and rigs it in Cubism. Typically a few hundred pounds for a model of this
complexity, and they use their own editor licence, so Cubism's free-vs-PRO tier
limits stop being your problem.

**Do it yourself.** Free, and a genuine art project. Inochi Creator is fully open
source with no revenue threshold at all; Cubism Editor's free tier has feature
limits worth checking against your rig's complexity before you start.

### The integration work

The Cubism SDK for Native is **C++**, rendering through Metal. There is no
official Swift wrapper, so integration means a small Objective-C++ bridge behind
an `NSViewRepresentable` wrapping an `MTKView`. Bounded and well-trodden, but not
zero — budget for it rather than discovering it.

Inochi2D's runtime is a separate integration with its own trade-offs; evaluate
whichever you pick before committing the artwork to its format.

### Why the sprite stage still happens first

Live2D is the destination, not the starting line. The sprite renderer ships at M4
as a **placeholder that keeps the app unblocked while the rig is being made** —
it is not a competing option and not wasted work.

Two reasons it earns its place:

1. **Artwork is the long pole.** Whether commissioned or self-made, the rig will
   not exist at M4. Without sprites the entire character track blocks on it.
2. **It de-risks the seam.** The sprite renderer drives the mouth from the audio
   amplitude stream. Live2D drives `ParamMouthOpenY` from *the same* amplitude
   stream. Getting that pipeline — TTS → level → mouth — working against cheap
   assets means that when the rig arrives, it is a new `CharacterRenderer`
   conformer and a manifest change, with the hard part already proven.

## Asset layout

```
~/Library/Application Support/AURA/character/
  procedural/
    base.png        the single chosen illustration
    hair-back.png   rough three-layer cut for parallax
    hair-front.png
    mouth/          a few overlay frames driven by audio amplitude
    eyelids.png
  live2d/           model3.json, moc3, textures  (when the rig lands)
  manifest.json     which renderer, which assets, mood -> lighting mapping
```

The manifest is what lets the renderer be swapped without a rebuild.

## What to avoid

- **A single static image with a glow.** Obvious within about four seconds. The
  procedural approach above is the opposite of this: one image, but never still.
- **Cutting between AI-generated poses.** The character drift reads as a glitch.
- **Random mood changes.** Presence comes from her reacting to *you*; randomness
  reads as broken.
- **Constant motion.** Stillness between movements is what makes movement mean
  something.
- **Blocking the UI on her.** If she stutters while the LLM generates, she
  becomes a progress indicator. Render on a display link, generate off-thread.
