import Foundation

// MARK: - Lineup

struct Lineup: Decodable {
    let version: Int?
    let anchor: Double?
    let channels: [Channel]
}

struct Channel: Decodable, Identifiable, Hashable {
    let id: String
    let num: Int
    let name: String
    let kind: String
    let blurb: String?
    let cat: String?
    let pluto: String?
    let headline: String?

    var isWeather: Bool { kind == "weather" }
}

// MARK: - Schedules

struct SchedulesResponse: Decodable {
    let built: Double?
    let anchor: Double
    let version: String?
    let genTS: Double?
    let validUntil: Double?
    let schedules: [String: ChannelSchedule]

    enum CodingKeys: String, CodingKey {
        case built, anchor, version, schedules
        case genTS = "gen_ts"
        case validUntil = "valid_until"
    }
}

struct ChannelSchedule: Decodable {
    let id: String
    let anchor: Double?
    let items: [ScheduleItem]
}

struct ScheduleItem: Decodable, Hashable {
    let t: String
    let u: String
    let f: String?
    let d: Double
    let a: Int?
    let h: Double?
    let preStitched: Bool?

    enum CodingKeys: String, CodingKey {
        case t, u, f, d, a, h
        case preStitched = "pre_stitched"
    }

    var isAd: Bool { a == 1 }
    var url: URL? { URL(string: u) }
    var fallbackURL: URL? { f.flatMap(URL.init(string:)) }
}

// MARK: - Commercial break clips

struct ClipManifest: Decodable {
    let version: Double?
    let clips: [Clip]
}

struct Clip: Decodable, Hashable, Identifiable {
    let id: String
    let type: String
    let dur: Double
    let file: String

    var url: URL {
        APIClient.baseURL.appendingPathComponent("clips").appendingPathComponent(file)
    }
}

// MARK: - Weather

struct WeatherReport: Decodable {
    struct Now: Decodable {
        let tempF: Double
        let text: String
        let windMph: Double?
        let windDir: String?
        let humidity: Double?
        let pressureIn: Double?
        let visibilityMi: Double?
        let station: String?
    }

    struct Period: Decodable, Identifiable {
        let name: String
        let tempF: Double?
        let day: Bool?
        let short: String?
        let detail: String?

        var id: String { name }
    }

    let city: String
    let state: String
    let tz: String?
    let updated: String?
    let now: Now
    let periods: [Period]
}

struct WeatherExtra: Decodable {
    struct Radar: Decodable {
        let station: String?
        let loop: String?
        let still: String?
    }

    struct City: Decodable, Identifiable {
        let name: String
        let text: String?
        let tempF: Double?
        let hi: Double?
        let lo: Double?

        var id: String { name }
    }

    struct Alert: Decodable, Identifiable {
        let event: String?
        let headline: String?

        var id: String { (event ?? "") + (headline ?? "") }
    }

    struct Briefing: Decodable {
        let office: String?
        let issued: String?
        let title: String?
        let text: String?
    }

    let radar: Radar?
    let cities: [City]?
    let alerts: [Alert]?
    let briefing: Briefing?
}

// MARK: - Derived guide data

struct Slot: Equatable {
    let index: Int
    let item: ScheduleItem
    let offset: Double
    let start: Date

    var remaining: Double { max(0, item.d - offset) }
}

struct ProgramInfo: Equatable {
    let title: String
    let next: String?
    let isAd: Bool
}
