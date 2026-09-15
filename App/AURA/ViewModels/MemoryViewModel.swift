import Foundation
import Observation
import AURACore
import AURAMemory

@Observable
@MainActor
public final class MemoryViewModel {

    public private(set) var proposed: [Fact] = []
    public private(set) var confirmed: [Fact] = []
    public private(set) var annotations: [Annotation] = []

    public var isAddingAnnotation = false
    public var draftKind: Annotation.Kind = .ill
    public var draftStart = Date()
    public var draftEnd = Date()
    public var draftNote = ""

    private let memory: MemoryStore

    public init(memory: MemoryStore) {
        self.memory = memory
    }

    public func load() async {
        proposed = (try? await memory.facts(status: .proposed)) ?? []
        confirmed = (try? await memory.facts(status: .confirmed)) ?? []
        annotations = (try? await memory.allAnnotations()) ?? []
    }

    public func confirm(_ fact: Fact) async {
        try? await memory.setStatus(.confirmed, for: fact.id)
        await load()
    }

    /// Rejecting keeps the record — that is what stops her proposing the same
    /// wrong inference again next week.
    public func reject(_ fact: Fact) async {
        try? await memory.setStatus(.rejected, for: fact.id)
        await load()
    }

    /// Forgetting deletes outright. Distinct from rejecting: this is "I never
    /// want this recorded", not "that inference was wrong".
    public func forget(_ fact: Fact) async {
        try? await memory.deleteFact(fact.id)
        await load()
    }

    public func addAnnotation() async {
        let range = DayRange(start: CalendarDay(draftStart), end: CalendarDay(draftEnd))
        try? await memory.save(Annotation(
            kind: draftKind, range: range,
            note: draftNote.isEmpty ? nil : draftNote))
        draftNote = ""
        await load()
    }

    public func remove(_ annotation: Annotation) async {
        try? await memory.deleteAnnotation(annotation.id)
        await load()
    }
}
