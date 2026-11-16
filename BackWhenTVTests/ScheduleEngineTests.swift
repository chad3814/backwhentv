import XCTest
@testable import BackWhenTV

final class ScheduleEngineTests: XCTestCase {
    private func item(_ title: String, _ duration: Double, ad: Bool = false) -> ScheduleItem {
        ScheduleItem(
            t: title,
            u: "https://example.com/\(title).mp4",
            f: nil,
            d: duration,
            a: ad ? 1 : nil,
            h: nil,
            preStitched: nil
        )
    }

    func testFindsFirstItem() {
        let items = [item("one", 100), item("two", 200), item("three", 300)]
        let slot = ScheduleEngine.slot(in: items, anchor: 0, at: Date(timeIntervalSince1970: 50))
        XCTAssertEqual(slot?.index, 0)
        XCTAssertEqual(slot?.item.t, "one")
        XCTAssertEqual(slot?.offset ?? -1, 50, accuracy: 0.001)
    }

    func testFindsMiddleItem() {
        let items = [item("one", 100), item("two", 200), item("three", 300)]
        let slot = ScheduleEngine.slot(in: items, anchor: 0, at: Date(timeIntervalSince1970: 150))
        XCTAssertEqual(slot?.index, 1)
        XCTAssertEqual(slot?.offset ?? -1, 50, accuracy: 0.001)
    }

    func testWrapsAroundCycle() {
        let items = [item("one", 100), item("two", 200), item("three", 300)]
        let slot = ScheduleEngine.slot(in: items, anchor: 0, at: Date(timeIntervalSince1970: 650))
        XCTAssertEqual(slot?.index, 0)
        XCTAssertEqual(slot?.offset ?? -1, 50, accuracy: 0.001)
    }

    func testBeforeAnchorWrapsBackwards() {
        let items = [item("one", 100), item("two", 200), item("three", 300)]
        let slot = ScheduleEngine.slot(in: items, anchor: 1_000, at: Date(timeIntervalSince1970: 950))
        XCTAssertEqual(slot?.index, 2)
        XCTAssertEqual(slot?.offset ?? -1, 250, accuracy: 0.001)
    }

    func testEmptyAndZeroDurationSchedules() {
        XCTAssertNil(ScheduleEngine.slot(in: [], anchor: 0, at: Date()))
        XCTAssertNil(ScheduleEngine.slot(in: [item("zero", 0)], anchor: 0, at: Date()))
    }

    func testNextProgramSkipsCommercials() {
        let items = [
            item("show a", 100),
            item("break", 60, ad: true),
            item("break 2", 60, ad: true),
            item("show b", 100)
        ]
        XCTAssertEqual(ScheduleEngine.nextProgramIndex(after: 0, in: items), 3)
        XCTAssertEqual(ScheduleEngine.nextProgramIndex(after: 2, in: items), 3)
        XCTAssertEqual(ScheduleEngine.nextProgramIndex(after: 3, in: items), 0)
    }

    func testNextProgramFallsBackWhenEverythingIsAnAd() {
        let items = [item("break", 60, ad: true), item("break 2", 60, ad: true)]
        XCTAssertEqual(ScheduleEngine.nextProgramIndex(after: 1, in: items), 1)
    }
}
