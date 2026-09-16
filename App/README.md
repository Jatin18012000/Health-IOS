# The app target

The app shell is an Xcode target rather than an SPM executable, because a real
`.app` needs a bundle, an Info.plist, entitlements (microphone, and later
network for a local Ollama) and code signing — none of which SwiftUI gets from
`swift build` alone.

One-time setup, once you're on the Mac:

1. Xcode → New Project → macOS → App, named `AURA`, at `App/AURA/`.
2. File → Add Package Dependencies → Add Local → choose the repository root.
3. Link `AURACore`, `AURAStore`, `AURAAnalytics`, `AURAIntelligence`,
   `AURAVoice`, `AURACharacter`, `AURADesign`.
4. Signing & Capabilities → App Sandbox → enable **Audio Input** and
   **User Selected File** read access (so the import can read the export).
5. Add **`NSMicrophoneUsageDescription`** to Info.plist. Without it the app
   does not prompt for the microphone — it crashes the moment the audio engine
   starts, which looks like a bug in the talk button rather than a missing key.
   Something like: *"AURA transcribes what you say on this device. No audio
   leaves your Mac."*

Everything below the shell stays in `Sources/` so it can be built and tested
from the command line with `swift build` / `swift test`, and so the future iOS
companion can link the same packages.

Keep this target thin: views and view models only. Anything with logic worth
testing belongs in a package.
