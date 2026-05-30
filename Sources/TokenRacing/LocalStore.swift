import Foundation

final class LocalStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Token Racing", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        fileURL = supportDirectory.appendingPathComponent("state.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> AppData {
        guard let data = try? Data(contentsOf: fileURL) else {
            return .empty
        }

        do {
            return try decoder.decode(AppData.self, from: data)
        } catch {
            NSLog("Token Racing: failed to decode local state: \(error.localizedDescription)")
            return .empty
        }
    }

    func save(_ data: AppData) {
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("Token Racing: failed to save local state: \(error.localizedDescription)")
        }
    }
}
