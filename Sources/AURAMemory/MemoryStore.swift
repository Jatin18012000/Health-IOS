import Foundation
import GRDB
import AURACore

/// Everything she remembers, in its own database.
///
/// **Separate from `aura.sqlite` deliberately.** Health data is derived — delete
/// it and a re-import rebuilds it exactly. Memory is not: a confirmed fact or a
/// week you marked as illness exists nowhere else, and losing it loses something
/// you actually said. Different lifecycle, different backup priority, different
/// file.
///
/// It is also much smaller. Four years of health data is 34 MB; four years of
/// conversation is a few megabytes at most, which makes it cheap to back up
/// often and cheap to keep forever.
public final class MemoryStore: @unchecked Sendable {

    private let dbQueue: DatabaseQueue

    public init(url: URL) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        try Self.migrator.migrate(dbQueue)
    }

    public init(inMemory: Bool) throws {
        self.dbQueue = try DatabaseQueue()
        try Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-memory") { db in
            try db.execute(sql: """
                CREATE TABLE facts (
                    id           TEXT PRIMARY KEY,
                    text         TEXT NOT NULL,
                    kind         TEXT NOT NULL,
                    status       TEXT NOT NULL,
                    source_quote TEXT,
                    created_at   INTEGER NOT NULL,
                    confirmed_at INTEGER,
                    expires_on   TEXT
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_facts_status ON facts (status)")

            try db.execute(sql: """
                CREATE TABLE annotations (
                    id         TEXT PRIMARY KEY,
                    kind       TEXT NOT NULL,
                    start_day  TEXT NOT NULL,
                    end_day    TEXT NOT NULL,
                    note       TEXT,
                    created_at INTEGER NOT NULL
                )
                """)
            try db.execute(sql:
                "CREATE INDEX idx_annotations_range ON annotations (start_day, end_day)")

            try db.execute(sql: """
                CREATE TABLE conversations (
                    id           TEXT PRIMARY KEY,
                    started_at   INTEGER NOT NULL,
                    last_turn_at INTEGER NOT NULL,
                    summary      TEXT,
                    turn_count   INTEGER NOT NULL DEFAULT 0
                )
                """)

            try db.execute(sql: """
                CREATE TABLE turns (
                    id              TEXT PRIMARY KEY,
                    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                    speaker         TEXT NOT NULL,
                    text            TEXT NOT NULL,
                    at              INTEGER NOT NULL
                )
                """)
            try db.execute(sql:
                "CREATE INDEX idx_turns_conversation ON turns (conversation_id, at)")
        }
        return migrator
    }

    // MARK: - Facts

    /// Facts live on `day` — confirmed, and not expired.
    ///
    /// The only accessor the brief uses. Proposals and rejections exist for the
    /// review UI and nowhere else.
    public func liveFacts(on day: CalendarDay) async throws -> [Fact] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql:
                "SELECT * FROM facts WHERE status = 'confirmed' ORDER BY created_at DESC")
                .compactMap(Self.fact(from:))
                .filter { $0.isLive(on: day) }
        }
    }

    public func facts(status: Fact.Status) async throws -> [Fact] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql:
                "SELECT * FROM facts WHERE status = ? ORDER BY created_at DESC",
                arguments: [status.rawValue]).compactMap(Self.fact(from:))
        }
    }

    public func save(_ fact: Fact) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO facts (id, text, kind, status, source_quote, created_at,
                                   confirmed_at, expires_on)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    text = excluded.text, kind = excluded.kind,
                    status = excluded.status, confirmed_at = excluded.confirmed_at,
                    expires_on = excluded.expires_on
                """, arguments: [
                    fact.id.uuidString, fact.text, fact.kind.rawValue,
                    fact.status.rawValue, fact.sourceQuote,
                    Int(fact.createdAt.timeIntervalSince1970),
                    fact.confirmedAt.map { Int($0.timeIntervalSince1970) },
                    fact.expiresOn?.description])
        }
    }

    /// Propose a fact, unless one just like it already exists.
    ///
    /// Deduplicated on the text, including against rejections: saying no once
    /// should mean she stops asking, not that she asks again next week.
    @discardableResult
    public func propose(_ fact: Fact) async throws -> Bool {
        let normalised = fact.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = try await dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT text FROM facts")
        }
        guard !existing.contains(where: {
            $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalised
        }) else { return false }

        try await save(fact)
        return true
    }

    public func setStatus(_ status: Fact.Status, for id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql:
                "UPDATE facts SET status = ?, confirmed_at = ? WHERE id = ?",
                arguments: [status.rawValue,
                            status == .confirmed ? Int(Date().timeIntervalSince1970) : nil,
                            id.uuidString])
        }
    }

    /// Delete outright. Distinct from rejecting: this is "I never want this
    /// recorded", not "that inference was wrong".
    public func deleteFact(_ id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM facts WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Annotations

    public func annotations(overlapping range: DayRange) async throws -> [Annotation] {
        try await dbQueue.read { db in
            // Overlap, not containment: a travel week that starts before the
            // window and ends inside it still explains the days inside it.
            try Row.fetchAll(db, sql: """
                SELECT * FROM annotations
                WHERE start_day <= ? AND end_day >= ?
                ORDER BY start_day DESC
                """, arguments: [range.end.description, range.start.description])
                .compactMap(Self.annotation(from:))
        }
    }

    public func allAnnotations() async throws -> [Annotation] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM annotations ORDER BY start_day DESC")
                .compactMap(Self.annotation(from:))
        }
    }

    public func save(_ annotation: Annotation) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO annotations (id, kind, start_day, end_day, note, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind, start_day = excluded.start_day,
                    end_day = excluded.end_day, note = excluded.note
                """, arguments: [
                    annotation.id.uuidString, annotation.kind.rawValue,
                    annotation.range.start.description, annotation.range.end.description,
                    annotation.note, Int(annotation.createdAt.timeIntervalSince1970)])
        }
    }

    public func deleteAnnotation(_ id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM annotations WHERE id = ?",
                           arguments: [id.uuidString])
        }
    }

    // MARK: - Conversations

    public func startConversation() async throws -> StoredConversation {
        let conversation = StoredConversation()
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO conversations (id, started_at, last_turn_at, turn_count)
                VALUES (?, ?, ?, 0)
                """, arguments: [conversation.id.uuidString,
                                 Int(conversation.startedAt.timeIntervalSince1970),
                                 Int(conversation.lastTurnAt.timeIntervalSince1970)])
        }
        return conversation
    }

    public func append(_ turn: StoredTurn) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO turns (id, conversation_id, speaker, text, at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [turn.id.uuidString, turn.conversationID.uuidString,
                                 turn.speaker.rawValue, turn.text,
                                 Int(turn.at.timeIntervalSince1970)])
            try db.execute(sql: """
                UPDATE conversations
                SET turn_count = turn_count + 1, last_turn_at = ?
                WHERE id = ?
                """, arguments: [Int(turn.at.timeIntervalSince1970),
                                 turn.conversationID.uuidString])
        }
    }

    public func turns(in conversation: UUID) async throws -> [StoredTurn] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql:
                "SELECT * FROM turns WHERE conversation_id = ? ORDER BY at",
                arguments: [conversation.uuidString]).compactMap(Self.turn(from:))
        }
    }

    public func recentConversations(limit: Int = 10) async throws -> [StoredConversation] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql:
                "SELECT * FROM conversations ORDER BY last_turn_at DESC LIMIT ?",
                arguments: [limit]).compactMap(Self.conversation(from:))
        }
    }

    /// Conversations old enough to compress and not yet summarised.
    public func conversationsAwaitingSummary(
        olderThan date: Date, minimumTurns: Int = 4
    ) async throws -> [StoredConversation] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM conversations
                WHERE summary IS NULL AND last_turn_at < ? AND turn_count >= ?
                ORDER BY last_turn_at
                """, arguments: [Int(date.timeIntervalSince1970), minimumTurns])
                .compactMap(Self.conversation(from:))
        }
    }

    public func setSummary(_ summary: String, for conversation: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE conversations SET summary = ? WHERE id = ?",
                           arguments: [summary, conversation.uuidString])
            // The verbatim turns go once they are summarised. Keeping both
            // doubles the store and defeats the point; the summary is what she
            // recalls from a conversation weeks later, which is also how
            // remembering actually works.
            try db.execute(sql: "DELETE FROM turns WHERE conversation_id = ?",
                           arguments: [conversation.uuidString])
        }
    }

    // MARK: - Row mapping

    private static func fact(from row: Row) -> Fact? {
        guard let id = UUID(uuidString: row["id"]),
              let kind = Fact.Kind(rawValue: row["kind"]),
              let status = Fact.Status(rawValue: row["status"]) else { return nil }
        return Fact(
            id: id, text: row["text"], kind: kind, status: status,
            sourceQuote: row["source_quote"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            confirmedAt: (row["confirmed_at"] as Int?).map {
                Date(timeIntervalSince1970: Double($0))
            },
            expiresOn: (row["expires_on"] as String?).flatMap(CalendarDay.init))
    }

    private static func annotation(from row: Row) -> Annotation? {
        guard let id = UUID(uuidString: row["id"]),
              let kind = Annotation.Kind(rawValue: row["kind"]),
              let start = CalendarDay(row["start_day"] as String),
              let end = CalendarDay(row["end_day"] as String) else { return nil }
        return Annotation(id: id, kind: kind,
                          range: DayRange(start: start, end: end),
                          note: row["note"],
                          createdAt: Date(timeIntervalSince1970: row["created_at"]))
    }

    private static func turn(from row: Row) -> StoredTurn? {
        guard let id = UUID(uuidString: row["id"]),
              let conversationID = UUID(uuidString: row["conversation_id"]),
              let speaker = StoredTurn.Speaker(rawValue: row["speaker"]) else { return nil }
        return StoredTurn(id: id, conversationID: conversationID, speaker: speaker,
                          text: row["text"],
                          at: Date(timeIntervalSince1970: row["at"]))
    }

    private static func conversation(from row: Row) -> StoredConversation? {
        guard let id = UUID(uuidString: row["id"]) else { return nil }
        return StoredConversation(
            id: id,
            startedAt: Date(timeIntervalSince1970: row["started_at"]),
            lastTurnAt: Date(timeIntervalSince1970: row["last_turn_at"]),
            summary: row["summary"], turnCount: row["turn_count"])
    }
}
