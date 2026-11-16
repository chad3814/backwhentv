import Foundation
import Observation
import OSLog

struct MetadataQuery {
    let lookup: MetadataLookup
    let key: String

    init?(rawTitle: String) {
        var name = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let upper = name.uppercased()
        guard !upper.hasPrefix("COMMERCIAL BREAK") else { return nil }

        // Strip the schedule's own labels before handing the title to the
        // filename parser. These are not part of the programme's name.
        if upper.hasPrefix("RETRO SHORT |") {
            name = String(name.dropFirst("RETRO SHORT |".count))
        } else if upper.hasPrefix("RETRO SHORT ") {
            name = String(name.dropFirst("RETRO SHORT ".count))
        }
        if name.uppercased().hasPrefix("C THE ") {
            name = String(name.dropFirst(2))
        }

        name = name.replacingOccurrences(of: "|", with: " ")
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let category: MetadataLookup.Category =
            name.range(of: #"S[0-9]+E[0-9]+"#, options: .regularExpression) != nil ? .tv : .movies

        let lookup = MetadataLookup(category: category, name: name)
        self.lookup = lookup
        self.key = lookup.key
    }
}

/// Batches schedule titles through OpenMetadata and keeps any overviews that
/// come back. One worker drains the queue in order, which keeps requests polite
/// and gives the guide a stable source of extra programme info.
@MainActor
@Observable
final class MetadataStore {
    typealias BatchLookup = ([MetadataLookup]) async throws -> [MetadataLookupResult]
    typealias PollLookup = (String) async throws -> MetadataLookupResult?

    private(set) var records: [String: MetadataInfo] = [:]

    private var queue: [MetadataLookup] = []
    private var queuedKeys: Set<String> = []
    private var attemptedKeys: Set<String> = []
    private var pollingIDs: Set<String> = []
    private var pollingTasks: [String: Task<Void, Never>] = [:]
    private var worker: Task<Void, Never>?

    private let lookup: BatchLookup?
    private let poll: PollLookup?

    private let maxBatchSize = 100
    private let maxEnqueue = 300

    private static let logger = Logger(subsystem: "stream.backwhen.tv", category: "metadata")

    init(client: OpenMetadataClient?) {
        if let client {
            self.lookup = { items in try await client.lookup(items) }
            self.poll = { lookupID in try await client.poll(lookupID: lookupID) }
        } else {
            self.lookup = nil
            self.poll = nil
        }
    }

    init(lookup: @escaping BatchLookup, poll: @escaping PollLookup = { _ in nil }) {
        self.lookup = lookup
        self.poll = poll
    }

    static func live() -> MetadataStore {
        MetadataStore(client: OpenMetadataClient.live())
    }

    var isEnabled: Bool { lookup != nil }
    var isWorking: Bool { worker != nil }

    /// The overview for a programme title, if one has arrived.
    func overview(forTitle rawTitle: String) -> MetadataInfo? {
        guard let query = MetadataQuery(rawTitle: rawTitle) else { return nil }
        return records[query.key]
    }

    func enqueue(titles: [String]) {
        guard lookup != nil else { return }

        let offered = titles.count
        var remaining = maxEnqueue
        for title in titles {
            guard remaining > 0 else { break }
            guard let query = MetadataQuery(rawTitle: title) else { continue }

            let key = query.key
            if records[key] != nil || queuedKeys.contains(key) || attemptedKeys.contains(key) {
                continue
            }

            queue.append(query.lookup)
            queuedKeys.insert(key)
            remaining -= 1
        }

        Self.logger.debug("metadata enqueue: \(offered) titles, \(self.queue.count) queued")
        startWorkerIfNeeded()
    }

    // MARK: - Queue

    private func startWorkerIfNeeded() {
        guard worker == nil, lookup != nil, !queue.isEmpty else { return }

        worker = Task { [weak self] in
            await self?.drainQueue()
            self?.worker = nil
        }
    }

    private func drainQueue() async {
        guard let lookup else { return }
        var rateLimitRetries = 0

        while !queue.isEmpty {
            let batch = Array(queue.prefix(maxBatchSize))
            queue.removeFirst(batch.count)

            do {
                let results = try await lookup(batch)
                rateLimitRetries = 0
                apply(results, to: batch)

                if !queue.isEmpty {
                    try? await Task.sleep(for: .milliseconds(250))
                }
            } catch OpenMetadataError.rateLimited(let seconds) {
                if rateLimitRetries < 2 {
                    rateLimitRetries += 1
                    queue.insert(contentsOf: batch, at: 0)
                    let delay = min(max(seconds, 1), 30)
                    Self.logger.debug("metadata queue paused for \(Int(delay))s")
                    try? await Task.sleep(for: .seconds(delay))
                } else {
                    Self.logger.debug("metadata queue dropped \(batch.count) items after repeated rate limits")
                    abandon(batch)
                }
            } catch {
                Self.logger.debug("metadata batch failed: \(error.localizedDescription)")
                abandon(batch)
            }
        }
    }

    private func abandon(_ batch: [MetadataLookup]) {
        for item in batch {
            queuedKeys.remove(item.key)
        }
    }

    private func apply(_ results: [MetadataLookupResult], to batch: [MetadataLookup]) {
        for (item, result) in zip(batch, results) {
            if let info = result.info {
                records[item.key] = info
                Self.logger.debug("metadata overview stored for \(item.name)")
            }

            if result.isPending, let lookupID = result.lookupId {
                beginPolling(lookupID: lookupID, item: item)
                continue
            }

            queuedKeys.remove(item.key)
            if result.info == nil {
                attemptedKeys.insert(item.key)
            }
        }

        if results.count < batch.count {
            for item in batch.dropFirst(results.count) {
                queuedKeys.remove(item.key)
            }
        }
    }

    // MARK: - Partial lookups

    private func beginPolling(lookupID: String, item: MetadataLookup) {
        guard let poll else {
            queuedKeys.remove(item.key)
            attemptedKeys.insert(item.key)
            return
        }
        guard !pollingIDs.contains(lookupID) else { return }

        pollingIDs.insert(lookupID)
        pollingTasks[lookupID] = Task { [weak self] in
            var resolved: MetadataLookupResult?

            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }

                do {
                    resolved = try await poll(lookupID)
                } catch {
                    break
                }

                if let state = resolved?.state, state == "resolved" || state == "unresolved" {
                    break
                }
            }

            guard let self else { return }
            self.pollingIDs.remove(lookupID)
            self.pollingTasks[lookupID] = nil
            self.queuedKeys.remove(item.key)

            if let info = resolved?.info {
                self.records[item.key] = info
            } else {
                self.attemptedKeys.insert(item.key)
            }
        }
    }
}
