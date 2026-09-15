import Testing
import Foundation
@testable import AURAIntelligence
@testable import AURAMemory

/// Parsing is strict because these become things she believes about you.
/// A half-parsed fact is worse than a missing one.
@Suite("Fact extraction")
struct MemoryKeeperTests {

    @Test("a well-formed line becomes a candidate")
    func wellFormed() {
        let parsed = MemoryKeeper.parse(
            "context | training for a half marathon in March | I've got a half in March")
        #expect(parsed.count == 1)
        #expect(parsed.first?.kind == .context)
        #expect(parsed.first?.text == "training for a half marathon in March")
        #expect(parsed.first?.quote == "I've got a half in March")
    }

    @Test("several lines parse independently")
    func multipleLines() {
        let parsed = MemoryKeeper.parse("""
            condition | shin splints since February | my shins have been sore
            preference | prefers not to discuss weight | don't bring up my weight
            """)
        #expect(parsed.count == 2)
        #expect(parsed.map(\.kind) == [.condition, .preference])
    }

    @Test("an unknown kind is dropped rather than guessed at")
    func unknownKind() {
        #expect(MemoryKeeper.parse("medical | they have anaemia | I feel tired").isEmpty)
    }

    @Test("a malformed line is dropped rather than salvaged")
    func malformed() {
        #expect(MemoryKeeper.parse("training for a half in March").isEmpty)
        #expect(MemoryKeeper.parse("context |").isEmpty)
        #expect(MemoryKeeper.parse("| something").isEmpty)
    }

    @Test("an overlong fact is dropped")
    func overlong() {
        // A model that ignores the length instruction is a model ignoring the
        // instructions generally — the output is not to be trusted.
        let long = String(repeating: "a", count: 200)
        #expect(MemoryKeeper.parse("context | \(long) | quote").isEmpty)
    }

    @Test("the empty answer produces nothing")
    func nothingWorthKeeping() {
        #expect(MemoryKeeper.parse("NOTHING").isEmpty)
        #expect(MemoryKeeper.parse("").isEmpty)
    }

    @Test("a missing quote is allowed, a missing fact is not")
    func optionalQuote() {
        #expect(MemoryKeeper.parse("life | moved to a new flat").count == 1)
        #expect(MemoryKeeper.parse("life |  | some quote").isEmpty)
    }
}
