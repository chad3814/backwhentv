import Foundation

/// The channel schedule is a fixed list of items that repeats from a per-channel
/// anchor, exactly like the web player. Given a moment in time, work out which
/// item is on and how far into it we are.
enum ScheduleEngine {
    static func totalDuration(_ items: [ScheduleItem]) -> Double {
        items.reduce(0) { $0 + max(0, $1.d) }
    }

    static func slot(in items: [ScheduleItem], anchor: Double, at date: Date) -> Slot? {
        guard !items.isEmpty else { return nil }
        let total = totalDuration(items)
        guard total > 0 else { return nil }

        let now = date.timeIntervalSince1970
        var position = (now - anchor).truncatingRemainder(dividingBy: total)
        if position < 0 { position += total }

        var accumulated = 0.0
        for (index, item) in items.enumerated() {
            let end = accumulated + max(0, item.d)
            if position < end || index == items.count - 1 {
                let offset = min(max(0, position - accumulated), max(0, item.d - 0.001))
                return Slot(
                    index: index,
                    item: item,
                    offset: offset,
                    start: date.addingTimeInterval(-offset)
                )
            }
            accumulated = end
        }
        return nil
    }

    /// The next item that isn't a commercial pod, used for the guide's "next"
    /// column. Returns the current index if the whole schedule is ad breaks.
    static func nextProgramIndex(after index: Int, in items: [ScheduleItem]) -> Int {
        guard !items.isEmpty else { return 0 }
        var cursor = index
        for _ in 0..<items.count {
            cursor = (cursor + 1) % items.count
            if !items[cursor].isAd { return cursor }
        }
        return index
    }
}
