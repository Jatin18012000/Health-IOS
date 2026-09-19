# Rig delivery — acceptance report

Checked against the criteria in `docs/LIVE2D_SETUP.md` §1 and against
`CharacterManifest.required`. Every claim below was verified against the files
themselves, not taken from the supplier's own validation report.

**Verdict: accept.** The rig is real, complete on the parameters that matter,
and correctly packaged. Three things are missing or unverifiable, one of which
is visible on screen (static hair) and one of which blocks loading entirely
until the SDK is in place.

---

## What was verified

| Check | Result |
|---|---|
| `.moc3` is a real rig, not a stub | ✅ `MOC3` magic, 29,504 bytes, 27 parameter IDs embedded in the binary |
| All 12 parameters in `CharacterManifest.required` | ✅ present — cross-checked against the Swift source, not retyped |
| `model3.json` references resolve | ✅ moc, texture and display-info paths all exist on disk |
| Texture decodes | ✅ 1024×1024, RGBA, 8-bit |
| Eye-blink and lip-sync groups declared | ✅ `ParamEyeLOpen`/`ParamEyeROpen`, `ParamMouthOpenY` |
| Editable source supplied | ✅ `.cmo3`, 898 KB |
| Free-tier parameter ceiling (30) | ✅ 27 used |

The supplier's `VALIDATION_REPORT.md` is accurate as far as it goes, and honest
about its own boundary — it says plainly that deformation quality was not
checked because no Cubism Core was available to it. That is the right thing to
have said.

The rig also carries 15 parameters beyond the 12 required — `ParamAngleZ`, eye
smiles, brow X/angle/form, `ParamCheek`, `ParamBodyAngleX/Y` and the three hair
parameters. Nothing drives them today. They cost nothing and widen what
`MoodResolver` could express later.

---

## ~~Missing #1~~ — RESOLVED: physics added 17 September 2026

A `physics3.json` was written and `model3.json` now references it. Three
settings — front, side and back hair — each driven by `ParamAngleX`/`ParamAngleZ`
and `ParamBodyAngleX`/`ParamBodyAngleZ`, each a two-vertex pendulum whose length
and delay scale with the weight of the hair mass it moves. Verified by
`tools/check_character.py`, which now runs in CI.

**The values are untuned.** They are conventional starting points, not measured
against this rig's hair geometry, because tuning physics is a visual task and no
Cubism Core is available here. Expect to adjust `Scale` and the tip vertex's
`Delay` and `Acceleration` in Cubism Editor once you can see her move. If the
hair swings too far, lower `Scale`; if it feels sluggish, lower `Delay`.

The original finding, kept for the record:

### The problem as found

`model3.json`'s `FileReferences` contains `Moc`, `Textures` and `DisplayInfo`
and **no `Physics` key**. No physics file is in the delivery.

The rig defines `ParamHairFront`, `ParamHairSide` and `ParamHairBack` — the
standard physics *output* parameters — so it was built expecting physics.
Nothing sets them. `Live2DRenderer.tick` calls `model.updatePhysics(Float(dt))`
on every frame and it has nothing to act on.

`docs/LIVE2D_SETUP.md` puts it bluntly: *no physics file means a static wig*.
Her head will turn and the hair will turn with it as one rigid piece. It is the
kind of thing that reads as "cheap" without the viewer being able to say why.

**Fix:** open `source/AURA_Live2D_Final.cmo3` in Cubism Editor, configure
physics groups against the three hair parameters, then File → Export Embedded
File → Export Physics Settings. Physics is **included in the free tier**, so
this costs nothing but an evening. It does not require going back to the
supplier.

## ~~Missing #2~~ — PARTIALLY RESOLVED: the target exists, unbuilt

`Sources/CubismBridge/` now holds a pure-Objective-C header and an Objective-C++
implementation wrapping `CubismUserModel`, and `Live2DStageView` has a real
`MTKViewDelegate` render loop instead of an empty `updateNSView`.

`Package.swift` **detects** the SDK rather than requiring it: `swift build`
behaves exactly as before on a machine without it, and starts compiling the
bridge the moment `Vendor/CubismSDK/Core/include/Live2DCubismCore.h` appears.
Declaring the targets unconditionally would have turned a working build into a
broken one for anyone without a proprietary download, CI included.

**None of it has been compiled.** There is no Swift toolchain and no Cubism SDK
in the environment it was written in. The call shapes were read from Live2D's
published Framework headers rather than recalled — `CubismUserModel`,
`CubismModelSettingJson`, `CubismModel`, `CubismRenderer_Metal` — but reading a
header is not compiling against one. Expect real errors on the first build. The
likeliest:

- `MTKViewDelegate` is not `@MainActor`, and Swift 6 strict concurrency will
  probably object to the `@MainActor` `Coordinator` conforming to it.
- The `exclude:` list for the Framework's non-Metal renderers is written from
  the SDK's usual layout and may not match 5.3 exactly.
- Linking a vendored `.a` uses `unsafeFlags`, which SwiftPM permits only in a
  root package. Fine today; it is what breaks if AURA ever becomes a dependency.

Still to do, in order: `tools/setup_cubism.sh` to confirm the layout, then
`swift build`, then work the errors.

