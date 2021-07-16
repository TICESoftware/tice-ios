//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import Cuckoo
import PromiseKit

@testable import TICE

class NotificationManagerTests: XCTestCase {

    var notificationCenter: MockUNUserNotificationCenterType!
    var pushReceiver: MockPushReceiverType!
    var storageManager: MockApplicationStorageManagerType!
    var deepLinkParser: MockDeepLinkParserType!

    var notificationManager: NotificationManager!
    
    var delegateShouldShowCallback: ((UNNotification) -> Bool)?
    var delegateDidOpenCallback: ((UNNotification) -> Void)?
    var delegateHandleDeepLinkCallback: ((AppState) -> Promise<Void>)?

    override func setUp() {
        super.setUp()

        notificationCenter = MockUNUserNotificationCenterType()
        pushReceiver = MockPushReceiverType()
        storageManager = MockApplicationStorageManagerType()
        deepLinkParser = MockDeepLinkParserType()

        notificationManager = NotificationManager(notificationCenter: notificationCenter, pushReceiver: pushReceiver, tracker: MockTracker(), deepLinkParser: deepLinkParser)
    }
    
    override func tearDown() {
        super.tearDown()
        
        delegateShouldShowCallback = nil
        delegateDidOpenCallback = nil
        delegateHandleDeepLinkCallback = nil
        
        notificationManager.notificationDelegate = nil
    }

    func testSetup() {
        stub(notificationCenter) { stub in
            when(stub.delegate.set(any())).thenDoNothing()
            when(stub.setNotificationCategories(any())).thenDoNothing()
        }
        
        notificationManager.setup()

        verify(notificationCenter).delegate.set(any())
        verify(notificationCenter).setNotificationCategories(any())
    }
    
    func testRequestAuthorizationAlreadyGranted() {
        stub(notificationCenter) { stub in
            when(stub.getNotificationSettings(completionHandler: any())).then { completion in
                let settings = MockUNNotificationSettings(authorizationStatus: .authorized, alertSetting: .enabled, badgeSetting: .enabled, soundSetting: .enabled)
                completion(settings)
            }
        }
        
        let completion = expectation(description: "Requested authorization")
        completion.isInverted = true

        notificationManager.requestAuthorization { granted in
            completion.fulfill()
        }

        wait(for: [completion])
        
        verify(notificationCenter).getNotificationSettings(completionHandler: any())
    }
    
    func testRequestAuthorizationAlreadyDenied() {
        stub(notificationCenter) { stub in
            when(stub.getNotificationSettings(completionHandler: any())).then { completion in
                let settings = MockUNNotificationSettings(authorizationStatus: .denied, alertSetting: .enabled, badgeSetting: .enabled, soundSetting: .enabled)
                completion(settings)
            }
        }
        
        let completion = expectation(description: "Requested authorization")
        completion.isInverted = true

        notificationManager.requestAuthorization { granted in
            completion.fulfill()
        }

        wait(for: [completion])
        
        verify(notificationCenter).getNotificationSettings(completionHandler: any())
    }
    
    func testRequestAuthorizationSettingsAlreadyEnabled() {
        stub(notificationCenter) { stub in
            when(stub.getNotificationSettings(completionHandler: any())).then { completion in
                let settings = MockUNNotificationSettings(authorizationStatus: .authorized, alertSetting: .disabled, badgeSetting: .enabled, soundSetting: .enabled)
                completion(settings)
            }
            when(stub.requestAuthorization(options: UNAuthorizationOptions([.alert, .sound, .badge]), completionHandler: any())).then { _, completion in
                completion(true, nil)
            }
        }
        
        let completion = expectation(description: "Requested authorization")

        notificationManager.requestAuthorization { granted in
            XCTAssertTrue(granted)
            completion.fulfill()
        }

        wait(for: [completion])
        
        verify(notificationCenter).getNotificationSettings(completionHandler: any())
        verify(notificationCenter).requestAuthorization(options: UNAuthorizationOptions([.alert, .sound, .badge]), completionHandler: any())
    }

