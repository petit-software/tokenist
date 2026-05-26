import Foundation

// File-backed snapshot cache living in the App Group container so the widget
// extension can read what the main app last fetched without making its own
// network call. UserDefaults is unsuitable here because the system coalesces
// writes and may drop updates that happen close together.

enum SharedSnapshotStore {
    private static let fileName = "usage-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedDefaults.suiteName)?
            .appendingPathComponent(fileName)
    }

    static func save(_ snapshot: UsageSnapshot) {
        guard let url = fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Best-effort cache; failures are non-fatal and recoverable on the next refresh.
        }
    }

    static func load() -> UsageSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
