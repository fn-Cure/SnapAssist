import Foundation

@MainActor
final class DiagnosticsStore {
    static let shared = DiagnosticsStore()

    private struct Entry {
        let date: Date
        let category: String
        let message: String
    }

    private let capacity = 200
    private var entries: [Entry] = []

    private init() {}

    func record(category: String, _ message: String) {
        entries.append(Entry(date: Date(), category: category, message: message))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    func report(header: [String]) -> String {
        let formatter = ISO8601DateFormatter()
        let body = entries.map { entry in
            "\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.message)"
        }
        return (header + ["", "Recent events:"] + body).joined(separator: "\n")
    }
}
