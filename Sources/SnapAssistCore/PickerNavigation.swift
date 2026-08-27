import Foundation

public struct PickerNavigation: Equatable, Sendable {
    public private(set) var zoneIDs: [Int]
    public private(set) var candidateIDs: [String]
    private var zoneIndex = 0
    private var candidateIndex = 0

    public init(zoneIDs: [Int], candidateIDs: [String]) {
        self.zoneIDs = zoneIDs
        self.candidateIDs = candidateIDs
    }

    public var activeZoneID: Int? {
        zoneIDs.indices.contains(zoneIndex) ? zoneIDs[zoneIndex] : nil
    }

    public var selectedCandidateID: String? {
        candidateIDs.indices.contains(candidateIndex) ? candidateIDs[candidateIndex] : nil
    }

    public mutating func moveZone(by delta: Int) {
        zoneIndex = wrapped(zoneIndex + delta, count: zoneIDs.count)
    }

    public mutating func moveCandidate(by delta: Int) {
        candidateIndex = wrapped(candidateIndex + delta, count: candidateIDs.count)
    }

    public mutating func removeCandidate(_ id: String) {
        candidateIDs.removeAll { $0 == id }
        if candidateIndex >= candidateIDs.count {
            candidateIndex = max(0, candidateIDs.count - 1)
        }
    }

    private func wrapped(_ value: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (value % count + count) % count
    }
}

