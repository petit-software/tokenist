import Foundation
import OSLog

private let log = Logger(subsystem: "com.tokenist.Tokenist", category: "api")

struct ClaudeAPIClient: Sendable {
    enum APIError: Error, LocalizedError {
        case unauthorized
        case http(Int, String?)
        case decoding(Error)
        case network(Error)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "Session cookie is invalid or expired."
            case .http(let code, let body):
                "HTTP \(code)\(body.map { ": \($0)" } ?? "")"
            case .decoding(let err): "Could not decode response: \(err.localizedDescription)"
            case .network(let err): err.localizedDescription
            }
        }
    }

    let sessionKey: String
    var urlSession: URLSession = .shared

    func listOrganizations() async throws -> [Organization] {
        let url = URL(string: "https://claude.ai/api/organizations")!
        return try await request(url: url)
    }

    func fetchUsage(orgId: String) async throws -> UsageResponse {
        let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage")!
        return try await request(url: url)
    }

    // MARK: - Internal

    private func request<T: Decodable>(url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: req)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "Non-HTTP response")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?.prefix(200).description
            throw APIError.http(http.statusCode, body)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFrac.date(from: raw) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Could not parse ISO8601 date: \(raw)"
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            log.error("decode failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            log.error("raw body: \(body, privacy: .public)")
            throw APIError.decoding(error)
        }
    }
}
