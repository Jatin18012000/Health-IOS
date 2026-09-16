# The character problem — a briefing

**Purpose of this file.** It is written to be handed to someone outside the
project — another person, or another AI — who knows nothing about it. Everything
needed to give a useful answer is here, including the constraints that rule
options out and the reasons behind decisions already taken, so they do not get
re-litigated.

If you are that outside reader: the question at the very bottom is the one being
asked. Everything above it is context.

---

## 1. What is being built

AURA is a **local-only macOS health companion**. It ingests a manually exported
Apple Health file, shows a dashboard of computed figures, and features an anime
character who speaks the summaries aloud and answers questions using a local
language model. No server, no account, no network in the default build.

The app is **built and working today** except for one thing: the character has
no artwork. Ingestion, analytics, the dashboard, the local LLM, speech, memory
and the settings screen are all implemented.

## 2. The person's situation — the binding constraints

These are not preferences. An answer that violates one of them is not usable.

| Constraint | Detail |
|---|---|
| **Cannot draw** | No illustration skill, and not looking to spend months acquiring it |
| **Must be free** | Set as a hard requirement at project start. Commissioning an artist (~£200–500) is therefore out unless explicitly reconsidered |
| **Two machines** | Art tools on a **Windows** laptop; the app itself builds and runs on a **MacBook (Apple M5)** |
| **Tools installed** | Krita (free, Windows) and Live2D Cubism Editor FREE (Windows) — both running |
| **Not published** | Local-only, single user, never shipped to the App Store. This makes most asset licences trivially satisfiable |

## 3. What the software actually needs

The app has **two** renderers behind one protocol (`CharacterRenderer`). Either
can be used; they need very different assets.

### Route A — the procedural renderer (implemented, working, needs 5 PNGs)

Drives one illustration with continuous motion. It is **not** a static image
with a glow — it animates breathing, blinking, gaze parallax and a mouth driven
by live audio amplitude.

Required files, all **PNG with transparency, identical canvas size, aligned**:

```
~/Library/Application Support/AURA/character/procedural/
  base.png         her, with the front hair removed
  hair-back.png    the hair mass behind her head
  hair-front.png   the bangs / fringe
  eyelids.png      closed-eye shapes; fades in as she blinks
  mouth/1..4.png   mouth-openness overlays, closed through wide
manifest.json      {"renderer": "procedural", "assetPath": "procedural"}
```

The three body layers are composited at different parallax depths
(`hair-back` −0.5, `base` 0, `hair-front` +0.8), which is what produces real
depth when the cursor moves. `eyelids.png` is cross-faded by an internal blink
timer. The mouth frame is indexed from a 0…1 audio level.

**Everything must be the same canvas size and aligned**, because the renderer
simply stacks them; it never positions anything.

### Route B — a Live2D Cubism rig (code written, no rig exists)

Loads `.moc3`, `.model3.json`, `.physics3.json` and textures via the Cubism SDK
for Native. Gives head rotation, hair physics and real facial expression that
Route A cannot.

It drives exactly these 12 parameters, which must exist and be spelled exactly:

```
ParamAngleX      ParamAngleY      ParamEyeBallX    ParamEyeBallY
ParamEyeLOpen    ParamEyeROpen    ParamMouthOpenY  ParamMouthForm
ParamBrowLY      ParamBrowRY      ParamBodyAngleZ  ParamBreath
```

**Caveat:** the Swift for this route has never been compiled. The Cubism SDK is
a proprietary download absent from the repository, so that code path is behind a
compile-time guard and its exact API calls are unverified.

### The seam

Swapping A for B is a new protocol conformer plus a change to `manifest.json`.
**No work done on Route A is wasted if Route B happens later.** The dashboard
never learns which renderer is drawing her.

## 4. The one technical detail that matters most

Her mouth is driven by a **live audio amplitude stream** from the
text-to-speech engine, not by pre-recorded animation or a timer.

This was measured against a simulated speech envelope:

| Approach | Flutter | Closes between words |
|---|---|---|
| Raw amplitude | 0.27 | 1.00 |
| Fast attack, slow release | 0.11 | **0.30** |
| Gated (attack 0.5, release 0.25, gate 0.12) | 0.15 | **0.95** |

The middle row is the standard audio-compressor shape and it is **wrong** here:
a mouth must close between words, and a slow release leaves it hanging open
through 70% of the gaps — continuous mumbling. The gated version is what ships.

Consequence for artwork: on Route B, `ParamMouthOpenY` needs a **smooth,
continuous range** where every intermediate value reads well. Rigs built for
expression presets snap between two mouth shapes; that looks fine in a demo
video and is wrong here. On Route A, four overlay frames are enough.

## 5. What has already been ruled out, and why

Do not re-propose these without new information.

**3D in Blender.** Evaluated and rejected. Anime faces rely on 2D cheating that
3D cannot do natively — eyes painted flat on a curved face, hair silhouettes
that only work from one angle. Studios solve this with custom shaders, per-angle
hair meshes and hand-edited vertex normals. Not achievable by a beginner.

**A five-pose AI sprite sheet.** Was the original plan. The five generated poses
are **not quite the same character** — jacket detailing, hair fall and face
proportions drift between them, and cutting between them reads as a glitch.
This drift is the single most important fact about using AI image generation
here.

