//
//  ChitalUITests.swift
//  ChitalUITests
//
//  Created by Justin Neuhard on 4/11/25.
//

import XCTest

final class ChitalUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it's important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    func testStopButtonCancelsStream() throws {
        let app = XCUIApplication()
        app.launch()

        let inputTextField = app.textFields["chatInputTextField"]
        let cancelButton = app.buttons["cancelStreamingButton"]

        XCTAssertTrue(inputTextField.waitForExistence(timeout: 5), "Chat input text field should exist.")
        inputTextField.click()
        inputTextField.typeText("Tell me a short story about a planet made of cheese.")
        inputTextField.typeText("\r") // Simulate Enter press

        XCTAssertTrue(cancelButton.waitForExistence(timeout: 10), "Cancel button should appear after submitting.")
        
        cancelButton.click()

        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: cancelButton
        )
        wait(for: [expectation], timeout: 5)
        XCTAssertFalse(cancelButton.exists, "Cancel button should disappear after being clicked.")

        sleep(1) // Allow UI state to settle
        XCTAssertTrue(inputTextField.isEnabled, "Text field should be enabled after cancellation.")
        XCTAssertFalse(app.alerts["Error"].exists, "Error alert should not appear after cancellation.")
    }
}

// Extension to allow typing Enter key easily (keep if needed)
// extension XCUIElement {
//     func typeEnter() {
//         typeKey(.enter, modifierFlags: [])
//     }
// }
