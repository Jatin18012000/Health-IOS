# The Apple Health export, as it actually is

A survey of a real export rather than a description of the format in the
abstract. Everything here was measured with `tools/reference_pipeline.py` and
the scan scripts against the reference file.

The previous attempt at this project (`Jatin18012000/AURA-HealthOS`,
`docs/APPLE_HEALTH.md`, ADR-0014) deferred the XML parser indefinitely because
no real export was available to validate against. This document is what closes
that gap.

## The file

An iOS "Export Health Data" archive unzips to:

```
apple_health_export/
  export.xml        293 MB   everything AURA needs
  export_cda.xml     56 MB   the same data as HL7 CDA -- ignored
  workout-routes/            one .gpx per outdoor workout
```

`export_cda.xml` is deliberately not read. It re-states the same records in a
clinical-document wrapper and adds nothing.

- HealthKit Export Version: **14**
- Reference export date: 2026-09-15, locale `en_IN`, timestamps at `+0530`

## Shape

```
<Record type="HKQuantityTypeIdentifierStepCount" sourceName="iPhone (2)"
        sourceVersion="17.2.1" device="&lt;&lt;HKDevice: 0x...&gt;, name:iPhone, ...&gt;"
        unit="count" creationDate="..." startDate="..." endDate="..." value="412"/>
```

One record per line, so a streaming parse is natural. Attribute order varies —
`device` is optional and sits between `sourceVersion` and `unit` when present,
so **positional attribute matching will fail**. Parse attributes as a map.

Category records (sleep, stand hours, events) carry a string `value` such as
`HKCategoryValueSleepAnalysisAsleepREM` and no `unit`.

`HeartRateVariabilitySDNN` records have nested
`<HeartRateVariabilityMetadataList>` children with instantaneous BPM readings.
Currently unused, but they are the reason a record can span multiple lines.

## Volume

| | |
|---|---|
| Records | **664,515** |
| Distinct metric types | 40 |
| Date range | 2022-09-27 → 2026-09-15 |
| Distinct days with data | **1,450** |
| Months | 49, **none sparse** (all >100 records) |
| Workouts | 4 |
| Distinct device descriptors | 2,175 |

Parsed at ~665k records in a couple of minutes in Python; the Swift
`XMLParser` implementation should be substantially faster.

## Sources, and why they collide

| Source | Records |
|---|---|
| iPhone (2) | 521,109 |
| Jatin's Apple Watch | 121,623 |
| FitCloudPro | 20,885 |
| iPad | 852 |
| NoiseFit | 44 |
| Health (manual) | 9 |

Note the source name contains a **non-breaking space** (`Apple\u{00a0}Watch`).
Matching on a plain `"Apple Watch"` string silently fails — `SourceResolver`
normalises whitespace before matching.

Overlap by metric:

| Metric | Days | Days with >1 source | Worst inflation |
|---|---|---|---|
| StepCount | 1,450 | 176 | **1.82x** |
| DistanceWalkingRunning | 1,450 | 154 | 1.81x |
| ActiveEnergyBurned | 1,188 | 83 | **1.89x** |

471 day/metric combinations required deduplication in total. See
`SourceResolver` for the algorithm and `VERDICT.md` §2 for why it matters.

## Units, exactly as emitted

| Metric | Emitted unit | Note |
|---|---|---|
| ActiveEnergyBurned | `Cal` | **A kilocalorie.** Same unit as `kcal`. |
| BasalEnergyBurned | `kcal` | |
| HeartRate, RestingHeartRate, WalkingHeartRateAverage | `count/min` | beats/min |
| RespiratoryRate | `count/min` | **breaths**/min — same spelling, different meaning |
| PhysicalEffort | `kcal/hr·kg` | contains U+00B7 MIDDLE DOT |
| VO2Max | `mL/min·kg` | contains U+00B7 MIDDLE DOT |
| HeartRateVariabilitySDNN | `ms` | |
| DistanceWalkingRunning, DistanceCycling | `km` | locale-dependent — do not assume |
| BodyMass | `kg` | locale-dependent |
| AppleSleepingWristTemperature | `degC` | locale-dependent |

Two traps: `Cal` ≠ calorie, and `count/min` means different things for different
metrics. A single global unit-alias table gets the second one wrong — aliasing
must be scoped per canonical unit (`Unit.acceptedSpellings`).

Distance/mass/temperature units follow the device locale, so an export from a
US-configured phone will emit `mi`, `lb` and `degF`. The importer must reject an
unrecognised unit loudly rather than assume.

## Sleep

`SleepAnalysis` category values in the reference export:

| Value | Count |
|---|---|
| InBed | 10,592 |
| Awake | 694 |
| AsleepCore | 697 |
| AsleepREM | 233 |
| AsleepDeep | 164 |
| AsleepUnspecified | 145 |

Reconstructed into **819 nights**, of which only **53 are staged**. The rest are
in-bed intervals only. These are not comparable quantities and the schema keeps
them distinguishable (`SleepNight.isStaged`).

Sessions arrive as many short overlapping intervals, not one block, so a night
is built by unioning intervals. A session is attributed to the night it *ends*:
anything ending before 18:00 belongs to the previous calendar day.

## Metric inventory

All 40 types present, by domain, with record counts:

**Activity** — BasalEnergyBurned 90,083 · DistanceWalkingRunning 71,038 ·
StepCount 67,547 · ActiveEnergyBurned 66,535 · PhysicalEffort 22,061 ·
FlightsClimbed 5,317 · AppleStandTime 3,275 · AppleStandHour 1,356 ·
DistanceCycling 1,175 · AppleExerciseTime 865

**Heart** — HeartRate 48,356 · HeartRateVariabilitySDNN 666 · RestingHeartRate 67 ·
WalkingHeartRateAverage 66 · OxygenSaturation 6 · VO2Max 2 ·
BloodPressureSystolic 2 · BloodPressureDiastolic 2 · HighHeartRateEvent 12

**Sleep** — SleepAnalysis 12,525 · RespiratoryRate 2,096 ·
AppleSleepingBreathingDisturbances 51 · AppleSleepingWristTemperature 30

**Mobility** — WalkingSpeed 66,766 · WalkingStepLength 66,765 ·
WalkingDoubleSupportPercentage 58,306 · WalkingAsymmetryPercentage 31,391 ·
StairDescentSpeed 326 · AppleWalkingSteadiness 206 · StairAscentSpeed 108 ·
SixMinuteWalkTestDistance 8

**Environment** — HeadphoneAudioExposure 44,036 · EnvironmentalAudioExposure 2,828 ·
TimeInDaylight 475 · HeadphoneAudioExposureEvent 150 · AudioExposureEvent 16

**Body** — BodyMass 3 · Height 1

**Mind** — HandwashingEvent 9 · MindfulSession 1

The long tail (VO2Max, blood pressure, body mass) is sparse enough that those
cards must show an honest empty or "last recorded N months ago" state rather
than a trend line through three points.
