import XCTest
@testable import BackWhenTV

final class PodPlannerTests: XCTestCase {
    private func loadClips() throws -> [Clip] {
        let bundle = Bundle(for: PodPlannerTests.self)
        guard let url = bundle.url(forResource: "clips", withExtension: "json") else {
            XCTFail("clips.json fixture missing from the test bundle")
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ClipManifest.self, from: data).clips
    }

    /// The web player's mulberry32 output for the same seed, calculated with
    /// node against the live manifest. If this drifts, mid-break tune-ins would
    /// no longer line up with everyone else's commercial pod.
    func testSeventySecondPodMatchesWebPlanner() throws {
        let plan = PodPlanner.plan(
            clips: try loadClips(),
            channelID: "ia-kids-wb",
            start: 1_794_781_778,
            total: 70
        )
        XCTAssertEqual(plan.map(\.id), [
            "stinger-15",
            "sponsor-25",
            "trivia-08-pokemon",
            "donate-15"
        ])
        XCTAssertEqual(plan.reduce(0) { $0 + $1.dur }, 70, accuracy: 0.001)
    }

    func testNinetySecondPodFillsWithMoreStingers() throws {
        let plan = PodPlanner.plan(
            clips: try loadClips(),
            channelID: "ia-kids-wb",
            start: 1_794_781_778,
            total: 90
        )
        XCTAssertEqual(plan.map(\.id), [
            "stinger-30",
            "stinger-5",
            "sponsor-25",
            "trivia-08-pokemon",
            "donate-15"
        ])
        XCTAssertEqual(plan.reduce(0) { $0 + $1.dur }, 90, accuracy: 0.001)
    }

    func testPlanIsDeterministic() throws {
        let clips = try loadClips()
        let first = PodPlanner.plan(clips: clips, channelID: "ia-90s-cartoons", start: 1_794_779_732, total: 60)
        let second = PodPlanner.plan(clips: clips, channelID: "ia-90s-cartoons", start: 1_794_779_732, total: 60)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.id), [
            "stinger-5",
            "sponsor-15",
            "trivia-01-rugrats",
            "donate-25"
        ])
    }

    func testEmptyInputsProduceNoPlan() throws {
        XCTAssertTrue(PodPlanner.plan(clips: [], channelID: "x", start: 0, total: 60).isEmpty)
        XCTAssertTrue(PodPlanner.plan(clips: try loadClips(), channelID: "x", start: 0, total: 0).isEmpty)
    }

    func testStingersAreCappedAtFour() throws {
        let plan = PodPlanner.plan(
            clips: try loadClips(),
            channelID: "cap-test",
            start: 12_345,
            total: 600
        )
        let stingers = plan.filter { $0.type == "stinger" }
        XCTAssertLessThanOrEqual(stingers.count, 4)
    }
}
