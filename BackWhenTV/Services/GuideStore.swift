import Foundation
import Observation

/// Loads the lineup, the rolling six-hour schedules and the commercial clips,
/// and answers "what is on right now?" for the guide and the player.
@MainActor
@Observable
final class GuideStore {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var channels: [Channel] = []
    private(set) var schedules: [String: ChannelSchedule] = [:]
    private(set) var clips: [Clip] = []
    private(set) var state: LoadState = .loading
    private(set) var weather: WeatherReport?
    private(set) var weatherExtra: WeatherExtra?
    private(set) var anchor: Double = 0
    private(set) var lastScheduleRefresh: Date?

    /// Ticks every few seconds so the guide's "now playing" column stays current.
    private(set) var now = Date()

    var tunedChannelID: String? {
        didSet { UserDefaults.standard.set(tunedChannelID, forKey: Self.tunedKey) }
    }

    private static let tunedKey = "bw.tunedChannel"
    private let api: APIClient
    let metadata: MetadataStore
    private var clockTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var weatherFetchedAt: Date?

    init(api: APIClient = APIClient(), metadata: MetadataStore? = nil) {
        self.api = api
        self.metadata = metadata ?? .live()
        if ProcessInfo.processInfo.arguments.contains("-resetState") {
            UserDefaults.standard.removeObject(forKey: Self.tunedKey)
        }

        self.tunedChannelID = UserDefaults.standard.string(forKey: Self.tunedKey)
    }

    // MARK: - Loading

    func load() async {
        state = .loading
        weather = nil
        weatherExtra = nil
        weatherFetchedAt = nil

        async let lineupTask = api.lineup()
        async let schedulesTask = api.schedules()
        async let clipsTask = api.clips()

        do {
            let (lineup, schedulesResponse) = try await (lineupTask, schedulesTask)
            apply(lineup: lineup, response: schedulesResponse)
            if let manifest = try? await clipsTask {
                clips = manifest.clips
            }
            state = .ready
            lastScheduleRefresh = Date()
            now = Date()
            startClocks()
        } catch {
            state = .failed(Self.friendlyMessage(for: error))
            return
        }
    }

    func refreshSchedules() async {
        guard state == .ready else { return }
        do {
            let response = try await api.schedules()
            applySchedules(response)
            enqueueMetadata()
            lastScheduleRefresh = Date()
            now = Date()
        } catch {
            // Keep the schedule we already have; the next retry may work.
        }
    }

    func refreshIfStale() async {
        guard state == .ready else { return }
        if let last = lastScheduleRefresh, Date().timeIntervalSince(last) < 20 * 60 { return }
        await refreshSchedules()
    }

    private func apply(lineup: Lineup, response: SchedulesResponse) {
        applySchedules(response)

        let playable = lineup.channels
            .filter { channel in
                guard channel.kind == "ia" || channel.kind == "weather" else { return false }
                if channel.kind == "weather" { return true }
                return response.schedules[channel.id]?.items.isEmpty == false
            }
            .sorted { $0.num < $1.num }

        channels = playable

        if tunedChannelID == nil || !playable.contains(where: { $0.id == tunedChannelID }) {
            tunedChannelID = playable.first?.id
        }

        enqueueMetadata()
    }

    /// Queue the current and next programme of every linear channel for an
    /// optional metadata lookup. The guide only ever displays those two rows,
    /// so this covers what the preview can show without walking the whole grid.
    private func enqueueMetadata() {
        guard !channels.isEmpty else { return }
        let date = Date()
        var titles: [String] = []

        // Put the channel currently on screen first so its overview is the
        // first answer the guide can display when it opens.
        let ordered = channels.filter { $0.kind != "weather" }
            .sorted { lhs, rhs in
                if lhs.id == tunedChannelID { return true }
                if rhs.id == tunedChannelID { return false }
                return lhs.num < rhs.num
            }

        for channel in ordered {
            guard let schedule = schedules[channel.id], !schedule.items.isEmpty,
                  let slot = ScheduleEngine.slot(
                    in: schedule.items,
                    anchor: schedule.anchor ?? anchor,
                    at: date
                  )
            else { continue }

            if !slot.item.isAd {
                titles.append(slot.item.t)
            }

            let nextIndex = ScheduleEngine.nextProgramIndex(after: slot.index, in: schedule.items)
            let next = schedule.items[nextIndex]
            if !next.isAd {
                titles.append(next.t)
            }
        }

        metadata.enqueue(titles: titles)
    }

    private func applySchedules(_ response: SchedulesResponse) {
        anchor = response.anchor
        schedules = response.schedules
    }

    private func startClocks() {
        if clockTask == nil {
            clockTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard let self else { return }
                    self.now = Date()
                }
            }
        }
        if refreshTask == nil {
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(45 * 60))
                    guard let self else { return }
                    await self.refreshSchedules()
                }
            }
        }
    }

    // MARK: - Guide lookups

    func schedule(for channel: Channel) -> ChannelSchedule? {
        schedules[channel.id]
    }

    func slot(for channel: Channel, at date: Date) -> Slot? {
        guard let schedule = schedules[channel.id] else { return nil }
        return ScheduleEngine.slot(
            in: schedule.items,
            anchor: schedule.anchor ?? anchor,
            at: date
        )
    }

    func program(for channel: Channel, at date: Date) -> ProgramInfo {
        if channel.kind == "weather" {
            return ProgramInfo(title: "Local forecast", next: nil, isAd: false)
        }
        guard let schedule = schedule(for: channel), !schedule.items.isEmpty,
              let slot = ScheduleEngine.slot(in: schedule.items, anchor: schedule.anchor ?? anchor, at: date)
        else {
            return ProgramInfo(title: "NO SIGNAL", next: nil, isAd: false)
        }

        let current = slot.item
        let nextIndex = ScheduleEngine.nextProgramIndex(after: slot.index, in: schedule.items)
        let nextTitle = schedule.items[nextIndex].t
        let end = slot.start.addingTimeInterval(current.d)
        let progress = current.d > 0 ? min(1, max(0, slot.offset / current.d)) : nil

        return ProgramInfo(
            title: current.isAd ? "COMMERCIAL BREAK" : current.t,
            next: nextTitle == current.t ? nil : nextTitle,
            isAd: current.isAd,
            start: slot.start,
            end: end,
            progress: progress
        )
    }

    // MARK: - Weather

    func ensureWeather() async {
        if let fetched = weatherFetchedAt, weather != nil, Date().timeIntervalSince(fetched) < 15 * 60 {
            return
        }

        async let reportTask = api.weather()
        async let extraTask = api.weatherExtra()

        do {
            let report = try await reportTask
            weather = report
            weatherExtra = try? await extraTask
            weatherFetchedAt = Date()
        } catch {
            // The music can keep playing without a forecast.
        }
    }

    // MARK: - Helpers

    private static func friendlyMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                return "NO INTERNET CONNECTION"
            case .timedOut:
                return "THE CABLE COMPANY IS TAKING TOO LONG"
            default:
                break
            }
        }
        return "COULD NOT REACH THE CABLE COMPANY"
    }
}
