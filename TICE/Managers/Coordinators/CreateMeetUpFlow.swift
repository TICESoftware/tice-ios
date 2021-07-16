//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Swinject
import SwinjectStoryboard
import UIKit
import PromiseKit

protocol MeetupCreationFlow: Coordinator {
    func done(meetup: Meetup)
    func cancel()
    func fail(error: Error?)
}

protocol CreateMeetupFlow: MeetupCreationFlow {
    var meetingPoint: LocationAnnotation? { get }

    func start(from group: Team, meetingPoint: LocationAnnotation?)
}

class CreateMeetupCoordinator: Coordinator {

    weak var parent: MainFlow?
    
    let window: UIWindow
    let storyboard: UIStoryboard
    let resolver: Swinject.Resolver

    let navigationController = UINavigationController()
    var meetingPoint: LocationAnnotation?

    var children: [Coordinator] = []

    let meetupManager: MeetupManagerType
    let signedInUser: SignedInUser

    let tracker: TrackerType

    init(meetupManager: MeetupManagerType, signedInUser: SignedInUser, parent: MainFlow, tracker: TrackerType) {
        self.parent = parent
        self.window = parent.window
        self.storyboard = parent.storyboard
        self.resolver = parent.resolver

        self.meetupManager = meetupManager
        self.signedInUser = signedInUser

        self.tracker = tracker
    }
}

extension CreateMeetupCoordinator: CreateMeetupFlow {

    func start(from group: Team, meetingPoint: LocationAnnotation?) {
        firstly {
            askForUserConfirmation(title: L10n.Team.ConfirmLocationSharing.title, message: L10n.Team.ConfirmLocationSharing.body)
        }.then {
            self.meetupManager.createMeetup(in: group, at: meetingPoint?.location.location, joinMode: .open, permissionMode: .everyone)
        }.done { meetup in
            self.done(meetup: meetup)
        }.catch(policy: .allErrors) { error in
            if error.isCancelled {
                self.cancel()
            } else {
                self.fail(error: error)
            }
        }
    }

    func cancel() {
        guard let parent = parent else {
            logger.debug("No parent for flow \(self)")
            return
        }

        parent.finish(createMeetupFlow: self)
    }

    func done(meetup: Meetup) {
        tracker.log(action: .createMeetup, category: .app)

        guard let parent = parent else {
            logger.debug("No parent for flow \(self)")
            return
        }
        
        parent.finish(createMeetupFlow: self)
    }

    func fail(error: Error?) {
        show(error: error)
    }
}
