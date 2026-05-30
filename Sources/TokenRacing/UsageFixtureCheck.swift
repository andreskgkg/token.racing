import Foundation

enum UsageFixtureCheck {
    static func run(arguments: [String]) -> Int32 {
        guard let pathIndex = arguments.firstIndex(of: "--usage-fixture"),
              arguments.indices.contains(pathIndex + 1) else {
            print("Usage: TokenRacing --usage-fixture /path/to/file [--expected-total 3175]")
            return 2
        }

        let expectedTotal: Int?
        if let expectedIndex = arguments.firstIndex(of: "--expected-total"),
           arguments.indices.contains(expectedIndex + 1) {
            expectedTotal = Int(arguments[expectedIndex + 1])
        } else {
            expectedTotal = nil
        }

        do {
            let path = arguments[pathIndex + 1]
            let parser = UsageLogParser(app: .claudeCode, sourceDescription: "Fixture")
            let events = try parser.events(since: .distantPast, atPath: path)
            let total = events.reduce(0) { $0 + $1.tokens }
            print("events=\(events.count)")
            print("total=\(total)")

            if let expectedTotal, expectedTotal != total {
                print("expected=\(expectedTotal)")
                return 1
            }

            return 0
        } catch {
            print(error.localizedDescription)
            return 1
        }
    }
}
