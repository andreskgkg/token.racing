import Foundation

struct SyncedFriend: Codable, Identifiable, Equatable {
    var id: UUID
    var handle: String
    var inviteCode: String?
    var avatarDataURL: String?
    var status: FriendRequestStatus
    var direction: FriendRequestDirection
}

struct BackendLeaderboardRow: Codable, Identifiable {
    var id: UUID
    var handle: String
    var avatarDataURL: String?
    var totalTokens: Int
    var breakdown: [String: Int]
    var isCurrentUser: Bool
    var rank: Int
}

final class SyncClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
    }

    func upsertUser(profile: UserProfile, backendURL: String) async throws -> UserProfile {
        struct Request: Codable {
            var userId: UUID
            var handle: String
            var inviteCode: String
            var avatarDataURL: String?
        }

        return try await post(
            path: "/users",
            backendURL: backendURL,
            body: Request(
                userId: profile.id,
                handle: profile.handle,
                inviteCode: profile.inviteCode,
                avatarDataURL: profile.avatarDataURL
            )
        )
    }

    func sendFriendRequest(profile: UserProfile, handleOrInviteCode: String, backendURL: String) async throws -> [SyncedFriend] {
        struct Request: Codable {
            var fromUserId: UUID
            var handleOrInviteCode: String
        }

        return try await post(
            path: "/friends/request",
            backendURL: backendURL,
            body: Request(fromUserId: profile.id, handleOrInviteCode: handleOrInviteCode)
        )
    }

    func respondToRequest(profile: UserProfile, friendId: UUID, status: FriendRequestStatus, backendURL: String) async throws -> [SyncedFriend] {
        struct Request: Codable {
            var userId: UUID
            var friendId: UUID
            var status: FriendRequestStatus
        }

        return try await post(
            path: "/friends/respond",
            backendURL: backendURL,
            body: Request(userId: profile.id, friendId: friendId, status: status)
        )
    }

    func fetchFriends(profile: UserProfile, backendURL: String) async throws -> [SyncedFriend] {
        try await get(path: "/friends/\(profile.id.uuidString)", backendURL: backendURL)
    }

    func uploadAggregates(profile: UserProfile, aggregates: [TokenAggregate], backendURL: String) async throws {
        struct AggregateDTO: Codable {
            var app: String
            var timeframe: String
            var periodStart: Date
            var tokens: Int
        }

        struct Request: Codable {
            var userId: UUID
            var handle: String
            var aggregates: [AggregateDTO]
        }

        let body = Request(
            userId: profile.id,
            handle: profile.handle,
            aggregates: aggregates.map {
                AggregateDTO(
                    app: $0.app.rawValue,
                    timeframe: $0.timeframe.rawValue,
                    periodStart: $0.periodStart,
                    tokens: $0.tokens
                )
            }
        )

        let _: EmptyResponse = try await post(path: "/usage", backendURL: backendURL, body: body)
    }

    func fetchLeaderboard(profile: UserProfile, timeframe: Timeframe, backendURL: String) async throws -> [LeaderboardRow] {
        let encodedTimeframe = timeframe.rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? timeframe.rawValue
        let rows: [BackendLeaderboardRow] = try await get(
            path: "/leaderboard/\(profile.id.uuidString)?timeframe=\(encodedTimeframe)",
            backendURL: backendURL
        )

        return rows.map { row in
            let breakdown = Dictionary(uniqueKeysWithValues: row.breakdown.compactMap { key, value -> (CodingApp, Int)? in
                guard let app = CodingApp(rawValue: key) else { return nil }
                return (app, value)
            })
            return LeaderboardRow(
                id: row.id,
                handle: row.handle,
                avatarDataURL: row.avatarDataURL,
                totalTokens: row.totalTokens,
                breakdown: breakdown,
                isCurrentUser: row.isCurrentUser,
                rank: row.rank
            )
        }
    }

    private func get<Response: Decodable>(path: String, backendURL: String) async throws -> Response {
        let request = try request(path: path, backendURL: backendURL, method: "GET")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func post<RequestBody: Encodable, Response: Decodable>(
        path: String,
        backendURL: String,
        body: RequestBody
    ) async throws -> Response {
        var request = try request(path: path, backendURL: backendURL, method: "POST")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func request(path: String, backendURL: String, method: String) throws -> URLRequest {
        guard let baseURL = URL(string: backendURL),
              let url = URL(string: path, relativeTo: baseURL) else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SyncError.server(message)
        }
    }
}

struct EmptyResponse: Codable {}

enum SyncError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid backend URL."
        case .invalidResponse:
            return "Invalid backend response."
        case .server(let message):
            return message
        }
    }
}
