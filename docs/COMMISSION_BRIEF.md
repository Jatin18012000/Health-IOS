# Live2D commission brief

Paste-ready. Everything in the first section is what an artist needs to quote
accurately; the rest is detail for once they are engaged.

Send it with the two full-body reference images.

---

## The brief

> Hi — I'm looking for a **Live2D model, art separation and rigging**, for a
> personal desktop app (a health companion that runs on my own Mac). Not for
> VTubing or streaming.
>
> **What I have:** two full-body illustrations of the character, as flat images.
> **They are AI-generated** — I'd rather say that up front than waste your time.
> I'm happy for you to redraw or reinterpret them if that's easier or if you'd
> rather not work from AI art; the character design is what I care about, not
> those specific files.
>
> **What I need:**
>
> - Layer separation from the flat image, including painting in everything
>   currently hidden (behind the hair, behind the arms, behind the jacket)
> - Rigging in Cubism
> - Half-body is fine — she's shown from roughly the thighs up
>
> **Motion:**
>
> - Head turn on X, Y and Z
> - Eye blink, plus eye tracking (she follows the cursor)
> - **Mouth open and mouth form, rigged for real lipsync** — this is the most
>   important part for me, see below
> - Breathing
> - Body sway / lean
> - Hair and ponytail physics
>
> **Deliverable:** Cubism runtime files — `.moc3`, `.model3.json`, `.physics3.json`
> and textures — for use with the **Cubism SDK for Native**. Plus the layered
> source file.
>
> **On lipsync specifically:** her mouth is driven by live audio amplitude from
> a text-to-speech engine, not by pre-recorded animation. So `ParamMouthOpenY`
> needs a full, smooth range that reads well at every value, not just at the
> extremes. If you normally rig mouths for a fixed set of expressions, this is a
> bit different and worth flagging in your quote.
>
> **Questions:**
>
> 1. Does your price include the layer separation and painting occluded areas
>    from a flat image, or do you need a layered PSD to start from?
> 2. Rough timeline?
> 3. Are you comfortable working from (or redrawing) AI-generated reference?
>
> Happy to answer anything. Thanks!

---

## Why the questions matter

**Question 1 is the one that moves the price most.** "I already have the image"
sounds like the hard part is done, and it isn't: a flat illustration contains no
information about what is behind the hair or under the arms, and a rig needs all
of it because every one of those parts moves independently. Some artists quote
for rigging only and assume you'll supply a layered PSD. Ask, or the quotes you
get back won't be comparable.

**Question 3 saves everyone time.** Some artists won't work from AI art at all,
some charge more to redraw it properly, some don't mind. All three are
reasonable. Saying it in the first message gets you honest quotes instead of an
awkward conversation later.

## What you should receive

| File | What it is |
|---|---|
| `*.moc3` | The rig itself — the binary the runtime loads |
| `*.model3.json` | The manifest tying moc, textures, physics and parameters together |
| `*.physics3.json` | Hair and ponytail physics settings |
| `textures/*.png` | The atlas |
| `*.cmo3` / `*.psd` | **The editable sources.** Ask for these explicitly |

Get the sources. Without them you cannot fix a weight, add a parameter or
re-export at a different resolution without going back to the artist.

## Parameters to check on delivery

Open the model and confirm each of these actually moves before you accept:

| Parameter | Used for |
|---|---|
| `ParamAngleX` / `Y` / `Z` | head turn — idle motion and cursor tracking |
| `ParamEyeLOpen` / `ParamEyeROpen` | blinking |
| `ParamEyeBallX` / `Y` | gaze direction |
| `ParamBrowLY` / `ParamBrowRY` | expression, driven by mood |
| **`ParamMouthOpenY`** | **lipsync — driven by audio amplitude** |
| `ParamMouthForm` | mouth shape, smile through neutral |
| `ParamBodyAngleX` / `Y` / `Z` | body sway |
| `ParamBreath` | breathing |

`ParamMouthOpenY` is the one to test hardest. Sweep it slowly from 0 to 1 and
watch for a mouth that snaps between two states rather than moving continuously
— a rig built for expression presets often does, and it will look wrong the
moment it is driven by a live waveform.

## Budget and alternatives

A half-body model of this complexity, art separation included, typically runs a
few hundred pounds. Rigging-only, from a supplied PSD, is less.

**Free alternative:** Inochi Creator is open source with no revenue threshold at
all, and does the same job. It is a genuine art project rather than an
afternoon, but it costs nothing and you keep full control.

Either way — **start this before you start anything else.** It is the longest
lead item on the project and the only one that cannot be compressed later by
working harder. See `docs/ROADMAP.md`.
