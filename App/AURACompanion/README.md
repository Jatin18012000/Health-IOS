# The iOS companion

HealthKit does not exist on macOS, so the Mac's only route in is a manual
export. On a phone the data is already there. This app reads what is new and
hands it to the Mac over the local network.

It shows no figures and computes nothing. The Mac holds the store and all the
arithmetic lives in `AURAAnalytics`; a second place that aggregated would be a
second place to get the multi-source deduplication subtly wrong, and
`CLAUDE.md` makes that deduplication an invariant because getting it wrong
inflates real days by up to 1.9×.

## Setup

1. Xcode → New Project → iOS → App, named `AURACompanion`, at
   `App/AURACompanion/`.
2. Add Package Dependencies → Add Local → the repository root.
3. Link `AURACore`, `AURAHealthKit`, `AURASync`, `AURADesign`.
4. Signing & Capabilities → **+ HealthKit**. Add **Background Delivery** only
   if you later want unattended sync; the app works without it.
5. Info.plist needs **`NSHealthShareUsageDescription`**. Without it the app
   crashes the moment it asks for authorisation, which looks like a bug in the
   sync button. Something like: *"AURA reads your Health data on this device
   and sends it to your own Mac over your local network. It goes nowhere else."*
   `NSHealthUpdateUsageDescription` is **not** needed — this app never writes.
6. Local Network usage: **`NSLocalNetworkUsageDescription`** and a
   `NSBonjourServices` entry of `_aura-sync._tcp`. Missing either means Bonjour
   discovery silently finds nothing.

## The cost problem, stated plainly

**This is the one part of AURA that is not free.** `docs/COST.md` commits to
the project costing nothing, and everything else honours that. An app installed
with a free Apple ID expires after **seven days** and must be re-signed from
Xcode. Keeping it on the phone properly needs an Apple Developer account at
**$99/year**.

That was known from the start — `VERDICT.md` §3 says so — but it is worth
repeating next to the code, because the trade is real: $99/year buys automatic
sync, and the alternative is re-exporting by hand, which is free and takes
about two minutes a month. Recorded as `docs/DECISIONS_PENDING.md` §12.

## How pairing works

The Mac shows six digits; you type them into the phone. Both sides derive the
same pre-shared key from that code and the connection is TLS-PSK — a device
that does not have the code cannot read or inject anything, even on a hostile
network. No certificates, no accounts, no trust-on-first-use.

The code is stored in the **keychain**, not `UserDefaults`, because a
preferences plist travels in an unencrypted device backup and this code is the
only thing standing between a health database and anyone on the same Wi-Fi.

The Mac only listens while AURA is open. A health companion that kept a
background listener alive so a phone could reach it is a different and less
welcome product.

## What it deliberately does not handle

**Deletions.** `HKAnchoredObjectQuery` reports deleted objects and this app
discards them. `SQLiteHealthStore` is append-only by design, so a sample
removed on the phone stays in the Mac's history. Worth knowing before you go
looking for why a corrected reading is still there.

**Verification of the percentage scale.** `HKUnit.percent()` is a fraction —
blood oxygen arrives as 0.97, not 97 — and `HealthKitUnits` stores it as-is on
the reasoning that Apple's own exporter writes canonical HealthKit values. That
reasoning is not verified: the reference export held six `OxygenSaturation`
records in four years and the edge-case fixture has none, so nothing in this
repository pins the scale. **Check it on the first real sync** by importing an
XML export of the same day and comparing. See `docs/DECISIONS_PENDING.md` §11.
