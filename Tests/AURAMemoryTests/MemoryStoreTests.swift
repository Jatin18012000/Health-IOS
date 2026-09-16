import Testing
import Foundation
@testable import AURAMemory
@testable import AURACore

@Suite("Memory store")
struct MemoryStoreTests {

    private func store() throws -> MemoryStore { try MemoryStore(inMemory: true) }
    private let today = CalendarDay(year: 2026, month: 9, day: 13)

    // MARK: Facts

    @Test("a proposed fact never reaches a brief")
    func proposalsAreNotLive() async throws {
        let store = try store()
        try await store.save(Fact(text: "training for a half in March", kind: .context))

        // The whole design: an unconfirmed inference is a guess, and a guess
        // repeated back as fact is how she starts being confidently wrong
        // about your life.
        #expect(try await store.liveFacts(on: today).isEmpty)
        #expect(try await store.facts(status: .proposed).count == 1)
    }

    @Test("confirming makes a fact live")
    func confirmation() async throws {
        let store = try store()
        let fact = Fact(text: "training for a half in March", kind: .context)
        try await store.save(fact)
        try await store.setStatus(.confirmed, for: fact.id)

        let live = try await store.liveFacts(on: today)
        #expect(live.count == 1)
        #expect(live.first?.confirmedAt != nil)
    }

    @Test("an expired fact retires itself")
    func expiry() async throws {
        let store = try store()
        var fact = Fact(text: "tapering for Sunday's race", kind: .context,
                        status: .confirmed)
        fact.expiresOn = CalendarDay(year: 2026, month: 9, day: 1)
        try await store.save(fact)

        // A race in March is not context in June. Without expiry she would
        // still be talking about it a year later.
        #expect(try await store.liveFacts(on: today).isEmpty)
        #expect(try await store.liveFacts(
            on: CalendarDay(year: 2026, month: 8, day: 30)).count == 1)
    }

    @Test("saying no once means she stops asking")
    func rejectionIsRemembered() async throws {
        let store = try store()
        let fact = Fact(text: "you dislike running", kind: .preference)
        try await store.save(fact)
        try await store.setStatus(.rejected, for: fact.id)

        // Rejections are kept rather than deleted precisely so the same wrong
        // inference is not proposed again next week.
        let proposed = try await store.propose(
            Fact(text: "You dislike running", kind: .preference))
        #expect(proposed == false)
        #expect(try await store.facts(status: .proposed).isEmpty)
    }

    @Test("a duplicate proposal is not recorded twice")
    func deduplication() async throws {
        let store = try store()
        #expect(try await store.propose(Fact(text: "shin splints", kind: .condition)))
        #expect(try await store.propose(Fact(text: "  Shin Splints  ", kind: .condition)) == false)
        #expect(try await store.facts(status: .proposed).count == 1)
    }

    // MARK: Annotations

    @Test("annotations are found by overlap, not containment")
    func overlap() async throws {
        let store = try store()
        // Starts before the window, ends inside it — it still explains the days
        // inside it, so containment would be the wrong test.
        try await store.save(Annotation(
            kind: .travelling,
            range: DayRange(start: CalendarDay(year: 2026, month: 9, day: 1),
                            end: CalendarDay(year: 2026, month: 9, day: 8))))

        let window = DayRange(start: CalendarDay(year: 2026, month: 9, day: 7),
                              end: today)
        #expect(try await store.annotations(overlapping: window).count == 1)
    }

    @Test("an unrelated period is not offered as an explanation")
    func nonOverlapping() async throws {
        let store = try store()
        try await store.save(Annotation(
            kind: .ill,
            range: DayRange(start: CalendarDay(year: 2026, month: 3, day: 1),
                            end: CalendarDay(year: 2026, month: 3, day: 8))))

        // A flu last March does not explain this week, and listing it would
        // invite her to reach for it.
        let window = DayRange.lastDays(30, endingOn: today)
        #expect(try await store.annotations(overlapping: window).isEmpty)
    }

    @Test("a single-day annotation covers exactly that day")
    func singleDay() {
        let annotation = Annotation(kind: .ill, range: DayRange(start: today, end: today))
        #expect(annotation.dayCount == 1)
        #expect(annotation.covers(today))
        #expect(!annotation.covers(today.adding(days: 1)))
    }

    // MARK: Conversations

    @Test("summarising a conversation discards its verbatim turns")
    func summaryReplacesTurns() async throws {
        let store = try store()
        let conversation = try await store.startConversation()
        for i in 0..<4 {
            try await store.append(StoredTurn(
                conversationID: conversation.id,
                speaker: i.isMultiple(of: 2) ? .you : .aura,
                text: "turn \(i)"))
        }
        #expect(try await store.turns(in: conversation.id).count == 4)

        try await store.setSummary("Talked about sleep.", for: conversation.id)

        // Keeping both doubles the store and defeats the point. The summary is
        // what she recalls weeks later, which is also how remembering works.
        #expect(try await store.turns(in: conversation.id).isEmpty)
        #expect(try await store.recentConversations().first?.summary == "Talked about sleep.")
    }

    @Test("only old, substantial conversations are queued for summary")
    func summaryQueue() async throws {
        let store = try store()
        let brief = try await store.startConversation()
        try await store.append(StoredTurn(conversationID: brief.id, speaker: .you, text: "hi"))

        // A two-turn exchange has nothing to compress.
        let cutoff = Date().addingTimeInterval(60)
        #expect(try await store.conversationsAwaitingSummary(olderThan: cutoff).isEmpty)
    }
}
