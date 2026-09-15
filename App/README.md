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
4. Signing & Capabilities → App Sandbox → enable **Audio Input** (M6) and
   **User Selected File** read access (so the import can read the export).

Everything below the shell stays in `Sources/` so it can be built and tested
from the command line with `swift build` / `swift test`, and so the future iOS
companion can link the same packages.

Keep this target thin: views and view models only. Anything with logic worth
testing belongs in a package.
