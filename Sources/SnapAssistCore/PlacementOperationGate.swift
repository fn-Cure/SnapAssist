import Foundation

public struct PlacementOperationGate: Sendable {
    private var activeOperationID: UUID?

    public init() {}

    public var isBusy: Bool { activeOperationID != nil }

    public mutating func begin() -> UUID? {
        guard activeOperationID == nil else { return nil }
        let operationID = UUID()
        activeOperationID = operationID
        return operationID
    }

    @discardableResult
    public mutating func finish(_ operationID: UUID) -> Bool {
        guard activeOperationID == operationID else { return false }
        activeOperationID = nil
        return true
    }

    public mutating func cancel() {
        activeOperationID = nil
    }
}
