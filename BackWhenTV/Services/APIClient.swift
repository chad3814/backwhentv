import Foundation

enum APIError: LocalizedError {
    case badStatus(Int)
    case badURL

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "The guide server answered with HTTP \(code)."
        case .badURL: return "The guide server address was malformed."
        }
    }
}

struct APIClient {
    static let baseURL = URL(string: "https://www.backwhen.stream")!

    private let session: URLSession

    init(session: URLSession = APIClient.makeSession()) {
        self.session = session
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = ["User-Agent": "BackWhenTV-tvOS/1.0"]
        return URLSession(configuration: config)
    }

    func lineup() async throws -> Lineup {
        try await get("/api/lineup")
    }

    func schedules() async throws -> SchedulesResponse {
        try await get("/api/schedules?pods=1&hours=6")
    }

    func clips() async throws -> ClipManifest {
        try await get("/clips/manifest.json")
    }

    func weather() async throws -> WeatherReport {
        try await get("/api/weather")
    }

    func weatherExtra() async throws -> WeatherExtra {
        try await get("/api/weather/extra")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else {
            throw APIError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
