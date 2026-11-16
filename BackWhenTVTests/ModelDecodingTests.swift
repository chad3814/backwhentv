import XCTest
@testable import BackWhenTV

final class ModelDecodingTests: XCTestCase {
    func testDecodesLineupWithOptionalFieldsMissing() throws {
        let json = """
        {
          "version": 1,
          "anchor": 1704067200,
          "channels": [
            {"id":"ia-retro-newswire","num":3,"name":"Newswire","kind":"ia"},
            {"id":"ia-retro-weather","num":2,"name":"WeatherStar","kind":"weather","blurb":"Local radar"}
          ]
        }
        """.data(using: .utf8)!

        let lineup = try JSONDecoder().decode(Lineup.self, from: json)
        XCTAssertEqual(lineup.channels.count, 2)
        XCTAssertEqual(lineup.channels[0].name, "Newswire")
        XCTAssertNil(lineup.channels[0].blurb)
        XCTAssertTrue(lineup.channels[1].isWeather)
    }

    func testDecodesScheduleItemsIncludingPodsAndFallbacks() throws {
        let json = """
        {
          "built": 1794780957747,
          "anchor": 1704067200,
          "version": "2026.11.11.6",
          "gen_ts": 1794780057,
          "valid_until": 1795391498,
          "schedules": {
            "ia-kids-wb": {
              "id": "ia-kids-wb",
              "anchor": 1794780803,
              "items": [
                {
                  "t": "RETRO SHORT",
                  "u": "https://archive.org/download/woody/woody_512kb.mp4",
                  "f": "https://archive.org/download/woody/woody_512kb.mp4",
                  "d": 411,
                  "pre_stitched": false,
                  "s": 1794780803,
                  "e": 1794781214,
                  "h": 720
                },
                {
                  "t": "COMMERCIAL BREAK",
                  "u": "https://backwhen.stream/clips/stinger-10.mp4",
                  "d": 70,
                  "a": 1
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SchedulesResponse.self, from: json)
        XCTAssertEqual(response.schedules.count, 1)
        let schedule = try XCTUnwrap(response.schedules["ia-kids-wb"])
        XCTAssertEqual(schedule.anchor, 1_794_780_803)
        XCTAssertEqual(schedule.items.count, 2)
        XCTAssertFalse(schedule.items[0].isAd)
        XCTAssertEqual(schedule.items[0].fallbackURL?.absoluteString, schedule.items[0].u)
        XCTAssertEqual(schedule.items[0].h, 720)
        XCTAssertTrue(schedule.items[1].isAd)
        XCTAssertNil(schedule.items[1].f)
    }

    func testDecodesWeather() throws {
        let json = """
        {
          "city": "Maquoketa",
          "state": "IA",
          "now": {
            "tempF": 46,
            "text": "Clear",
            "windMph": 5,
            "windDir": "SW",
            "humidity": 49,
            "pressureIn": 30.42,
            "visibilityMi": 10,
            "station": "Dubuque Regional Airport"
          },
          "periods": [
            {"name": "Tonight", "tempF": 26, "day": false, "short": "Mostly Clear", "detail": "Mostly clear."}
          ]
        }
        """.data(using: .utf8)!

        let report = try JSONDecoder().decode(WeatherReport.self, from: json)
        XCTAssertEqual(report.now.tempF, 46)
        XCTAssertEqual(report.periods.first?.name, "Tonight")
        XCTAssertEqual(report.periods.first?.tempF, 26)
    }
}
