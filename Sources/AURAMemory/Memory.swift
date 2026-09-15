import Foundation
import AURACore

/// Something she has learned about you and you have confirmed.
///
/// The confirmation is the whole design. `docs/INTELLIGENCE.md`: *a companion
/// that quietly accumulates conclusions about you is unsettling; one that says
/// "should I remember that?" is not.* So a fact has two states, and only one of
/// them reaches her.
public struct Fact: Identifiable, Hashable, Sendable, Codable {

    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// Something ongoing — "training for a half marathon in March".
        case context
        /// A constraint or condition — "shin splints since February".
        case condition
        /// A preference about how she behaves — "don't mention weight".
        case preference
        /// Something you told her about your life that explains your data.
        case life
    }

    public enum Status: String, Sendable, Codable {
        /// Extracted from conversation, waiting for you to confirm it.
        ///
        /// Proposals are never used in a brief. An unconfirmed inference is a
        /// guess, and a guess repeated back as fact is how a companion starts
        /// being wrong about your life with total confidence.
        case proposed
        case confirmed
        /// You said no. Kept rather than deleted so the same wrong inference is
        /// not proposed again next week.
        case rejected
        /// Replaced by a newer fact, or explicitly retired.
        case retired
    }

    public let id: UUID
    public var text: String
    public var kind: Kind
    public var status: Status
    /// The turn this came from, when it was proposed rather than typed.
    public var sourceQuote: String?
    public var createdAt: Date
    public var confirmedAt: Date?
    /// Facts that stop being true on their own. A race in March is not context
    /// in June, and an expired fact quietly retires rather than misleading her.
    public var expiresOn: CalendarDay?

    public init(id: UUID = UUID(), text: String, kind: Kind,
                status: Status = .proposed, sourceQuote: String? = nil,
                createdAt: Date = Date(), confirmedAt: Date? = nil,
                expiresOn: CalendarDay? = nil) {
        self.id = id
        self.text = text
        self.kind = kind
        self.status = status
        self.sourceQuote = sourceQuote
        self.createdAt = createdAt
        self.confirmedAt = confirmedAt
        self.expiresOn = expiresOn
    }

    public func isLive(on day: CalendarDay) -> Bool {
        guard status == .confirmed else { return false }
        guard let expiresOn else { return true }
        return day <= expiresOn
    }
}

/// A labelled stretch of days — why a week looks the way it does.
///
/// Without these a two-week dip looks like decline instead of flu, and she will
/// tell you a confident, wrong story about your own life. They are the cheapest
/// possible fix for the single biggest gap in what the data can know.
public struct Annotation: Identifiable, Hashable, Sendable, Codable {

    public enum Kind: String, Sendable, Codable, CaseIterable {
        case ill, injured, travelling, stressed, resting, training, celebrating

        public var label: String {
            switch self {
            case .ill:         "Unwell"
            case .injured:     "Injured"
            case .travelling:  "Travelling"
            case .stressed:    "Stressed"
            case .resting:     "Rest period"
            case .training:    "Training block"
            case .celebrating: "Occasion"
            }
        }

        /// A hint for her tone, not a rule for the numbers.
        public var suppressesEncouragement: Bool {
            switch self {
            case .ill, .injured, .stressed: true
            default: false
            }
        }
    }

    public let id: UUID
    public var kind: Kind
    public var range: DayRange
    public var note: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), kind: Kind, range: DayRange,
                note: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.range = range
        self.note = note
        self.createdAt = createdAt
    }

    public func covers(_ day: CalendarDay) -> Bool {
        day >= range.start && day <= range.end
    }

    public var dayCount: Int {
        var count = 1
        var cursor = range.start
        while cursor < range.end {
            cursor = cursor.adding(days: 1)
            count += 1
        }
        return count
    }
}

/// One exchange, as stored.
public struct StoredTurn: Identifiable, Hashable, Sendable, Codable {
    public enum Speaker: String, Sendable, Codable { case you, aura }

    public let id: UUID
    public let conversationID: UUID
    public let speaker: Speaker
    public let text: String
    public let at: Date

    public init(id: UUID = UUID(), conversationID: UUID, speaker: Speaker,
                text: String, at: Date = Date()) {
        self.id = id
        self.conversationID = conversationID
        self.speaker = speaker
        self.text = text
        self.at = at
    }
}

/// A conversation, with a summary once it is old enough to compress.
public struct StoredConversation: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var startedAt: Date
    public var lastTurnAt: Date
    /// Nil until summarised. Recent conversations stay verbatim; older ones
    /// compress, so context stays bounded without history being lost.
    public var summary: String?
    public var turnCount: Int

    public init(id: UUID = UUID(), startedAt: Date = Date(),
                lastTurnAt: Date = Date(), summary: String? = nil,
                turnCount: Int = 0) {
        self.id = id
        self.startedAt = startedAt
        self.lastTurnAt = lastTurnAt
        self.summary = summary
        self.turnCount = turnCount
    }
}
