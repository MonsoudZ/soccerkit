import XCTest

/// Launches the real app and drives the main navigation. This is the guard that
/// would have caught the missing-environment-object crash: any trap on launch or
/// while switching tabs fails the test instead of shipping.
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
        return app
    }

    func testLaunchesToTabBar() {
        let app = launchApp()
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 20),
            "App should launch to the tab bar without crashing"
        )
    }

    func testCoreTabsExistAndAreNavigable() {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20))

        for tab in ["Home", "Calendar", "Roster", "Game Day", "More"] {
            XCTAssertTrue(tabBar.buttons[tab].exists, "Missing tab: \(tab)")
        }

        // Switching tabs must not crash (the regression was in this path).
        tabBar.buttons["Roster"].tap()
        tabBar.buttons["Calendar"].tap()
        tabBar.buttons["More"].tap()
        tabBar.buttons["Home"].tap()
        XCTAssertTrue(tabBar.buttons["Home"].isSelected)
    }

    func testMoreTabOpensCustomizeTabs() {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20))

        tabBar.buttons["More"].tap()
        let customize = app.buttons["Customize Tabs"].firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 5), "More tab should offer Customize Tabs")
    }
}