    func testRequestAuthorizationGranted() {
        stub(notificationCenter) { stub in
            when(stub.getNotificationSettings(completionHandler: any())).then { completion in
                let settings = MockUNNotificationSettings(authorizationStatus: .notDetermined, alertSetting: .enabled, badgeSetting: .enabled, soundSetting: .enabled)
                completion(settings)
            }
            when(stub.requestAuthorization(options: UNAuthorizationOptions([.alert, .sound, .badge]), completionHandler: any())).then { _, completion in
                completion(true, nil)
            }
        }
        
        let completion = expectation(description: "Requested authorization")

        notificationManager.requestAuthorization { granted in
            XCTAssertTrue(granted)
            completion.fulfill()
        }

        wait(for: [completion])
        
        verify(notificationCenter).getNotificationSettings(completionHandler: any())
        verify(notificationCenter).requestAuthorization(options: UNAuthorizationOptions([.alert, .sound, .badge]), completionHandler: any())
    }
    
    func testRequestAuthorizationDenied() {
        stub(notificationCenter) { stub in
            when(stub.getNotificationSettings(completionHandler: any())).then { completion in
                let settings = MockUNNotificationSettings(authorizationStatus: .notDetermined, alertSetting: .enabled, badgeSetting: .enabled, soundSetting: .enabled)
                completion(settings)
            }
            when(stub.requestAuthorization(options: UNAuthorizationOptions([.alert, .sound, .badge]), completionHandler: any())).then { _, completion in
                completion(false, nil)
            }
        }
        
        let completion = expectation(description: "Requested authorization")

        notificationManager.requestAuthorization { granted in
            XCTAssertFalse(granted)
            completion.fulfill()
        }

        wait(for: [completion])
        
        verify(notificationCenter).getNotificationSettings(completionHandler: any())
        verify(notificationCenter).requestAuthorization(options: UNAuthorizationOptions([.alert, .sound, .badge]), completionHandler: any())
    }
    
    func testTriggerNotificationWithoutAuthorization() {
        let notificationRequestAdded = expectation(description: "Notification request added")
        notificationRequestAdded.isInverted = true
        
        stub(notificationCenter) { stub in
            when(stub.getNotificationSettings(completionHandler: any())).then { completion in
                let settings = MockUNNotificationSettings(authorizationStatus: .denied, alertSetting: .enabled, badgeSetting: .enabled, soundSetting: .enabled)
                completion(settings)
            }
            when(stub.add(any(), withCompletionHandler: any())).then { _, _ in
                notificationRequestAdded.fulfill()
            }
        }
        
        notificationManager.triggerNotification(title: "", body: "", state: .main(.demo), category: nil, userInfo: [:])
        
        wait(for: [notificationRequestAdded])
        
        verify(notificationCenter).getNotificationSettings(completionHandler: any())
    }
    
    func testTriggerNotificationWithAlertDisabled() {
        let notificationRequestAdded = expectation(description: "Notification request added")
        notificationRequestAdded.isInverted = true
        
        stub(notificationCenter) { stub in
            when(stub.getNotificationSettings(completionHandler: any())).then { completion in
                let settings = MockUNNotificationSettings(authorizationStatus: .authorized, alertSetting: .disabled, badgeSetting: .enabled, soundSetting: .enabled)
                completion(settings)
            }
            when(stub.add(any(), withCompletionHandler: any())).then { _, _ in
                notificationRequestAdded.fulfill()
            }
        }
        
        notificationManager.triggerNotification(title: "", body: "", state: .main(.demo), category: nil, userInfo: [:])
        
        wait(for: [notificationRequestAdded])
        
        verify(notificationCenter).getNotificationSettings(completionHandler: any())
    }
    
