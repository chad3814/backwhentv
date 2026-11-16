import Foundation
import OSLog

struct MetadataLookup: Hashable, Codable {
    enum Category: String, Codable {
        case tv
        case movies
    }

    let category: Category
    let name: String

    var key: String {
        "\(category.rawValue)|\(name.lowercased())"
    }
}

struct MetadataInfo: Equatable {
    let overview: String
    let title: String?
    let year: Int?
    let kind: String?
    let provider: String?
}

struct MetadataLookupBatchResponse: Decodable {
    let results: [MetadataLookupResult]
}

struct MetadataLookupResult: Decodable {
    let lookupId: String?
    let state: String?
    let partial: Bool?
    let cached: Bool?
    let confidence: Double?
    let refusal: String?
    let media: MetadataMedia?
    let status: Int?

    var isPending: Bool {
        status == 202 || state == "pending" || partial == true
    }

    /// Only accept an overview from a confident answer. Unresolved lookups can
    /// still carry a plausible media candidate, but zero-confidence candidates
    /// are often the wrong series.
    var info: MetadataInfo? {
        guard refusal == nil,
              let media,
              let overview = media.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !overview.isEmpty
        else { return nil }

        let accepted: Bool
        switch state {
        case "resolved":
            accepted = true
        case "unresolved":
            accepted = (confidence ?? 0) >= 0.4
        default:
            accepted = false
        }

        guard accepted else { return nil }
        return MetadataInfo(
            overview: overview,
            title: media.title,
            year: media.year,
            kind: media.kind,
            provider: media.provider
        )
    }
}

struct MetadataMedia: Decodable {
    let kind: String?
    let title: String?
    let year: Int?
    let provider: String?
    let overview: String?
}

enum OpenMetadataError: Error, Equatable {
    case http(Int)
    case rateLimited(seconds: TimeInterval)
    case badResponse
}

struct OpenMetadataClient {
    private static let logger = Logger(subsystem: "stream.backwhen.tv", category: "metadata")
    private static let baseURL = URL(string: "https://openmetadata.nexus")!

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = OpenMetadataClient.makeSession()) {
        self.apiKey = apiKey
        self.session = session
    }

    /// The key comes from the ignored Config/Local.xcconfig via Info.plist.
    /// An environment variable is also honoured for tests and local overrides.
    static func live(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) -> OpenMetadataClient? {
        if arguments.contains("-disableMetadata") {
            logger.debug("metadata disabled by launch argument")
            return nil
        }

        if let environmentKey = ProcessInfo.processInfo.environment["OPEN_METADATA_API_KEY"] {
            let key = environmentKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                logger.debug("metadata enabled from environment")
                return OpenMetadataClient(apiKey: key)
            }
        }

        guard let raw = bundle.object(forInfoDictionaryKey: "OpenMetadataAPIKey") as? String else {
            logger.debug("metadata disabled: no key in Info.plist")
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            logger.debug("metadata disabled: empty key")
            return nil
        }
        logger.debug("metadata enabled from Info.plist")
        return OpenMetadataClient(apiKey: key)
    }

    func lookup(_ items: [MetadataLookup]) async throws -> [MetadataLookupResult] {
        guard !items.isEmpty else { return [] }
        guard items.count <= 100 else { throw OpenMetadataError.badResponse }

        let request = try Self.makeLookupRequest(items: items, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenMetadataError.badResponse }

        switch http.statusCode {
        case 200:
            let batch = try JSONDecoder().decode(MetadataLookupBatchResponse.self, from: data)
            Self.logger.debug("metadata batch: \(batch.results.count) results")
            return batch.results
        case 429:
            let delay = Self.retryAfter(from: http)
            Self.logger.debug("metadata rate limited; retry after \(Int(delay))s")
            throw OpenMetadataError.rateLimited(seconds: delay)
        default:
            Self.logger.debug("metadata lookup failed: HTTP \(http.statusCode)")
            throw OpenMetadataError.http(http.statusCode)
        }
    }

    func poll(lookupID: String) async throws -> MetadataLookupResult? {
        var request = URLRequest(url: Self.lookupURL.appendingPathComponent(lookupID))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BackWhenTV-tvOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenMetadataError.badResponse }

        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(MetadataLookupResult.self, from: data)
        case 404:
            return nil
        case 429:
            throw OpenMetadataError.rateLimited(seconds: Self.retryAfter(from: http))
        default:
            throw OpenMetadataError.http(http.statusCode)
        }
    }

    static func makeLookupRequest(items: [MetadataLookup], apiKey: String) throws -> URLRequest {
        let payload = BatchPayload(items: items.map {
            BatchPayload.Item(category: $0.category.rawValue, name: $0.name)
        })
        let body = try JSONEncoder().encode(payload)

        var request = URLRequest(url: lookupURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BackWhenTV-tvOS/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        return request
    }

    private static var lookupURL: URL {
        baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("lookup")
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw)
        else { return 30 }
        return max(1, seconds)
    }

    private struct BatchPayload: Encodable {
        struct Item: Encodable {
            let category: String
            let name: String
        }

        let items: [Item]
    }
}
