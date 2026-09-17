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

        // Written to the stored properties, not through the facades below:
        // going through a setter here would persist the values we just read.
        let id = defaults.string(forKey: Key.theme) ?? Theme.cyberNeon.id
        self.storedTheme = Theme.all.first { $0.id == id } ?? .cyberNeon

        if let data = defaults.data(forKey: Key.goals),
           let decoded = try? JSONDecoder().decode(Goals.self, from: data) {
            self.storedGoals = decoded
        } else {
            self.storedGoals = .default
        }

        self.storedMorningBriefEnabled =
            defaults.object(forKey: Key.morningBrief) as? Bool ?? true
        self.storedMorningBriefHour =
            defaults.object(forKey: Key.morningBriefHour) as? Int ?? 8
        self.lastBackup = defaults.object(forKey: Key.lastBackup) as? Date
    }

    // MARK: Why these are facades rather than `didSet`
    //
    // The obvious way to write this is a stored property with
    // `didSet { defaults.set(...) }`. It is the wrong way here: `@Observable`
    // rewrites stored properties into computed ones, and a computed property
    // cannot carry a property observer. At best the combination is
    // ambiguous; at worst the observer is silently dropped and *no preference
    // ever persists* — a bug that only shows up after a relaunch, which is
    // exactly when nobody is looking for it.
    //
    // So each preference is a private stored property, which `@Observable`
    // tracks normally, behind a public computed property that persists on
    // write. Reading the facade registers access to the stored property, so
    // SwiftUI still redraws; the call sites are unchanged.
    //
    // This is the same shape as the `lazy`-inside-`@Observable` problem
    // already recorded in `AppContainer`: the macro does not leave stored
    // properties alone, and anything relying on them being stored breaks
    // quietly.

    private var storedTheme: Theme
    public var theme: Theme {
        get { storedTheme }
        set {
            storedTheme = newValue
            defaults.set(newValue.id, forKey: Key.theme)
        }
    }

    /// A preference, and only a preference.
    ///
    /// `AURAAnalytics` never reads this — percentiles and the composite score
    /// do not consult goals at all. A goal is a number someone picked; a
    /// percentile is a fact about the person, and letting the first move the
    /// second corrupts a figure meant to describe reality. Goal *progress* is
    /// carried in the `HealthBrief` so she may state it.
    private var storedGoals: Goals
    public var goals: Goals {
        get { storedGoals }
        set {
            storedGoals = newValue
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.goals)
        }
    }

    private var storedMorningBriefEnabled: Bool
    public var morningBriefEnabled: Bool {
        get { storedMorningBriefEnabled }
        set {
            storedMorningBriefEnabled = newValue
            defaults.set(newValue, forKey: Key.morningBrief)
        }
    }

    private var storedMorningBriefHour: Int
    public var morningBriefHour: Int {
        get { storedMorningBriefHour }
        set {
            storedMorningBriefHour = newValue
            defaults.set(newValue, forKey: Key.morningBriefHour)
        }
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
