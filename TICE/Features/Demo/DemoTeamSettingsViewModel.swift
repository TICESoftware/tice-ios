//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import PromiseKit
import Swinject

class DemoTeamSettingsViewModel: TeamSettingsViewModelType {
    
    weak var delegate: TeamSettingsViewController?
    
    let demoManager: DemoManagerType
    let tracker: TrackerType
    let coordinator: DemoFlow
    
    var team: DemoTeam { demoManager.demoTeam.wrappedValue }
    
    init(demoManager: DemoManagerType, tracker: TrackerType, coordinator: DemoFlow) {
        self.demoManager = demoManager
        self.tracker = tracker
        self.coordinator = coordinator
    }
    
    enum Section: Int, CaseIterable {
        case name = 0
        case members = 1
        case meetups = 2
        case manage = 3
    }
    
    func viewWillAppear() {
        delegate?.update()
    }
    
    var numberOfSections: Int {
        return Section.allCases.count
    }
    
    func section(for index: Int) -> Section {
        return Section(rawValue: index)!
    }
    
    func numberOfRowsIn(sectionIndex: Int) -> Int {
        let section = self.section(for: sectionIndex)
        
        switch section {
        case .name: return 1
        case .members: return team.members.count + 1
        case .meetups: return 1
        case .manage: return 1
        }
    }
    
    func cellType(for indexPath: IndexPath) -> TeamSettingsViewController.CellType {
        let section = self.section(for: indexPath.section)
        switch section {
        case .name: return .infoCell
        case .members: return .memberCell
        case .meetups: return .actionCell
        case .manage: return .actionCell
        }
    }
    
    func sectionHeader(for sectionIndex: Int) -> String? {
        guard numberOfRowsIn(sectionIndex: sectionIndex) > 0 else { return nil }
        
        let section = self.section(for: sectionIndex)
        
        switch section {
        case .name: return nil
        case .members: return L10n.GroupSettings.Members.header
        case .meetups: return L10n.GroupSettings.LocationSharing.header
        case .manage: return L10n.Demo.Manage.header
        }
    }
    
    func sectionFooter(for sectionIndex: Int) -> String? {
        guard numberOfRowsIn(sectionIndex: sectionIndex) > 0 else { return nil }
        
        let section = self.section(for: sectionIndex)
        
        switch section {
        case .name, .members, .meetups: return nil
        case .manage: return L10n.Demo.Manage.footer
        }
    }
    
    func infoCellViewModel(for indexPath: IndexPath) -> InfoTableViewCellViewModel {
        return InfoTableViewCellViewModel(title: L10n.GroupSettings.Name.name,
                                          value: team.name,
                                          shouldShowDisclosureIndicator: false)
    }
    
    func memberCellViewModel(for indexPath: IndexPath) -> MemberTableViewCellViewModelType {
        switch indexPath.row {
        case team.members.count:
            return ManualMemberTableViewCellViewModel(userName: L10n.Name.you.capitalized, avatar: UIImage(named: "person")!, subtitle: L10n.Group.Member.admin, isTouchable: false)
        default:
            let user = team.members[indexPath.row]
            return DemoMemberTableViewCellViewModel(demoManager: demoManager, user: user)
        }
    }
    
    func actionCellViewModel(for indexPath: IndexPath) -> ActionTableViewCellViewModel {
        let section = self.section(for: indexPath.section)
        switch section {
        case .manage:
            return ActionTableViewCellViewModel(title: L10n.Demo.Manage.endDemo,
                                                isDestructive: false,
                                                isEnabled: true,
                                                isLoading: false)
        case .meetups:
            let title = team.userSharingLocation ? L10n.GroupSettings.LocationSharing.stop : L10n.GroupSettings.LocationSharing.start
            return ActionTableViewCellViewModel(title: title, isDestructive: false, isEnabled: true, isLoading: false)
        default:
            fatalError("Not implemented")
        }
    }
    
    func didTapOnRow(at indexPath: IndexPath) {
        let section = self.section(for: indexPath.section)
        switch (section, indexPath.row, team.userSharingLocation) {
        case (.manage, _, _):
            tracker.log(action: .endDemo, category: .demo, detail: "Teams")
            demoManager.endDemo()
            coordinator.didDeleteTeam()
        case (.meetups, _, true):
            stopLocationSharing()
        case (.meetups, _, false):
            startLocationSharing()
        default:
            print("What happened?")
        }
    }
    
    private func stopLocationSharing() {
        demoManager.didEndLocationSharing()
        delegate?.update()
    }
    
    private func startLocationSharing() {
        firstly {
            coordinator.askForUserConfirmation(title: L10n.Team.StartLocationSharing.title, message: L10n.Team.StartLocationSharing.message)
        }.done {
            self.demoManager.didStartLocationSharing()
            self.delegate?.update()
        }.catch { error in
            self.coordinator.show(error: error)
        }
    }
}
