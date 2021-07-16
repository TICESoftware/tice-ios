//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import PromiseKit
import TICEAPIModels
import Observable
import CoreLocation

enum DemoManagerError: CancellableError {
    case paused
}

class DemoManager: DemoManagerType {
    
    private let storage: DemoStorageManagerType
    private let notifier: Notifier
    private let tracker: TrackerType
    
    private var state: DemoManagerState {
        didSet {
            try? storage.store(state: state)
            demoTeamSubject.wrappedValue = state.team
            if state.step != oldValue.step {
                tracker.log(action: TrackerAction.changeDemoState(step: state.step, previousStep: oldValue.step), category: .demo)
            }
            switch state.step {
            case .inactive, .notOpened, .opened, .chatOpened, .teamDeleted: showMeetupButtonSubject.wrappedValue = false
            default: showMeetupButtonSubject.wrappedValue = true
            }
        }
    }
    
    private var promise: Promise<Void>?
    private var paused: Bool = true
    
    init(storage: DemoStorageManagerType, notifier: Notifier, tracker: TrackerType) {
        self.storage = storage
        self.notifier = notifier
        self.tracker = tracker
        
        self.messages = []
        
        do {
            self.state = try storage.load() ?? .initial
        } catch {
            logger.error("Could not load demo state. Reason: \(error)")
            self.state = .initial
        }
        
        self.messages = messages(upTo: state.step)
    }

    var messages: [DemoMessage]
    
    lazy var demoTeam: Observable<DemoTeam> = demoTeamSubject.asObservable()
    private lazy var demoTeamSubject: MutableObservable<DemoTeam> = .init(state.team)
    
    var lastLocation: Coordinate? {
        get {
            return state.team.location
        }
        set {
            state.team.location = newValue
        }
    }
    
    var isDemoEnabled: Bool {
        switch state.step {
        case .teamDeleted, .inactive:
            return false
        default:
            return true
        }
    }
    
    private var locationSharingStatesSubject: MutableObservable<[LocationSharingState]> = .init([])
    lazy var locationSharingStates: Observable<[LocationSharingState]> = locationSharingStatesSubject.asObservable()
    
    private var showMeetupButtonSubject: MutableObservable<Bool> = .init(false)
    lazy var showMeetupButton: Observable<Bool> = showMeetupButtonSubject.asObservable()
    
    var memberLocations: Set<MemberLocation> {
        return Set(state.team.members.map { user in
            let location = lastLocation(userId: user.userId)
            return MemberLocation(userId: user.userId, lastLocation: location)
        })
    }
    
    var teamAvatar: UIImage {
        return UIImage(named: "teamAvatar")!
    }
    
    func lastLocation(userId: UserId) -> Location? {
        guard let user = demoUser(userId: userId),
              let startedTimestamp = user.startedLocationSharing,
              let teamLocation = demoTeam.wrappedValue.location else {
            return nil
        }
        
        let baseAngle: Double
        switch user {
        case state.team.userOne: baseAngle = 70
        case state.team.userTwo: baseAngle = 250
        default: fatalError()
        }
        
        let timeDelta = -startedTimestamp.timeIntervalSinceNow
        let angle = baseAngle + sin(timeDelta * 0.1)
        let distance = 1000.0 + cos(timeDelta * 0.1) * 30.0
        let location = projecting(point: teamLocation, angle: angle, meters: distance)
        
        return Location(coordinate: CLLocationCoordinate2D(location), altitude: 0.0, horizontalAccuracy: 3.0, verticalAccuracy: 3.0, timestamp: Date())
    }
    
    func demoUser(userId: UserId) -> DemoUser? {
        switch userId {
        case state.team.userOne.userId: return state.team.userOne
        case state.team.userTwo.userId: return nil
        default: return nil
        }
    }
    
    func avatar(demoUser: DemoUser) -> UIImage {
        switch demoUser {
        case state.team.userOne: return UIImage(named: "demoUserOne")!
        case state.team.userTwo: return UIImage(named: "demoUserTwo")!
        default:
            logger.error("Avatar for unkown demo user \(demoUser).")
            return UIImage(named: "person")!
        }
    }
    
    private func messages(upTo upToState: DemoManagerStep) -> [DemoMessage] {
        let allMessagesUpToState = DemoManagerStep.allCases.filter { $0 <= upToState }.compactMap { message(for: $0) }
        return allMessagesUpToState
    }
    
    private func message(for step: DemoManagerStep, sender: DemoUser? = nil) -> DemoMessage? {
        switch step {
        case .opened:
            return DemoMessage(sender: sender ?? state.team.userOne, text: L10n.Demo.Message.opened)
        case .chatOpened:
            return DemoMessage(sender: sender ?? state.team.userOne, text: L10n.Demo.Message.chatOpened, read: true)
        case .chatClosed:
            return DemoMessage(sender: sender ?? state.team.userOne, text: L10n.Demo.Message.chatClosed)
        case .locationSharingEndedPrematurely:
            return DemoMessage(sender: sender ?? state.team.userOne, text: L10n.Demo.Message.locationSharingEndedPrematurely)
        case .locationSharingStarted:
            return DemoMessage(sender: sender ?? state.team.userOne, text: L10n.Demo.Message.locationSharingStarted)
        case .locationMarked:
            return DemoMessage(sender: sender ?? state.team.userOne, text: L10n.Demo.Message.locationMarked)
        case .meetingPointCreated:
            return DemoMessage(sender: sender ?? state.team.userOne, text: L10n.Demo.Message.meetingPointCreated)
        case .userSelected:
            return DemoMessage(sender: sender ?? state.team.userOne, text: L10n.Demo.Message.userSelected)
        case .locationSharingEnded:
            return DemoMessage(sender: sender ?? state.team.userOne, text: L10n.Demo.Message.locationSharingEnded)
        default:
            return nil
        }
    }
    