    func testTriggerNotification() {
        let title = "title"
        let body = "body"
        let userInfo = ["key": "value"]
        
        let url = URL(string: "http://example.com")!
        
        stub(deepLinkParser) { stub in
            when(stub.deepLink(state: AppState.main(.demo))).thenReturn(url)
        }
        
        let notificationRequestAdded = expectation(description: "Notification request added")
        stub(notificationCenter) { stub in
            when(stub.getNotificationSettings(completionHandler: any())).then { completion in
                let settings = MockUNNotificationSettings(authorizationStatus: .authorized, alertSetting: .enabled, badgeSetting: .enabled, soundSetting: .enabled)
                completion(settings)
            }
            when(stub.add(any(), withCompletionHandler: any())).then { request, completion in
                XCTAssertEqual(request.content.title, title)
                XCTAssertEqual(request.content.body, body)
                XCTAssertEqual(request.content.sound, .default)
                XCTAssertEqual(request.content.userInfo["key"] as! String, "value")
                XCTAssertEqual(request.content.userInfo["type"] as! String, "local")
                XCTAssertEqual(request.content.userInfo["url"] as! String, url.absoluteString)
                
                notificationRequestAdded.fulfill()
                completion?(nil)
            }
        }
        
        notificationManager.triggerNotification(title: title, body: body, state: .main(.demo), category: nil, userInfo: userInfo)
        
        wait(for: [notificationRequestAdded])
        
        verify(notificationCenter).getNotificationSettings(completionHandler: any())
    }
    
    func testPendingNotifications() {
        let request = UNNotificationRequest(identifier: "id", content: UNNotificationContent(), trigger: nil)
        
        stub(notificationCenter) { stub in
            when(stub.getPendingNotificationRequests(completionHandler: any())).then { completion in
                completion([request])
            }
        }
        
        let exp = expectation(description: "Completion")
        
        firstly {
            notificationManager.pendingNotifications()
        }.done { requests in
            XCTAssertEqual(requests, [request])
        }.catch {
            XCTFail($0.localizedDescription)
        }.finally {
            exp.fulfill()
        }
        
        wait(for: [exp])
    }
    
    func testRemovePendingNotifications() {
        let identifiers = ["id1", "id2"]
        
        stub(notificationCenter) { stub in
            when(stub.removePendingNotificationRequests(withIdentifiers: identifiers)).thenDoNothing()
        }
        
        notificationManager.removePendingNotifications(with: identifiers)
        
        verify(notificationCenter).removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    func testRemoveAllPendingNotifications() {
        stub(notificationCenter) { stub in
            when(stub.removeAllPendingNotificationRequests()).thenDoNothing()
        }
        
        notificationManager.removeAllPendingNotifications()
        
        verify(notificationCenter).removeAllPendingNotificationRequests()
    }
    
    func testWillPresentRemoteNotification() {
        let exp = expectation(description: "Completion")
        
        let content = UNMutableNotificationContent()
        content.userInfo = ["key": "value"]
        let request = UNNotificationRequest(identifier: "identifier", content: content, trigger: nil)
        let notification = MockUNNotification(date: Date(), request: request)
        
        stub(pushReceiver) { stub in
            when(stub.didReceiveRemoteNotification(userInfo: any(), fetchCompletionHandler: any())).then { userInfo, completionHandler in
                XCTAssertEqual(userInfo as! [String: String], content.userInfo as! [String: String])
                XCTAssertNil(completionHandler)
            }
        }
        
        notificationManager.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: notification) { options in
            XCTAssertTrue(options.isEmpty)
            exp.fulfill()
        }
        
        wait(for: [exp])
        
        verify(pushReceiver).didReceiveRemoteNotification(userInfo: any(), fetchCompletionHandler: any())
    }
    
