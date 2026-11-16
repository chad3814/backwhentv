import XCTest
@testable import BackWhenTV

final class UsageReporterTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "UsageReporterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    private func makeReporter(
        clock: @escaping () -> Date,
        sender: @escaping UsageSender
    ) -> UsageReporter {
        UsageReporter(defaults: defaults, version: "9.9", now: clock, sender: sender)
    }

    @MainActor
    func testCreatesAndPersistsAFormattedID() {
        let reporter = makeReporter(clock: Date.init) { _ in true }

        XCTAssertEqual(reporter.id.count, 24)
        XCTAssertTrue(reporter.id.allSatisfy(\.isHexDigit))
        XCTAssertTrue(UsageReporter.isValidID(reporter.id))
        XCTAssertEqual(defaults.string(forKey: UsageReporter.idKey), reporter.id)

        let second = makeReporter(clock: Date.init) { _ in true }
        XCTAssertEqual(second.id, reporter.id)
    }

    func testGeneratedIDLayoutAndChecksum() throws {
        let id = UsageReporter.generateID()
        XCTAssertEqual(id.count, 24)
        XCTAssertTrue(UsageReporter.isValidID(id))

        let bytes = try decode(id)
        XCTAssertEqual(bytes.count, 12)

        let payload = Array(bytes.prefix(11))
        let markerIndex = try XCTUnwrap(UsageReporter.markerIndex(in: payload))
        XCTAssertTrue((0...8).contains(markerIndex))
        XCTAssertEqual(Array(payload[markerIndex..<(markerIndex + 3)]), [0x43, 0x4C, 0x57])
        XCTAssertEqual(UsageReporter.crc8(payload), bytes[11])
    }

    func testMarkerIsPlacedAtRandomOffsets() throws {
        var positions: Set<Int> = []

        for _ in 0..<200 {
            let bytes = try decode(UsageReporter.generateID())
            let payload = Array(bytes.prefix(11))
            let index = try XCTUnwrap(UsageReporter.markerIndex(in: payload))
            XCTAssertTrue((0...8).contains(index))
            positions.insert(index)
        }

        XCTAssertGreaterThan(positions.count, 1)
    }

    func testReadmeExampleIDIsValid() {
        XCTAssertTrue(UsageReporter.isValidID("96e16bd9a5163051434c5770"))
    }

    func testChecksumRejectsAMutatedID() throws {
        let id = UsageReporter.generateID()
        var bytes = try decode(id)
        bytes[11] ^= 0x01 // corrupt the checksum byte itself

        let mutated = bytes.map { String(format: "%02x", $0) }.joined()
        XCTAssertFalse(UsageReporter.isValidID(mutated))
    }

    @MainActor
    func testOldUnmarkedIDIsReplaced() {
        let oldID = "0123456789abcdef01234567"
        defaults.set(oldID, forKey: UsageReporter.idKey)

        let reporter = makeReporter(clock: Date.init) { _ in true }

        XCTAssertNotEqual(reporter.id, oldID)
        XCTAssertTrue(UsageReporter.isValidID(reporter.id))
        XCTAssertEqual(defaults.string(forKey: UsageReporter.idKey), reporter.id)
    }

    @MainActor
    func testExistingFormattedIDIsPreserved() {
        let id = UsageReporter.generateID()
        defaults.set(id, forKey: UsageReporter.idKey)

        let reporter = makeReporter(clock: Date.init) { _ in true }

        XCTAssertEqual(reporter.id, id)
    }

    private func decode(_ hex: String) throws -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex

        while index < hex.endIndex {
            let next = try XCTUnwrap(hex.index(index, offsetBy: 2, limitedBy: hex.endIndex))
            let byte = try XCTUnwrap(UInt8(hex[index..<next], radix: 16))
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    @MainActor
    func testPayloadShapeAndVersion() async throws {
        var sent: [UsagePayload] = []
        let reporter = makeReporter(clock: Date.init) { payload in
            sent.append(payload)
            return true
        }

        reporter.switchTo("ia-kids-wb")
        await reporter.send()

        let payload = try XCTUnwrap(sent.last)
        XCTAssertEqual(payload.p, "appletv")
        XCTAssertEqual(payload.v, "9.9")
        XCTAssertEqual(payload.r, "")
        XCTAssertEqual(payload.id, reporter.id)
        XCTAssertEqual(payload.w, [String: Int]())
    }

    @MainActor
    func testRoundsMinutesAndAttributesThemToTheRightChannel() async {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        var sent: [UsagePayload] = []
        let reporter = makeReporter(clock: { clock }) { payload in
            sent.append(payload)
            return true
        }

        reporter.switchTo("channel-a")
        clock.addTimeInterval(90) // 1.5 minutes, rounded up like Math.round
        reporter.flush()
        XCTAssertEqual(reporter.watched["channel-a"], 2)

        // A switch flushes the old channel before the new one starts.
        reporter.switchTo("channel-b")
        clock.addTimeInterval(5 * 60)
        await reporter.send()

        XCTAssertEqual(sent.last?.w["channel-a"], 2)
        XCTAssertEqual(sent.last?.w["channel-b"], 5)
        XCTAssertTrue(reporter.watched.isEmpty)
    }

    @MainActor
    func testStoppingTrackingDoesNotCountIdleTime() async {
        var clock = Date(timeIntervalSince1970: 2_000_000)
        var sent: [UsagePayload] = []
        let reporter = makeReporter(clock: { clock }) { payload in
            sent.append(payload)
            return true
        }

        reporter.switchTo("channel-a")
        clock.addTimeInterval(2 * 60)
        reporter.switchTo(nil)
        clock.addTimeInterval(10 * 60)
        await reporter.send()

        XCTAssertEqual(sent.last?.w, ["channel-a": 2])
    }

    @MainActor
    func testFailedSendKeepsTheMinutesForTheNextAttempt() async {
        var clock = Date(timeIntervalSince1970: 3_000_000)
        var shouldSucceed = false
        var sent: [UsagePayload] = []
        let reporter = makeReporter(clock: { clock }) { payload in
            sent.append(payload)
            return shouldSucceed
        }

        reporter.switchTo("channel-a")
        clock.addTimeInterval(5 * 60)
        await reporter.send()

        XCTAssertEqual(reporter.watched["channel-a"], 5)
        XCTAssertEqual(sent.last?.w, ["channel-a": 5])

        shouldSucceed = true
        await reporter.send()
        XCTAssertTrue(reporter.watched.isEmpty)
    }

    func testRequestTargetsTheUsageEndpointWithTheExpectedBody() throws {
        let payload = UsagePayload(
            id: "b42c19c4483d004fd947c5bb",
            p: "appletv",
            v: "1.0",
            r: "",
            w: ["ia-kids-wb": 5]
        )

        let request = try UsageReporter.makeRequest(payload)

        XCTAssertEqual(request.url?.absoluteString, "https://www.backwhen.stream/api/ev")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(Set(json.keys), ["id", "p", "v", "r", "w"])
        XCTAssertEqual(json["p"] as? String, "appletv")
        XCTAssertEqual(json["v"] as? String, "1.0")
        XCTAssertEqual(json["r"] as? String, "")
        XCTAssertEqual(json["id"] as? String, "b42c19c4483d004fd947c5bb")
        XCTAssertEqual((json["w"] as? [String: Int])?["ia-kids-wb"], 5)
    }
}
