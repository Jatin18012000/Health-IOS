# The AURA character rig

Delivered as a Cubism 5.3 model. What is here, and how it gets onto a Mac.

```
runtime/              <- copy this folder's CONTENTS to the app's character directory
  manifest.json       which renderer and where its assets are
  live2d/
    AURA_Live2D_Final.model3.json    the entry point the SDK loads
    AURA_Live2D_Final.moc3           the rig  (moc3 version 6)
    AURA_Live2D_Final.cdi3.json      parameter display names
    AURA_Live2D_Final.1024/
      texture_00.png                 1024x1024 RGBA atlas

source/
  AURA_Live2D_Final.cmo3             the editable Cubism project
  SUPPLIER_VALIDATION_REPORT.md      what the supplier checked
```

## Install

```bash
mkdir -p ~/Library/Application\ Support/AURA/character
cp -R Resources/Characters/aura/runtime/. ~/Library/Application\ Support/AURA/character/
```

`AppContainer` reads `manifest.json` from that directory at launch;
`CharacterStageView` resolves `assetPath` relative to it, so the `live2d/`
subfolder must keep its name. The texture subdirectory must keep its name too —
`model3.json` references it by relative path.

## Two things that will bite

**The SDK must be Cubism 5.3 or newer.** This is a moc3 **version 6** file.
Older Cores refuse it with `csmReviveMocInPlace is failed. The Core unsupport
later than moc3 ver:[5]. This moc3 ver is [6]`, which does not obviously mean
"your SDK is too old".

**There is no `physics3.json`, so the hair is static.** The rig has
`ParamHairFront`, `ParamHairSide` and `ParamHairBack`, but nothing drives them —
`Live2DRenderer.tick` calls `updatePhysics` every frame and it has nothing to
act on. Fixable from the `.cmo3` without going back to the supplier; physics is
included in Cubism Editor's free tier. See `docs/CHARACTER_DELIVERY_REPORT.md`.

Keep `source/` — without the `.cmo3` you cannot adjust a weight or add physics
without commissioning the model again.
