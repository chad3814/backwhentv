import Foundation

/// Builds the line-up of stingers, sponsor spots, trivia cards and donation
/// asks that fills a commercial pod. The pick is seeded from the channel id and
/// the pod's start time, so everyone watching the same break sees the same
/// thing (and a mid-break tune-in joins at the right moment).
enum PodPlanner {
    static func plan(clips: [Clip], channelID: String, start: Double, total: Double) -> [Clip] {
        guard !clips.isEmpty, total > 0 else { return [] }

        func clipsOfType(_ type: String) -> [Clip] {
            clips.filter { $0.type == type }
        }

        var random = PodRandom(seed: "\(channelID):\(Int(start.rounded()))")

        func pick(_ pool: [Clip]) -> Clip? {
            guard !pool.isEmpty else { return nil }
            let position = Int(random.next() * Double(pool.count))
            return pool[min(pool.count - 1, max(0, position))]
        }

        let sponsored = clipsOfType("sponsored")
        let house = clipsOfType("sponsor")

        var spots: [Clip] = []
        if let clip = pick(sponsored.isEmpty ? house : sponsored) { spots.append(clip) }
        if let clip = pick(clipsOfType("trivia")) { spots.append(clip) }
        if sponsored.isEmpty {
            if let clip = pick(clipsOfType("donate")) { spots.append(clip) }
        } else if random.next() < 0.5 {
            if let clip = pick(house) { spots.append(clip) }
        } else {
            if let clip = pick(clipsOfType("donate")) { spots.append(clip) }
        }

        var fill = total - spots.reduce(0) { $0 + $1.dur }
        var lead: [Clip] = []
        let stingers = clipsOfType("stinger").sorted { $0.dur > $1.dur }
        for stinger in stingers {
            while fill >= stinger.dur - 0.01 && fill >= 2 && lead.count < 4 {
                lead.append(stinger)
                fill -= stinger.dur
            }
        }

        return lead + spots
    }
}

/// A tiny mulberry32 port. The first stage hashes the seed like the web player's
/// FNV-1a loop so both produce identical breaks.
struct PodRandom {
    private var state: UInt32

    init(seed: String) {
        var hash: UInt32 = 2_166_136_261
        for unit in seed.utf16 {
            hash = (hash ^ UInt32(unit)) &* 16_777_619
        }
        state = hash
    }

    mutating func next() -> Double {
        state = state &+ 0x6d2b79f5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}
