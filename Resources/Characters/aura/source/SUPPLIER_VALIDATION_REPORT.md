# AURA Live2D Delivery — Validation Report

## Deliverables

- Editable Cubism project: `Editable/AURA_Live2D_Final.cmo3`
- Runtime model definition: `AURA_Live2D_Runtime/AURA_Live2D_Final.model3.json`
- Compiled model: `AURA_Live2D_Runtime/AURA_Live2D_Final.moc3`
- Display information: `AURA_Live2D_Runtime/AURA_Live2D_Final.cdi3.json`
- Texture: `AURA_Live2D_Runtime/AURA_Live2D_Final.1024/texture_00.png`

## Required parameter IDs verified in the compiled `.moc3`

- `ParamAngleX`
- `ParamAngleY`
- `ParamEyeBallX`
- `ParamEyeBallY`
- `ParamEyeLOpen`
- `ParamEyeROpen`
- `ParamMouthOpenY`
- `ParamMouthForm`
- `ParamBrowLY`
- `ParamBrowRY`
- `ParamBodyAngleZ`
- `ParamBreath`

Additional parameters are also present for Angle Z, eye smiles, brow forms, cheek, body X/Y, and hair movement.

## Runtime metadata

- Eye blink group: `ParamEyeLOpen`, `ParamEyeROpen`
- Lip-sync group: `ParamMouthOpenY`
- `model3.json` format version: 3
- Texture atlas: 1024 × 1024 RGBA PNG

## Packaging correction

The supplied `model3.json` references `AURA_Live2D_Final.1024/texture_00.png`. The uploaded texture was supplied separately at the root, so this delivery places it in the required subdirectory. No model or artwork data was modified.

## Integration entry point

Load `AURA_Live2D_Runtime/AURA_Live2D_Final.model3.json` using the Cubism SDK. Preserve the included relative directory structure when copying the runtime folder into the AURA application bundle.

## Validation boundary

File integrity, JSON references, parameter identifiers, groups, and texture decoding were validated. Final deformation quality and animation appearance still require a visual playback test with Cubism Viewer or the AURA renderer because the Cubism Core runtime is not available in this workspace.
