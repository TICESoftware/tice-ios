//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import PromiseKit

@testable import TICE

class UpdateCheckerTests: XCTestCase {
    func testCheckFails() {

        let backendURL = URL(string: "http://example.org")!
        let mockAPI = MockAPI { (method, requestBaseURL, resource, _, _, _) in
            XCTAssertEqual(method, .GET)
            XCTAssertEqual(requestBaseURL, backendURL)
            XCTAssertEqual(resource, "/")
            throw APIError(type: .internalServerError)
        }

        let completion = self.expectation(description: "Call should complete")
        let updateChecker = UpdateChecker(backendURL: backendURL, api: mockAPI, currentVersion: 1)
        updateChecker.check().done {
            XCTFail()
        }.catch { error in
            // yay.
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testCheckSucceeds() {

        let serverInformation = ServerInformationResponse(deployedAt: Date(),
                                                          deployedCommit: "8ce13e45c40f42f2c609ca6907b993328629f3bf",
                                                          env: "test",
                                                          minVersion: MinVersion(iOS: 28))

        let backendURL = URL(string: "http://example.org")!
        let mockAPI = MockAPI { (method, requestBaseURL, resource, _, _, _) -> Any? in
            XCTAssertEqual(method, .GET)
            XCTAssertEqual(requestBaseURL, backendURL)
            XCTAssertEqual(resource, "/")
            return serverInformation
        }

        let completion = self.expectation(description: "Call should complete")
        let updateChecker = UpdateChecker(backendURL: backendURL, api: mockAPI, currentVersion: 28)

        firstly { () -> Promise<Void> in
            updateChecker.check()
        }.catch { error in
            XCTFail(error.localizedDescription)
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testCheckMinVersionNotReached() {

        let serverInformation = ServerInformationResponse(deployedAt: Date(),
                                                          deployedCommit: "8ce13e45c40f42f2c609ca6907b993328629f3bf",
                                                          env: "test",
                                                          minVersion: MinVersion(iOS: 28))
        let backendURL = URL(string: "http://example.org")!
        let mockAPI = MockAPI { (method, requestBaseURL, resource, _, _, _) -> Any? in
            XCTAssertEqual(method, .GET)
            XCTAssertEqual(requestBaseURL, backendURL)
            XCTAssertEqual(resource, "/")
            return serverInformation
        }

        let completion = self.expectation(description: "Call should complete")
        let updateChecker = UpdateChecker(backendURL: backendURL, api: mockAPI, currentVersion: 27)

        firstly { () -> Promise<Void> in
            updateChecker.check()
        }.done {
            XCTFail("Should not be called")
        }.catch { error in
            guard let updateCheckerError = error as? UpdateCheckerError,
                case UpdateCheckerError.outdated(let minVersion) = updateCheckerError else {
                return XCTFail("Unknown error: \(error)")
            }

            XCTAssertEqual(minVersion, 28)
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }
}
