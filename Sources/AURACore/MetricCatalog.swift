import Foundation

/// The registry of every metric AURA understands.
///
/// Derived from a real 4-year Apple Health export (664,515 records,
/// 2022-09-27 to 2026-09-15) rather than from guesswork -- see
/// docs/APPLE_HEALTH_EXPORT.md for the full survey that produced it.
///
/// This table and `tools/reference_pipeline.py`'s CATALOG are the same table in
/// two languages and must be changed together. `AURACoreTests` asserts they
/// have not drifted.
///
/// Adding a metric is a one-line change here. Nothing else needs to know.
public enum MetricCatalog {

    public static let all: [Metric] = [
        // -- Activity ------------------------------------------------------
        m("StepCount",              .activity, .count,        .sum,   true,  "Steps"),
        m("DistanceWalkingRunning", .activity, .kilometres,   .sum,   true,  "Walk + Run Distance"),
        m("DistanceCycling",        .activity, .kilometres,   .sum,   true,  "Cycling Distance"),
        m("FlightsClimbed",         .activity, .count,        .sum,   true,  "Flights Climbed"),
        m("ActiveEnergyBurned",     .activity, .kilocalories, .sum,   true,  "Active Energy"),
        m("BasalEnergyBurned",      .activity, .kilocalories, .sum,   true,  "Resting Energy"),
        m("AppleExerciseTime",      .activity, .minutes,      .sum,   true,  "Exercise Minutes"),
        m("AppleStandTime",         .activity, .minutes,      .sum,   true,  "Stand Minutes"),
        m("AppleStandHour",         .activity, .count,        .count, false, "Stand Hours"),
        m("PhysicalEffort",         .activity, .met,          .mean,  false, "Physical Effort"),

        // -- Heart ---------------------------------------------------------
        m("HeartRate",                .heart, .beatsPerMinute, .minMax, false, "Heart Rate"),
        m("RestingHeartRate",         .heart, .beatsPerMinute, .mean,   false, "Resting Heart Rate"),
        m("WalkingHeartRateAverage",  .heart, .beatsPerMinute, .mean,   false, "Walking Heart Rate"),
        m("HeartRateVariabilitySDNN", .heart, .milliseconds,   .mean,   false, "HRV (SDNN)"),
        m("OxygenSaturation",         .heart, .percent,        .mean,   false, "Blood Oxygen"),
        m("VO2Max",                   .heart, .vo2,            .last,   false, "Cardio Fitness"),
        m("BloodPressureSystolic",    .heart, .mmHg,           .mean,   false, "Systolic"),
        m("BloodPressureDiastolic",   .heart, .mmHg,           .mean,   false, "Diastolic"),
        m("HighHeartRateEvent",       .heart, .count,          .count,  false, "High Heart Rate Events"),

        // -- Sleep ---------------------------------------------------------
        m("SleepAnalysis",                      .sleep, .minutes,          .interval, false, "Sleep"),
        m("RespiratoryRate",                    .sleep, .breathsPerMinute, .mean,     false, "Respiratory Rate"),
        m("AppleSleepingWristTemperature",      .sleep, .celsius,          .mean,     false, "Wrist Temperature"),
        m("AppleSleepingBreathingDisturbances", .sleep, .count,            .mean,     false, "Breathing Disturbances"),

        // -- Mobility ------------------------------------------------------
        m("WalkingSpeed",                   .mobility, .kmPerHour,        .mean, false, "Walking Speed"),
        m("WalkingStepLength",              .mobility, .centimetres,      .mean, false, "Step Length"),
        m("WalkingAsymmetryPercentage",     .mobility, .percent,          .mean, false, "Walking Asymmetry"),
        m("WalkingDoubleSupportPercentage", .mobility, .percent,          .mean, false, "Double Support"),
        m("StairAscentSpeed",               .mobility, .metresPerSecond,  .mean, false, "Stair Ascent Speed"),
        m("StairDescentSpeed",              .mobility, .metresPerSecond,  .mean, false, "Stair Descent Speed"),
        m("AppleWalkingSteadiness",         .mobility, .percent,          .mean, false, "Walking Steadiness"),
        m("SixMinuteWalkTestDistance",      .mobility, .metres,           .last, false, "Six-Minute Walk"),

        // -- Environment ---------------------------------------------------
        m("HeadphoneAudioExposure",      .environment, .decibelsASPL, .mean,  false, "Headphone Audio"),
        m("EnvironmentalAudioExposure",  .environment, .decibelsASPL, .mean,  false, "Environmental Audio"),
        m("TimeInDaylight",              .environment, .minutes,      .sum,   true,  "Time in Daylight"),
        m("AudioExposureEvent",          .environment, .count,        .count, false, "Loud Environment Events"),
        m("HeadphoneAudioExposureEvent", .environment, .count,        .count, false, "Headphone Alerts"),

        // -- Body ----------------------------------------------------------
        m("BodyMass", .body, .kilograms,   .last, false, "Weight"),
        m("Height",   .body, .centimetres, .last, false, "Height"),

        // -- Mind ----------------------------------------------------------
        m("MindfulSession",   .mind, .minutes, .sum,   true,  "Mindful Minutes"),
        m("HandwashingEvent", .mind, .count,   .count, false, "Handwashing"),
    ]

    private static let index: [String: Metric] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static subscript(id: String) -> Metric? { index[id] }

    public static func inDomain(_ domain: MetricDomain) -> [Metric] {
        all.filter { $0.domain == domain }
    }

    /// Only these need multi-source deduplication before summing.
    public static var cumulative: [Metric] { all.filter(\.isCumulative) }

    private static func m(_ id: String, _ d: MetricDomain, _ u: Unit,
                          _ a: Aggregation, _ c: Bool, _ t: String) -> Metric {
        Metric(id: id, domain: d, unit: u, aggregation: a, isCumulative: c, title: t)
    }
}
