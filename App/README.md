# The app target

The app shell is an Xcode target rather than an SPM executable, because a real
`.app` needs a bundle, an Info.plist, entitlements (microphone, and later
network for a local Ollama) and code signing — none of which SwiftUI gets from
`swift build` alone.

One-time setup, once you're on the Mac:

1. Xcode → New Project → macOS → App, named `AURA`, at `App/AURA/`.
2. File → Add Package Dependencies → Add Local → choose the repository root.
3. Link `AURACore`, `AURAStore`, `AURAIngest`, `AURAAnalytics`,
   `AURAIntelligence`, `AURAMemory`, `AURAReport`, `AURASync`, `AURAVoice`,
   `AURACharacter`, `AURADesign` — every package except `AURAHealthKit`,
   which is the phone's. The shell reaches all of them now that Settings
   carries the report, the backup and phone sync.
4. Signing & Capabilities → App Sandbox → enable **Audio Input** and
   **User Selected File** read access. The import screen needs the latter for
   both the file panel and the drop target; without it a dropped folder reads
   as empty rather than as denied, which looks like a broken importer.
5. Sandbox also needs **Incoming Connections (Server)** and **Outgoing
   Connections (Client)** for phone sync, plus
   **`NSLocalNetworkUsageDescription`** and an `NSBonjourServices` entry of
   `_aura-sync._tcp` in Info.plist. Without them the listener starts and no
   phone ever finds it, with no error on either side. Skip all of this if you
   are not using the companion — see `App/AURACompanion/README.md`.
6. Link **`CubismBridge`** too, but only once `Vendor/CubismSDK` exists —
   see `Vendor/README.md` and run `tools/setup_cubism.sh` first. Without the
   SDK the target does not exist and the app draws the procedural placeholder,
   which is the normal state.
7. Add **`NSMicrophoneUsageDescription`** to Info.plist. Without it the app
   does not prompt for the microphone — it crashes the moment the audio engine
   starts, which looks like a bug in the talk button rather than a missing key.
   Something like: *"AURA transcribes what you say on this device. No audio
   leaves your Mac."*

Everything below the shell stays in `Sources/` so it can be built and tested
from the command line with `swift build` / `swift test`, and so the future iOS
companion can link the same packages.

Keep this target thin: views and view models only. Anything with logic worth
testing belongs in a package.

## What lives where at runtime

Everything is under `~/Library/Application Support/AURA/`:

| Path | What |
|---|---|
| `aura.sqlite` | the health data, plus its `-wal` and `-shm` sidecars |
| `memory.sqlite` | facts, annotations and conversation transcripts |
| `voice/` | Kokoro weights, if installed; absent means the system voice |
| `character/` | `manifest.json` and a rig, if there is one |
| `restore-pending/` | a restored backup waiting for the next launch |

`restore-pending/` is the one that needs explaining. Both databases are open
with WAL journaling while the app runs, and writing over `aura.sqlite`
underneath an open connection corrupts it *silently* — it opens fine afterwards
and is simply wrong. So a restore stages the files here and `AppContainer.open()`
moves them into place before it opens anything, deleting the old `-wal` and
`-shm` as it goes. Leaving those behind would let SQLite replay the previous
write-ahead log over the restored database, which is the same corruption by a
longer route.
