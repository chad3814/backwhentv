import Foundation
import OSLog

struct UsagePayload: Codable, Equatable {
    let id: String
    let p: String
    let v: String
    let r: String
    let w: [String: Int]
}

typealias UsageSender = (UsagePayload) async -> Bool

/// Sends the same anonymous viewing stats as the web player: a random 24-hex
/// device id, the app version, an empty referrer, and minutes watched per
/// channel. Everything is flushed to `/api/ev` on launch, every five minutes,
/// and when the app leaves the foreground.
@MainActor
final class UsageReporter {
    nonisolated static let idKey = "bw.usageID"
    nonisolated private static let endpoint = URL(string: "https://www.backwhen.stream/api/ev")!
    nonisolated private static let logger = Logger(subsystem: "stream.backwhen.tv", category: "usage")
    nonisolated static let marker: [UInt8] = [0x43, 0x4C, 0x57]
    nonisolated private static let payloadByteCount = 11
    nonisolated private static let idByteCount = 12

    private let defaults: UserDefaults
    private let version: String
    private let now: () -> Date
    private let sender: UsageSender

    private(set) var id: String
    private(set) var watched: [String: Int] = [:]

    private var currentChannelID: String?
    private var segmentStart: Date?
    private var isTracking = false
    private var isSending = false
    private var isRunning = false
    private var timerTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        version: String = UsageReporter.bundleVersion,
        now: @escaping () -> Date = Date.init,
        sender: UsageSender? = nil
    ) {
        self.defaults = defaults
        self.version = version
        self.now = now
        self.sender = sender ?? UsageReporter.post
        self.id = UsageReporter.loadOrCreateID(defaults: defaults)
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // The web page counts the visit immediately, before any minutes accrue.
        Task { await send() }

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5 * 60))
                guard let self, !Task.isCancelled else { return }
                await self.send()
            }
        }
    }

    func flushAndSend() {
        flush()
        Task { await send() }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
    }

    // MARK: - Watching

    func switchTo(_ channelID: String?) {
        flush()
        currentChannelID = channelID
        if let channelID, !channelID.isEmpty {
            isTracking = true
            segmentStart = now()
        } else {
            isTracking = false
            segmentStart = nil
        }
    }

    func flush() {
        guard isTracking,
              let channelID = currentChannelID,
              let start = segmentStart
        else { return }

        let minutes = Int((now().timeIntervalSince(start) / 60).rounded())
        guard minutes > 0 else { return }

        watched[channelID, default: 0] += minutes
        segmentStart = start.addingTimeInterval(Double(minutes) * 60)
    }

    // MARK: - Sending

    func send() async {
        guard !isSending else { return }
        flush()

        let snapshot = watched
        let payload = UsagePayload(id: id, p: "appletv", v: version, r: "", w: snapshot)

        isSending = true
        let success = await sender(payload)
        isSending = false

        guard success else { return }
        // Only subtract what was actually sent, so minutes accrued while the
        // request was in flight are kept for the next report.
        for (channelID, minutes) in snapshot {
            let remaining = (watched[channelID] ?? 0) - minutes
            if remaining > 0 {
                watched[channelID] = remaining
            } else {
                watched.removeValue(forKey: channelID)
            }
        }
    }

    // MARK: - Defaults

    nonisolated private static var bundleVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    nonisolated private static func loadOrCreateID(defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: idKey), isValidID(existing) {
            return existing
        }
        let id = generateID()
        defaults.set(id, forKey: idKey)
        return id
    }

    /// 12 bytes: eight random bytes with `43 4C 57` placed contiguously at a
    /// random offset inside the first 11 bytes, then a CRC-8 of those 11 bytes.
    nonisolated static func generateID() -> String {
        var generator = SystemRandomNumberGenerator()

        var payload = (0..<payloadByteCount).map { _ in
            UInt8.random(in: 0...255, using: &generator)
        }
        let markerStart = Int.random(in: 0...(payloadByteCount - marker.count), using: &generator)
        for (offset, byte) in marker.enumerated() {
            payload[markerStart + offset] = byte
        }

        let bytes = payload + [crc8(payload)]
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func isValidID(_ id: String) -> Bool {
        guard id.count == idByteCount * 2,
              let bytes = hexBytes(id),
              bytes.count == idByteCount
        else { return false }

        let payload = Array(bytes[0..<payloadByteCount])
        guard markerIndex(in: payload) != nil else { return false }
        return crc8(payload) == bytes[payloadByteCount]
    }

    nonisolated static func markerIndex(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= marker.count else { return nil }
        for index in 0...(bytes.count - marker.count) {
            if Array(bytes[index..<(index + marker.count)]) == marker {
                return index
            }
        }
        return nil
    }

    nonisolated static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 {
                if (crc & 0x80) != 0 {
                    crc = (crc &<< 1) ^ 0x07
                } else {
                    crc = crc &<< 1
                }
            }
        }
        return crc
    }

    private nonisolated static func hexBytes(_ string: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(string.count / 2)
        var index = string.startIndex

        while index < string.endIndex {
            guard let next = string.index(index, offsetBy: 2, limitedBy: string.endIndex),
                  let byte = UInt8(string[index..<next], radix: 16)
            else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    nonisolated static func makeRequest(_ payload: UsagePayload) throws -> URLRequest {
        let body = try JSONEncoder().encode(payload)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BackWhenTV-tvOS/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        return request
    }

    nonisolated private static func post(_ payload: UsagePayload) async -> Bool {
        guard let request = try? makeRequest(payload) else { return false }

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else {
            logger.debug("usage report failed: no HTTP response")
            return false
        }

        if (200..<300).contains(http.statusCode) {
            logger.debug("usage report accepted: HTTP \(http.statusCode)")
            return true
        }
        logger.debug("usage report rejected: HTTP \(http.statusCode)")
        return false
    }
}
