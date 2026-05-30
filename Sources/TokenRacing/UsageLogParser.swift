import Foundation

struct UsageLogParser {
    let app: CodingApp
    let sourceDescription: String

    func events(since startDate: Date, atPath path: String) throws -> [TokenUsageEvent] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw UsageAdapterError.unavailable("Local usage source does not exist: \(path)")
        }

        let fileURLs: [URL]
        if isDirectory.boolValue {
            fileURLs = usageFiles(in: URL(fileURLWithPath: path))
        } else {
            fileURLs = [URL(fileURLWithPath: path)]
        }

        return fileURLs.flatMap { url in
            (try? parseFile(url, since: startDate)) ?? []
        }
    }

    private func usageFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let allowedExtensions = ["json", "jsonl", "log", "txt"]
            guard allowedExtensions.contains(url.pathExtension.lowercased()) else { return nil }

            let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues?.isRegularFile == true else { return nil }

            // Keep MVP scanning lightweight and avoid accidentally ingesting huge raw logs.
            if let size = resourceValues?.fileSize, size > 20_000_000 {
                return nil
            }
            return url
        }
    }

    private func parseFile(_ url: URL, since startDate: Date) throws -> [TokenUsageEvent] {
        let data = try Data(contentsOf: url)
        let fallbackDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let text = String(data: data, encoding: .utf8) ?? ""

        if url.pathExtension.lowercased() == "jsonl" || text.contains("\n") {
            let jsonlEvents = text
                .split(separator: "\n")
                .flatMap { line -> [TokenUsageEvent] in
                    guard let lineData = String(line).data(using: .utf8),
                          let value = try? JSONSerialization.jsonObject(with: lineData) else {
                        return []
                    }
                    return extractEvents(from: value, fallbackDate: fallbackDate, since: startDate)
                }
            if !jsonlEvents.isEmpty {
                return jsonlEvents
            }
        }

        let value = try JSONSerialization.jsonObject(with: data)
        return extractEvents(from: value, fallbackDate: fallbackDate, since: startDate)
    }

    private func extractEvents(from value: Any, fallbackDate: Date, since startDate: Date) -> [TokenUsageEvent] {
        if let dictionary = value as? [String: Any] {
            if let tokens = directTokenTotal(in: dictionary), tokens > 0 {
                let timestamp = directDate(in: dictionary) ?? fallbackDate
                guard timestamp >= startDate else { return [] }
                return [
                    TokenUsageEvent(
                        app: app,
                        timestamp: timestamp,
                        tokens: tokens,
                        sourceDescription: sourceDescription
                    )
                ]
            }

            return dictionary.values.flatMap {
                extractEvents(from: $0, fallbackDate: directDate(in: dictionary) ?? fallbackDate, since: startDate)
            }
        }

        if let array = value as? [Any] {
            return array.flatMap { extractEvents(from: $0, fallbackDate: fallbackDate, since: startDate) }
        }

        return []
    }

    private func directTokenTotal(in dictionary: [String: Any]) -> Int? {
        if let total = integerValue(dictionary["total_tokens"] ?? dictionary["totalTokens"]) {
            return total
        }

        let componentKeys = [
            "input_tokens",
            "output_tokens",
            "cache_creation_input_tokens",
            "cache_read_input_tokens",
            "prompt_tokens",
            "completion_tokens",
            "reasoning_tokens",
            "cached_tokens"
        ]

        let total = componentKeys.reduce(0) { partial, key in
            partial + (integerValue(dictionary[key]) ?? 0)
        }

        return total > 0 ? total : nil
    }

    private func integerValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private func directDate(in dictionary: [String: Any]) -> Date? {
        let candidateKeys = ["timestamp", "created_at", "createdAt", "date", "time"]
        for key in candidateKeys {
            if let date = dateValue(dictionary[key]) {
                return date
            }
        }
        return nil
    }

    private func dateValue(_ value: Any?) -> Date? {
        if let timeInterval = value as? TimeInterval {
            if timeInterval > 10_000_000_000 {
                return Date(timeIntervalSince1970: timeInterval / 1000)
            }
            return Date(timeIntervalSince1970: timeInterval)
        }

        guard let string = value as? String else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: string) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)
    }
}
