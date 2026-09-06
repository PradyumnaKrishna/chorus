import Foundation

/// Wait for a stable selection and emit it once. Clearing or changing selection rearms reading.
struct SelectionGate {
    struct Snapshot: Equatable, Sendable {
        let source: String
        let text: String
    }
    private var candidate: Snapshot?
    private var changedAt: TimeInterval = 0
    private var delivered: Snapshot?

    mutating func observe(_ snapshot: Snapshot?, at time: TimeInterval, interacting: Bool) -> String? {
        guard let snapshot, !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              snapshot.text.utf8.count <= 65_536 else {
            self = SelectionGate()
            return nil
        }
        if candidate != snapshot || interacting {
            candidate = snapshot
            changedAt = time
            if delivered != snapshot { delivered = nil }
            return nil
        }
        guard delivered != snapshot, time - changedAt >= 0.6 else { return nil }
        delivered = snapshot
        return snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
