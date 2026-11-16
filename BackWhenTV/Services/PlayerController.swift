import AVFoundation
import Foundation
import Observation

/// Owns the AVPlayer and keeps it tuned to the live schedule: seeking into the
/// right part of a show, assembling commercial pods, falling back to archive.org
/// when a storage node is down, and rolling into the next programme on time.
@MainActor
@Observable
final class PlayerController {
    let player = AVPlayer()

    private(set) var currentChannel: Channel?
    private(set) var isLoading = false
    private(set) var noSignal = false
    private(set) var isPaused = false
    private(set) var isWeather = false

    private var store: GuideStore?

    private var generation = 0
    private var statusObservation: NSKeyValueObservation?
    private var playerObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var deadlineTask: Task<Void, Never>?
    private var loadTimeoutTask: Task<Void, Never>?
    private var currentURL: URL?
    private var currentFallback: URL?
    private var currentOffset: Double = 0
    private var badURLs: Set<String> = []
    private var suspended = false
    private var loadToken = 0

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause

        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard player.timeControlStatus == .playing else { return }
            Task { @MainActor in
                self?.isLoading = false
            }
        }
    }

    // MARK: - Tuning

    func tune(_ channel: Channel, store: GuideStore) {
        self.store = store
        suspended = false
        currentChannel = channel
        isWeather = channel.kind == "weather"
        isPaused = false
        noSignal = false
        badURLs.removeAll()

        let generation = newGeneration()
        isLoading = true

        if isWeather {
            Task { await store.ensureWeather() }
        }
        playCurrent(channel: channel, generation: generation, at: Date())
    }

    func togglePause() {
        guard let channel = currentChannel, let store else { return }
        if isPaused {
            isPaused = false
            tune(channel, store: store) // resume at the live point, not the paused frame
        } else {
            isPaused = true
            isLoading = false
            player.pause()
            deadlineTask?.cancel()
            loadTimeoutTask?.cancel()
        }
    }

    func suspendPlayback() {
        guard currentChannel != nil, !isPaused else { return }
        suspended = true
        player.pause()
        deadlineTask?.cancel()
        loadTimeoutTask?.cancel()
    }

    func resumeIfSuspended() {
        guard suspended, let channel = currentChannel, let store else { return }
        suspended = false
        tune(channel, store: store)
    }

    func stop() {
        _ = newGeneration()
        currentChannel = nil
        isWeather = false
        isLoading = false
        isPaused = false
    }

    // MARK: - Schedule playback

    private func playCurrent(
        channel: Channel,
        generation: Int,
        at date: Date,
        forcedIndex: Int? = nil,
        forcedOffset: Double = 0
    ) {
        guard generation == self.generation, let store else { return }
        guard let schedule = store.schedule(for: channel), !schedule.items.isEmpty else {
            isLoading = false
            noSignal = true
            return
        }

        let slot: Slot?
        if let forcedIndex, schedule.items.indices.contains(forcedIndex) {
            let offset = max(0, forcedOffset)
            slot = Slot(
                index: forcedIndex,
                item: schedule.items[forcedIndex],
                offset: offset,
                start: date.addingTimeInterval(-offset)
            )
        } else {
            slot = store.slot(for: channel, at: date)
        }

        guard let slot else {
            isLoading = false
            noSignal = true
            return
        }

        scheduleDeadline(seconds: slot.remaining + 1.5, generation: generation) { [weak self] in
            self?.advance(channel: channel, generation: generation, after: slot.index)
        }

        if slot.item.isAd, !store.clips.isEmpty {
            playPod(channel: channel, slot: slot, generation: generation)
        } else if let url = slot.item.url {
            playStream(
                url: url,
                fallback: slot.item.fallbackURL,
                offset: slot.offset,
                generation: generation,
                onEnd: { [weak self] in
                    self?.advance(channel: channel, generation: generation, after: slot.index)
                },
                onFail: { [weak self] in
                    self?.signalFailure(channel: channel, generation: generation, after: slot.index)
                }
            )
        } else {
            signalFailure(channel: channel, generation: generation, after: slot.index)
        }
    }

    private func advance(channel: Channel, generation: Int, after index: Int) {
        guard generation == self.generation,
              let store,
              let schedule = store.schedule(for: channel),
              !schedule.items.isEmpty
        else { return }

        let date = Date()
        if let live = store.slot(for: channel, at: date), live.index != index {
            // The file ended at a different point than the grid predicted; jump
            // to wherever the channel actually is so we stay in sync with the guide.
            playCurrent(
                channel: channel,
                generation: generation,
                at: date,
                forcedIndex: live.index,
                forcedOffset: live.offset
            )
        } else {
            let next = (index + 1) % schedule.items.count
            playCurrent(channel: channel, generation: generation, at: date, forcedIndex: next, forcedOffset: 0)
        }
    }

    // MARK: - Commercial pods

    private func playPod(channel: Channel, slot: Slot, generation: Int) {
        guard let store else { return }
        let plan = PodPlanner.plan(
            clips: store.clips,
            channelID: channel.id,
            start: slot.start.timeIntervalSince1970,
            total: slot.item.d
        )

        guard !plan.isEmpty else {
            if let url = slot.item.url {
                playStream(
                    url: url,
                    fallback: slot.item.fallbackURL,
                    offset: slot.offset,
                    generation: generation,
                    onEnd: { [weak self] in
                        self?.advance(channel: channel, generation: generation, after: slot.index)
                    },
                    onFail: { [weak self] in
                        self?.signalFailure(channel: channel, generation: generation, after: slot.index)
                    }
                )
            } else {
                signalFailure(channel: channel, generation: generation, after: slot.index)
            }
            return
        }

        var accumulated = 0.0
        var index = 0
        while index < plan.count, slot.offset >= accumulated + plan[index].dur {
            accumulated += plan[index].dur
            index += 1
        }
        guard index < plan.count else {
            // Tuned in after the last generated spot; hold until the pod's
            // deadline rolls us into the next programme.
            isLoading = false
            return
        }
        playPodClip(plan: plan, index: index, offset: max(0, slot.offset - accumulated), channel: channel, generation: generation)
    }

    private func playPodClip(plan: [Clip], index: Int, offset: Double, channel: Channel, generation: Int) {
        guard generation == self.generation, index < plan.count else { return }
        let clip = plan[index]
        playStream(
            url: clip.url,
            fallback: nil,
            offset: offset,
            generation: generation,
            onEnd: { [weak self] in
                self?.playPodClip(plan: plan, index: index + 1, offset: 0, channel: channel, generation: generation)
            },
            onFail: { [weak self] in
                self?.playPodClip(plan: plan, index: index + 1, offset: 0, channel: channel, generation: generation)
            }
        )
    }

    // MARK: - AVPlayer plumbing

    private func playStream(
        url: URL,
        fallback: URL?,
        offset: Double,
        generation: Int,
        onEnd: @escaping @MainActor () -> Void,
        onFail: @escaping @MainActor () -> Void
    ) {
        guard generation == self.generation else { return }
        guard !badURLs.contains(url.absoluteString) else {
            onFail()
            return
        }

        loadToken += 1
        let token = loadToken

        currentURL = url
        currentFallback = fallback
        currentOffset = offset

        let item = AVPlayerItem(url: url)

        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, generation == self.generation, token == self.loadToken else { return }
                switch item.status {
                case .readyToPlay:
                    self.loadTimeoutTask?.cancel()
                    self.beginPlayback(item: item, offset: offset, generation: generation)
                case .failed:
                    self.fail(
                        url: url,
                        fallback: fallback,
                        offset: offset,
                        generation: generation,
                        onEnd: onEnd,
                        onFail: onFail
                    )
                default:
                    break
                }
            }
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, generation == self.generation, token == self.loadToken else { return }
                self.isLoading = false
                onEnd()
            }
        }

        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
        }
        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, generation == self.generation, token == self.loadToken else { return }
                self.fail(
                    url: url,
                    fallback: fallback,
                    offset: offset,
                    generation: generation,
                    onEnd: onEnd,
                    onFail: onFail
                )
            }
        }

        loadTimeoutTask?.cancel()
        loadTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard let self,
                  !Task.isCancelled,
                  generation == self.generation,
                  token == self.loadToken,
                  item.status != .readyToPlay
            else { return }
            self.fail(
                url: url,
                fallback: fallback,
                offset: offset,
                generation: generation,
                onEnd: onEnd,
                onFail: onFail
            )
        }

        player.replaceCurrentItem(with: item)
    }

    private func beginPlayback(item: AVPlayerItem, offset: Double, generation: Int) {
        guard generation == self.generation else { return }
        let duration = item.duration.seconds
        var target = offset
        if target > 1, duration.isFinite, duration > 0 {
            target = min(target, max(0, duration - 2))
        }
        if target > 0.5 {
            player.seek(
                to: CMTime(seconds: target, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, generation == self.generation else { return }
                    self.isLoading = false
                    self.player.play()
                }
            }
        } else {
            isLoading = false
            player.play()
        }
    }

    private func fail(
        url: URL,
        fallback: URL?,
        offset: Double,
        generation: Int,
        onEnd: @escaping @MainActor () -> Void,
        onFail: @escaping @MainActor () -> Void
    ) {
        guard generation == self.generation else { return }

        if let fallback,
           fallback != url,
           !badURLs.contains(fallback.absoluteString) {
            // The direct storage node is down; archive.org's own download link
            // usually still has the file. Try it at the same position.
            playStream(
                url: fallback,
                fallback: nil,
                offset: offset,
                generation: generation,
                onEnd: onEnd,
                onFail: onFail
            )
            return
        }

        badURLs.insert(url.absoluteString)
        isLoading = false
        onFail()
    }

    private func signalFailure(channel: Channel, generation: Int, after index: Int) {
        guard generation == self.generation else { return }
        isLoading = false
        noSignal = true
        deadlineTask?.cancel()

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, generation == self.generation else { return }
            self.noSignal = false
            self.advance(channel: channel, generation: generation, after: index)
        }
    }

    private func scheduleDeadline(seconds: Double, generation: Int, action: @escaping @MainActor () -> Void) {
        deadlineTask?.cancel()
        let clamped = min(max(0.5, seconds), 6 * 60 * 60)
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
            guard let self, !Task.isCancelled, generation == self.generation else { return }
            action()
        }
    }

    // MARK: - Teardown

    @discardableResult
    private func newGeneration() -> Int {
        generation += 1
        teardown()
        return generation
    }

    private func teardown() {
        deadlineTask?.cancel()
        deadlineTask = nil
        loadTimeoutTask?.cancel()
        loadTimeoutTask = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
        }
        failedObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        currentFallback = nil
    }
}