    private func checkPaused() -> Promise<Void> {
        guard !paused else {
            return .init(error: DemoManagerError.paused)
        }
        
        return .init()
    }
    
    private func sendMessageForCurrentState(sender: DemoUser? = nil) {
        guard let messageForCurrentState = message(for: state.step, sender: sender) else { return }
        send(message: messageForCurrentState)
    }
    
    private func send(message: DemoMessage) {
        messages.append(message)
        notifier.notify(DemoMessageNotificationHandler.self) { $0.didReceive(message: message) }
    }
    
    private func startDemoUserLocationSharing() {
        let location = lastLocation ?? Coordinate(latitude: 52.0, longitude: 13.0)
        state.team.demoUsersSharingLocation = true
        state.team.location = location
        state.team.userOne.startedLocationSharing = Date()
        state.team.userTwo.startedLocationSharing = Date()
        
        locationSharingStatesSubject.wrappedValue = state.team.members.map { LocationSharingState(userId: $0.userId, groupId: state.team.groupId, enabled: true, lastUpdated: Date()) }
    }
    
    private func projecting(point: Coordinate, angle: Double, meters: Double) -> Coordinate {
        let earthRadius = 6_370_994.0
        let dx = meters * cos(angle * .pi / 180)
        let dy = meters * sin(angle * .pi / 180)
        let newLatitude = point.latitude + (dy / earthRadius) * (180 / .pi)
        let newLongitude = point.longitude + (dx / earthRadius) * (180 / .pi) / cos(point.latitude * .pi / 180)
        return Coordinate(latitude: newLatitude, longitude: newLongitude)
    }
    
    func didRegister() {
        if state.step != .inactive {
            logger.warning("Did register but demo was in state \(state.step). This should not happen. Resetting state.")
            state = .initial
        }
        
        state.step = .notOpened
    }
    
    func didOpenTeam() {
        tracker.log(action: .unpause, category: .demo, detail: state.step.description)
        paused = false
        
        switch state.step {
        case .notOpened:
            state.step = .opened
            after(seconds: 0.5).then(self.checkPaused).done {
                self.sendMessageForCurrentState()
            }.cauterize()
        default:
            guard let lastMessage = messages.last else { return }
            self.notifier.notify(DemoMessageNotificationHandler.self) { $0.didReceive(message: lastMessage) }
        }
    }
    
    func didCloseTeam() {
        tracker.log(action: .pause, category: .demo, detail: state.step.description)
        paused = true
    }
    
    func didOpenChat() {
        switch state.step {
        case .opened:
            state.step = .chatOpened
            
            for message in self.messages {
                notifier.notify(DemoMessageNotificationHandler.self) { $0.didRead(message: message) }
            }
            
            after(seconds: 0.5).done {
                self.sendMessageForCurrentState()
                self.startDemoUserLocationSharing()
            }
        default:
            break
        }
    }
    
    func didCloseChat() {
        switch state.step {
        case .chatOpened:
            state.step = .chatClosed
            sendMessageForCurrentState()
        default:
            break
        }
    }
    
    func didStartLocationSharing() {
        switch state.step {
        case .chatClosed, .locationSharingEndedPrematurely:
            state.step = .locationSharingStarted
            state.team.userSharingLocation = true
            sendMessageForCurrentState()
        case .locationSharingEnded:
            state.team.userSharingLocation = true
        default:
            break
        }
    }
    
    func didMarkLocation() {
        switch state.step {
        case .locationSharingStarted:
            state.step = .locationMarked
            sendMessageForCurrentState()
        default:
            break
        }
    }
    
    func didHideAnnotation() {
        switch state.step {
        case .locationMarked:
            state.step = .locationSharingStarted
            sendMessageForCurrentState()
        default:
            break
        }
    }
    
    func didCreateMeetingPoint(location: CLLocationCoordinate2D) {
        state.team.meetingPoint = Coordinate(location)
        
        switch state.step {
        case .locationSharingStarted, .locationMarked:
            state.step = .meetingPointCreated
            sendMessageForCurrentState()
        default:
            break
        }
    }
    
    func didDeleteMeetingPoint() {
        state.team.meetingPoint = nil
    }
    
    func didEndLocationSharing() {
        state.team.userSharingLocation = false
        
        switch state.step {
        case .locationSharingStarted, .meetingPointCreated:
            state.step = .locationSharingEndedPrematurely
            sendMessageForCurrentState()
        case .userSelected:
            state.step = .locationSharingEnded
            sendMessageForCurrentState()
        default:
            break
        }
    }
    
    func didOpenTeamSettings() {
        
    }
    
    func didSelectUser(user: DemoUser) {
        switch state.step {
        case .meetingPointCreated:
            state.step = .userSelected
            sendMessageForCurrentState(sender: user)
        default:
            break
        }
    }
    
    func resetDemo() {
        messages = []
        state = .initial
        didRegister()
    }
    
    func endDemo() {
        state.step = .teamDeleted
    }
}

protocol DemoMessageNotificationHandler {
    func didReceive(message: DemoMessage)
    func didRead(message: DemoMessage)
}
