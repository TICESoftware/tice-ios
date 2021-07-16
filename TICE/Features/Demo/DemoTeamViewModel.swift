//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Observable
import TICEAPIModels
import Chatto

class DemoTeamViewModel: TeamViewModelType {
    
    let demoManager: DemoManagerType
    let notifier: Notifier
    
    let coordinator: DemoFlow
    
    weak var delegate: TeamViewController?
    
    var team: DemoTeam { demoManager.demoTeam.wrappedValue }
    
    var title: String { team.name }
    
    var teamAvatar: UIImage { demoManager.teamAvatar }
    
    init(demoManager: DemoManagerType, notifier: Notifier, coordinator: DemoFlow) {
        self.demoManager = demoManager
        self.notifier = notifier
        self.coordinator = coordinator
    }
    
    func didEnter() {
        demoManager.didOpenTeam()
    }
    
    func didLeave() {
        demoManager.didCloseTeam()
    }
    
    func didTapInfo() {
        demoManager.didOpenTeamSettings()
        coordinator.showTeamSettingsScreen()
    }
}
