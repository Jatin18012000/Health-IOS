import Foundation
import Observation
import AURACore
import AURADesign

/// The handful of things that are the user's choice rather than the app's.
///
/// `UserDefaults`, not the databases. These are preferences, not data: losing
/// them costs a re-pick, and keeping them out of the stores means a backup
/// carries your health history rather than your colour scheme.
///
/// Note what is *not* here. `AnalyticsConfig` holds the statistical tunables —
/// the 365-day baseline, the 14-reading minimum — and they are deliberately not
/// user-facing. A percentile whose window the reader can change is not a fact
/// about the person any more, and `docs/DECISIONS_PENDING.md` is where those
/// constants get argued about, on the record.
@Observable
@MainActor
public final class Preferences {

    private enum Key {
        static let theme = "aura.theme"
        static let goals = "aura.goals"
        static let morningBrief = "aura.morningBrief.enabled"
        static let morningBriefHour = "aura.morningBrief.hour"
        static let lastBackup = "aura.backup.lastWritten"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let id = defaults.string(forKey: Key.theme) ?? Theme.cyberNeon.id
        self.theme = Theme.all.first { $0.id == id } ?? .cyberNeon

        if let data = defaults.data(forKey: Key.goals),
           let decoded = try? JSONDecoder().decode(Goals.self, from: data) {
            self.goals = decoded
        } else {
            self.goals = .default
        }

        self.morningBriefEnabled = defaults.object(forKey: Key.morningBrief) as? Bool ?? true
        self.morningBriefHour = defaults.object(forKey: Key.morningBriefHour) as? Int ?? 8
        self.lastBackup = defaults.object(forKey: Key.lastBackup) as? Date
    }

    public var theme: Theme {
        didSet { defaults.set(theme.id, forKey: Key.theme) }
    }

    /// A preference, and only a preference.
    ///
    /// `AURAAnalytics` never reads this — percentiles and the composite score
    /// do not consult goals at all. A goal is a number someone picked; a
    /// percentile is a fact about the person, and letting the first move the
    /// second corrupts a figure meant to describe reality. Goal *progress* is
    /// carried in the `HealthBrief` so she may state it.
    public var goals: Goals {
        didSet {
            guard let data = try? JSONEncoder().encode(goals) else { return }
            defaults.set(data, forKey: Key.goals)
        }
    }

    public var morningBriefEnabled: Bool {
        didSet { defaults.set(morningBriefEnabled, forKey: Key.morningBrief) }
    }

    public var morningBriefHour: Int {
        didSet { defaults.set(morningBriefHour, forKey: Key.morningBriefHour) }
    }

    /// Shown in Settings so "I have a backup" can be checked rather than
    /// believed. Only the date — never the passphrase, which is not stored
    /// anywhere and cannot be recovered.
    public private(set) var lastBackup: Date?

    public func recordBackup(at date: Date = Date()) {
        lastBackup = date
        defaults.set(date, forKey: Key.lastBackup)
    }
}
