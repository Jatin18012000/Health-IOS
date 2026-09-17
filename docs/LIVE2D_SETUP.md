# Installing the rig

What to do when the artwork comes back. Fifteen minutes if the rig is correct,
and the checks below are how you find out whether it is *before* you spend an
afternoon on integration.

## 1. Check the delivery before anything else

Open the model in **Cubism Viewer** (free) and sweep each parameter. You are
looking for four things, in this order:

**`ParamMouthOpenY` moves smoothly across its whole range.** Drag it slowly from
0 to 1 and watch. A rig built for expression presets often snaps between two
mouth shapes, which is fine for pre-recorded animation and wrong here — her
mouth is driven by a live waveform, so every value in between is used. This is
the single most likely thing to be wrong with a commission and the easiest to
miss, because it looks fine in any demo video.

**Every parameter in `CharacterManifest.required` exists**, spelled exactly:

```
ParamAngleX ParamAngleY ParamEyeBallX ParamEyeBallY
ParamEyeLOpen ParamEyeROpen ParamMouthOpenY ParamMouthForm
ParamBrowLY ParamBrowRY ParamBodyAngleZ ParamBreath
```

Names are conventional but not guaranteed. A rig using `ParamMouthOpen` without
the `Y` will simply do nothing, silently.

**Physics is present** — `.physics3.json` — and hair moves when you drag
`ParamAngleX`. The renderer does not animate hair; it moves the head and the rig
responds. No physics file means a static wig.

**You have the editable sources** (`.cmo3`, layered `.psd`). Without them you
cannot fix a weight without going back to the artist.

## 2. Get the SDK

**It must be 5.3 or newer.** The delivered rig is a moc3 **version 6** file, and
an older Core refuses it outright with `csmReviveMocInPlace is failed. The Core
unsupport later than moc3 ver:[5]. This moc3 ver is [6]` — which does not
obviously mean "your SDK is too old".

Cubism SDK for Native, from live2d.com. Free below the revenue threshold you are
comfortably under (`docs/COST.md`), but it requires an account and is not
redistributable — which is why it is not in this repository and why the bridge
below could not be compiled here.

## 3. Build the bridge

The SDK is C++ with no official Swift wrapper, so `Sources/CubismBridge` is a
small Objective-C++ target exposing only what `Live2DRenderer` calls:

```objc
@interface CubismModelHandle : NSObject
- (nullable instancetype)initWithDirectory:(NSString *)path;
- (void)setParameter:(NSString *)name value:(float)value;
- (void)updatePhysics:(float)deltaTime;
- (void)update;
- (NSArray<NSString *> *)parameterIDs;
@end
```

Five methods. Everything else the SDK offers — motions, expressions, pose files,
motion groups — is deliberately unused: she is driven parameter by parameter
from live data, not by playing canned animations, and a motion player fighting
the renderer for the same parameters is a real bug that is hard to see.

Underneath, each call maps to:

```cpp
CubismFramework::GetIdManager()->GetId(name)   // NSString -> CubismId
model->SetParameterValue(id, value)
model->LoadParameters() / SaveParameters()
physics->Evaluate(model, deltaTime)
model->Update()
```

**Expect to correct these signatures.** They are written from the published API
shape rather than compiled against the real headers.

## 4. Install

```
~/Library/Application Support/AURA/character/
  manifest.json
  live2d/
    aura.model3.json
    aura.moc3
    aura.physics3.json
    aura.2048/texture_00.png
```

```json
{
  "renderer": "live2d",
  "assetPath": "live2d",
  "parameters": ["ParamAngleX", "ParamAngleY", "..."]
}
```

List the parameters the rig actually has. `missingParameters()` compares that
against what the renderer drives, so a rig short of one is caught at install
rather than the first time she tries to speak.

## 5. Switch back if you need to

Set `"renderer": "procedural"`. The placeholder is not deleted when the rig
arrives, and being able to fall back in one line is worth more than the disk it
costs.

## What does not change

No dashboard code. No view model. Nothing in `AURAAnalytics`,
`AURAIntelligence` or `AURAVoice`. The mouth is driven by the same amplitude
stream through the same `MouthShaper`; only the thing consuming it changes.

That was the acceptance criterion for this milestone from the beginning, and it
is the reason the placeholder was built procedurally rather than as a sprite
sheet — a pose sheet would have thrown all of it away.