**Drawing it by hand.** Requires redrawing everything currently hidden — the
face behind the hair, the torso behind the arms — because every part moves
independently. Roughly 40–80 hours *and* illustration skill. Ruled out by
constraint 1.

**Commissioning.** ~£200–500, would produce the best result, and a full brief is
already written and ready to send. Ruled out only by the free-of-cost
constraint, and is the obvious answer if that constraint is ever relaxed.

**Inochi2D / Inochi Creator.** The open-source alternative to Live2D. Rejected
because its runtime is a separate integration — the reference implementation is
written in D, the Rust reimplementation renders through OpenGL which Apple has
deprecated on macOS, and neither has a Swift binding. Cubism ships an official
Metal renderer. The formats are not interchangeable.

## 6. Verified facts about the available free tools

Checked against primary sources, not assumed.

### Live2D Cubism Editor FREE

| | |
|---|---|
| Parameters | 30 max — project needs 12 ✅ |
| ArtMeshes | 100 max — project needs 30–60 ✅ |
| Parts | **30 max** — the tight one, needs disciplined grouping ⚠️ |
| Physics + `.physics3.json` export | **included in FREE** ✅ |
| `.moc3` export for SDK use | works, within the limits above ✅ |
| Warp deformer divisions | **9×9** (PRO: 100×100) — the quality ceiling ⚠️ |

Two traps: exceeding any limit means the file **cannot be saved**, not merely
exported. And the texture atlas must be generated before `.moc3` export is even
selectable.

### Gemini / Nano Banana image generation

**Cannot output an alpha channel.** Google's image models emit flat RGB across
the whole family. Asking for a transparent background returns solid white, solid
black, or a *painted-on checkerboard pattern* that looks transparent in a
thumbnail and is fully opaque.

Workaround: generate on a flat chroma-key colour — **magenta `#FF00FF`**, chosen
because it appears nowhere on the character, so keying it out will not eat skin
tones or eye highlights the way white would. Then Krita's
Filter → Colors → **Color to Alpha**, which handles anti-aliased edges correctly.

### Live2D official sample models

Free to use by individuals and businesses under ¥10M annual revenue, for both
commercial and non-commercial work. Some models — Hiyori Momose among them —
forbid **any** design alteration and require a copyright notice. For a
local-only personal app these terms are easy to satisfy.

## 7. The options currently on the table

| | Skill needed | Effort | Cost | Result |
|---|---|---|---|---|
| **A. AI-generated art → 5-layer cut → procedural renderer** | none — prompting and keying | 2–3 h | free | **her**, breathing, blinking, gaze-tracking, audio-driven mouth |
| **B. Free pre-rigged Live2D sample model** | none | ~1 h | free | full rig quality, but a stock character, and no design changes permitted |
| **C. Commission a rig** | none | ~0 of their time | £200–500 | her, fully rigged |
| **D. Hand-draw and self-rig** | illustration | 40–80 h | free | her, fully rigged |

The current plan is **A**, because it is free, needs no drawing, produces *her*
rather than a stock character, and the renderer for it already works.

### The method worked out for option A

The failure mode is consistency drift (§5). The rule that avoids it:

> **Generate the character once. Then edit that one image five times.**
> Image *editing* preserves the subject; image *generation* re-invents it. Feed
> the same source image to every edit — never the previous edit's output.

For `eyelids` and the mouth frames, ask for **whole-image** edits ("close her
eyes, change nothing else") and crop to the region afterwards in Krita.
Whole-image edits hold framing; "isolate this element" requests re-frame and
rescale.

To verify alignment, stack each result over the original in Krita with blend
mode **Difference** — anything unchanged renders black, so any drift lights up
immediately.

## 8. Known weaknesses of the current plan

Stated plainly so an outside reader can attack them:

1. **AI edit drift is unsolved, only mitigated.** Several re-rolls per layer are
   expected. `hair-back` is the worst case, because "complete the hair mass
   where the head overlapped it" is genuine inpainting.
2. **Route A cannot do head rotation, hair physics or real expression.** It
   animates breathing, blinking, gaze parallax and the mouth. That is all.
3. **No alpha from the generator**, so every asset needs a keying pass.
4. **Nobody has verified the end-to-end path yet** — no asset has been produced
   and loaded into the running app.

---

## The question

> Given the constraints in §2 — cannot draw, must be free, Windows for art and
> macOS for the app — and the asset requirements in §3, **is there a better
> option than plan A in §7?**
>
> Specifically:
>
> 1. Is there a tool or workflow that produces **consistent, aligned, layered**
>    character art from a single AI-generated image, better than
>    generate-once-then-edit? Automatic layer separation, character-consistent
>    generation, anything producing a layered PSD directly?
> 2. Is there a free route to a **rigged** model — Route B — that does not
>    require drawing? Auto-rigging from a flat image, a free rigging service, a
>    permissively licensed rig that can be re-skinned?
> 3. Is the Gemini alpha-channel limitation in §6 avoidable with a better tool
>    choice, rather than worked around with chroma keying?
>
> Concrete, currently-available tools please, with their licensing. Answers that
> require illustration skill or paid commissions do not fit the constraints.
