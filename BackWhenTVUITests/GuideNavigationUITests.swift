import XCTest

final class GuideNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGuideOpensWithTheRemoteAndChangesChannels() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        app.launch()

        // The app opens on the last tuned channel, WeatherStar by default.
        let weatherPages = NSPredicate(
            format: "label IN %@",
            ["CURRENT CONDITIONS", "LOCAL FORECAST", "EXTENDED FORECAST", "WEATHER ALERTS", "REGIONAL RADAR"]
        )
        XCTAssertTrue(
            app.staticTexts.matching(weatherPages).firstMatch.waitForExistence(timeout: 40),
            "The weather channel should tune itself in"
        )
        attachScreenshot(named: "01-weather-channel")

        // Menu opens the cable guide.
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(
            app.staticTexts["GUIDE"].waitForExistence(timeout: 8),
            "Pressing Menu should open the guide"
        )
        attachScreenshot(named: "02-guide")

        // Move two rows down and check the preview follows the focus.
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.down)
        attachScreenshot(named: "02b-guide-moved")

        XCUIRemote.shared.press(.select)

        XCTAssertTrue(
            app.staticTexts["GUIDE"].waitForNonExistence(timeout: 8),
            "Selecting a guide row should close the guide"
        )
        XCTAssertTrue(
            app.staticTexts["HOLIDAY TV"].waitForExistence(timeout: 15),
            "The banner should announce the newly tuned channel"
        )
        XCTAssertTrue(
            app.staticTexts["LOADING CHANNEL..."].waitForNonExistence(timeout: 75),
            "The loading card should go away once the stream starts or the next item rolls in"
        )
        attachScreenshot(named: "03-tuned-from-guide")

        // Channel surfing with the remote while the video is on screen.
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(
            app.staticTexts["WATERTOWER KIDS"].waitForExistence(timeout: 15),
            "Up should move to the next channel in the lineup"
        )
        XCTAssertTrue(
            app.staticTexts["LOADING CHANNEL..."].waitForNonExistence(timeout: 60),
            "The new channel should start playing before we pause it"
        )
        attachScreenshot(named: "04-channel-up")

        // Pause shows the state in the banner; resuming rejoins the live point.
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(
            app.staticTexts["PAUSED"].waitForExistence(timeout: 8),
            "Play/Pause should pause and show PAUSED on the banner"
        )
        attachScreenshot(named: "05-paused")
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(
            app.staticTexts["PAUSED"].waitForNonExistence(timeout: 10),
            "Pressing Play/Pause again should resume"
        )

        // Select also opens the guide, and Menu closes it.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            app.staticTexts["GUIDE"].waitForExistence(timeout: 8),
            "Select should open the guide while watching"
        )
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["GUIDE"].waitForNonExistence(timeout: 8))
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