    func testWillPresentLocalNotificationShouldShow() {
        let exp = expectation(description: "Completion")
        
        let content = UNMutableNotificationContent()
        content.userInfo = ["type": "local"]
        let request = UNNotificationRequest(identifier: "identifier", content: content, trigger: nil)
        let notification = MockUNNotification(date: Date(), request: request)
        
        let delegateAsked = expectation(description: "Delegate asked")
        delegateShouldShowCallback = { notification in
            delegateAsked.fulfill()
            return true
        }
        
        notificationManager.notificationDelegate = self
        notificationManager.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: notification) { options in
            XCTAssertEqual(options, [.alert, .sound, .badge])
            exp.fulfill()
        }
        
        wait(for: [exp, delegateAsked])
    }
    
    func testWillPresentLocalNotificationShouldNotShow() {
        let exp = expectation(description: "Completion")
        
        let content = UNMutableNotificationContent()
        content.userInfo = ["type": "local"]
        let request = UNNotificationRequest(identifier: "identifier", content: content, trigger: nil)
        let notification = MockUNNotification(date: Date(), request: request)
        
        let delegateAsked = expectation(description: "Delegate asked")
        delegateShouldShowCallback = { presentedNotification in
            XCTAssertEqual(presentedNotification, notification)
            delegateAsked.fulfill()
            return false
        }
        
        notificationManager.notificationDelegate = self
        notificationManager.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: notification) { options in
            XCTAssertTrue(options.isEmpty)
            exp.fulfill()
        }
        
        wait(for: [exp, delegateAsked])
    }
    
    func testReceivedNotificationResponseWithoutRegisteredHandler() {
        let exp = expectation(description: "Completion")
        
        let actionIdentifier = UNNotificationDefaultActionIdentifier
        
        let content = UNMutableNotificationContent()
        content.userInfo = ["type": "local"]
        let request = UNNotificationRequest(identifier: "identifier", content: content, trigger: nil)
        let notification = MockUNNotification(date: Date(), request: request)
        let response = MockUNNotificationResponse(notification: notification, actionIdentifier: actionIdentifier)
        
        let delegateAsked = expectation(description: "Delegate asked")
        delegateDidOpenCallback = { presentedNotification in
            XCTAssertEqual(presentedNotification, notification)
            delegateAsked.fulfill()
        }
        
        notificationManager.notificationDelegate = self
        notificationManager.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: response) {
            exp.fulfill()
        }
        
        wait(for: [exp, delegateAsked])
    }
    
    func testReceivedNotificationResponseWithRegisteredHandler() {
        let exp = expectation(description: "Completion")
        
        let action = NotificationAction.join
        let actionIdentifier = action.rawValue
        let state = AppState.main(.demo)
        
        let handlerCalled = expectation(description: "Handler called")
        notificationManager.handlers[action] = { notification in
            handlerCalled.fulfill()
            return Promise.value(state)
        }
        
        let delegateAsked = expectation(description: "Delegate asked")
        delegateHandleDeepLinkCallback = { toState in
            XCTAssertEqual(toState, state)
            delegateAsked.fulfill()
            return Promise()
        }
        
        let content = UNMutableNotificationContent()
        content.userInfo = ["type": "local"]
        let request = UNNotificationRequest(identifier: "identifier", content: content, trigger: nil)
        let notification = MockUNNotification(date: Date(), request: request)
        let response = MockUNNotificationResponse(notification: notification, actionIdentifier: actionIdentifier)
        
        notificationManager.notificationDelegate = self
        notificationManager.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: response) {
            exp.fulfill()
        }
        
        wait(for: [exp, delegateAsked, handlerCalled])
    }
}

extension NotificationManagerTests: NotificationDelegate {
    func shouldShow(notification: UNNotification) -> Bool {
        delegateShouldShowCallback!(notification)
    }
    
    func didOpen(notification: UNNotification) {
        delegateDidOpenCallback!(notification)
    }
    
    func handleDeepLink(to state: AppState) -> Promise<Void> {
        delegateHandleDeepLinkCallback!(state)
    }
}