The original finding, kept for the record:

### The problem as found

This is the real blocker, and it predates this delivery.

`Live2DRenderer.swift` is entirely inside `#if canImport(CubismBridge)`.
That module has never existed — there are no references to it in
`Package.swift`. So today the rig cannot be loaded by anything, and
`CharacterStageView` will correctly draw the procedural placeholder with the
message *"this build has no Cubism SDK linked"*.

Outstanding work, none of it done:

1. Download **Cubism SDK for Native 5.3 or newer** (see #3).
2. Add a `CubismBridge` target wrapping the C++ Core in Objective-C++, exposing
   the `CubismModelHandle` interface `Live2DRenderer` already calls —
   `setParameter`, `update`, `updatePhysics`.
3. Implement the Metal render loop. `Live2DStageView.makeNSView` creates an
   `MTKView` and `updateNSView` is **empty**; nothing currently draws.
4. Verify the call signatures. They were written from the published API shape
   and have never been compiled — the file says so itself.

## Missing #3 — the SDK must be 5.3+, or it will not load at all

The `.moc3` is **version 6**, which is a Cubism 5.3 export. Cubism Cores older
than 5.3 refuse it outright:

```
csmReviveMocInPlace is failed.
The Core unsupport later than moc3 ver:[5]. This moc3 ver is [6].
```

Worth knowing in advance, because that message does not obviously mean "your SDK
is too old", and downloading whichever SDK a search result offers first is an
easy way to lose an afternoon.

## ~~Cannot be verified here~~ — CHECKED 19 September 2026: the mouth does not move at all

`docs/LIVE2D_SETUP.md` called this *the single most likely thing to be wrong
with a commission and the easiest to miss, because it looks fine in any demo
video*, and anticipated one specific failure — a rig built for expression
presets snapping between two mouth shapes instead of interpolating. The real
finding is more fundamental than that.

**`ParamMouthOpenY` was stepped from 0.00 to 1.00 in 21 steps of 0.05, each one
screenshotted, in Cubism Editor (free mode) against the source
`AURA_Live2D_Final.cmo3`** — the standalone Cubism Viewer has no manual
parameter-scrubbing panel, so the source project was opened in the full editor
instead; it should match the exported `.moc3` since the latter is built from
it, though this was not confirmed byte-for-byte against the shipped runtime
file.

**The mouth mesh is visually identical at 0.00 and at 1.00.** There is no snap
between two shapes because there is effectively only one shape shown across the
entire range — the lips read as fully closed at every value tested.
`ParamMouthForm` (smile/frown) shows the same non-response at its extremes.

This is not a rendering or methodology problem: `ParamEyeLOpen` set to 0.0 in
the same file closes the eye correctly and dramatically, so parameter-driven
deformation works in general in this rig. The defect is specific to the mouth
mesh's keyforms — whoever rigged this either never sculpted a real "open"
shape into the `ParamMouthOpenY = 1.0` keyform, or the sculpt didn't get saved
into it before export.

**Practical consequence.** `AudioPlayback.rms` drives this parameter from live
speech amplitude continuously. With the mouth mesh as delivered, that will not
produce a lip-sync glitch — it will produce a character whose mouth never
visibly opens while she talks, which reads as far more broken than an
interpolation snap would have. This blocks real lip-sync entirely, not just
its smoothness, and needs the mouth mesh re-sculpted at the open keyform —
back to whoever authored the rig, the same way the missing physics did, since
it is an art-authoring task rather than a code one.

---

## Not missing, despite being absent

Recorded so they do not get chased:

- **No `.motion3.json`.** Correct. All motion is parameter-driven from Swift —
  breathing, blinking and gaze are computed in `Live2DRenderer.tick`. Canned
  animation clips would fight it.
- **No `.pose3.json`.** Correct. Nothing in the app switches part visibility.
- **No layered `.psd`.** The `.cmo3` embeds the artwork, so the rig stays
  editable. A PSD would only matter for re-drawing the art itself.

## Minor

The texture is a single 1024×1024 atlas and the part names suggest a full
figure (`face`, `neck`, `topwear`, `legwear`, `handwear`, `headwear`, `ears`,
`earwear`, `eyebrow`, `eyelash`, `eyewhite`, `irides`, `mouth`, `nose`). Her
face therefore occupies a modest fraction of a 1024 atlas, and she renders in a
~520 pt column that is 1040 px on a Retina display. Faces may read soft. Judge
it on screen rather than pre-emptively; re-exporting the atlas at 2048 from the
`.cmo3` is cheap if it does.

---

## What to do next, in order

1. ~~**Cubism Viewer check** on `ParamMouthOpenY`~~ — done; failed. The mouth
   mesh needs re-sculpting at the open keyform before anything downstream is
   worth building on top of it. This is now the highest-priority open item.
2. **Add physics** from the `.cmo3` — free, one evening, fixes the static hair.
3. **Download Cubism SDK for Native 5.3+**.
4. **Build the `CubismBridge` target and the Metal render loop** — the long pole.

Step 1 was worth doing before 3 and 4, and it paid off: it is far better to know
the mouth needs a re-rig before the bridge exists than after.
