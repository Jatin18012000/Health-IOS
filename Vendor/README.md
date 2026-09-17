# Vendored SDKs

## `CubismSDK/` — not in this repository, and cannot be

The Live2D Cubism SDK for Native is proprietary. It needs a live2d.com account
and agreement to a licence, and it cannot be redistributed, so it is downloaded
per-machine and `.gitignore`d.

`Package.swift` **detects** it rather than requiring it. Without it, `swift build`
works exactly as before and the app draws the procedural placeholder. With it,
`CubismBridge` is built and `AURACharacter` links it. Nothing needs uncommenting.

### Get it

1. Download **Cubism SDK for Native, 5.3 or newer** from live2d.com.
   The version floor is not optional: the rig in `Resources/Characters/aura/`
   is a moc3 **version 6** file and an older Core refuses it outright.
2. Unzip it and place it so the layout is:

```
Vendor/CubismSDK/
  Core/
    include/Live2DCubismCore.h
    lib/macos/libLive2DCubismCore.a
  Framework/
    src/            CubismFramework.hpp, Model/, Physics/, Rendering/Metal/ ...
```

The downloaded folder is usually named `CubismSdkForNative-5.x.y`; rename it to
`CubismSDK` or symlink it.

3. Check it:

```bash
tools/setup_cubism.sh
```

That script exists because the failure mode otherwise is a wall of C++ header
errors that do not say "the SDK is in the wrong place".

### Licence

Free below ¥10,000,000 annual revenue — see `docs/COST.md`. The terms are the
SDK's own; nothing here grants them.
