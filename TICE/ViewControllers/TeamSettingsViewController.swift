//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import PromiseKit
import Swinject

class TeamSettingsViewController: UITableViewController {

    enum CellType: String {
        case infoCell
        case memberCell
        case actionCell
    }

    var viewModel: TeamSettingsViewModelType! {
        didSet {
            viewModel.delegate = self
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.viewWillAppear()
    }

    func update() {
        tableView.reloadData()
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
    }

    // MARK: UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.numberOfSections
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.numberOfRowsIn(sectionIndex: section)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellType = viewModel.cellType(for: indexPath)
        
        switch cellType {
        case .infoCell:
            // swiftlint:disable:next force_cast
            let cell = tableView.dequeueReusableCell(withIdentifier: cellType.rawValue, for: indexPath) as! InfoTableViewCell
            cell.viewModel = viewModel.infoCellViewModel(for: indexPath)
            return cell
        case .memberCell:
            // swiftlint:disable:next force_cast
            let cell = tableView.dequeueReusableCell(withIdentifier: cellType.rawValue, for: indexPath) as! MemberTableViewCell
            cell.viewModel = viewModel.memberCellViewModel(for: indexPath)
            return cell
        case .actionCell:
            // swiftlint:disable:next force_cast
            let cell = tableView.dequeueReusableCell(withIdentifier: cellType.rawValue, for: indexPath) as! ActionTableViewCell
            cell.viewModel = viewModel.actionCellViewModel(for: indexPath)
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return viewModel.sectionHeader(for: section)
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return viewModel.sectionFooter(for: section)
    }

    // MARK: UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        viewModel.didTapOnRow(at: indexPath)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let cellType = viewModel.cellType(for: indexPath)
        switch cellType {
        case .memberCell:
            return 56
        default:
            return 44
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            return 18
        }

        return UITableView.automaticDimension
    }
}

protocol TeamSettingsViewModelType {
    
    var delegate: TeamSettingsViewController? { get set }
    
    var numberOfSections: Int { get }
    
    func viewWillAppear()

    func numberOfRowsIn(sectionIndex: Int) -> Int

    func sectionHeader(for sectionIndex: Int) -> String?
    func sectionFooter(for sectionIndex: Int) -> String?

    func cellType(for indexPath: IndexPath) -> TeamSettingsViewController.CellType
    func infoCellViewModel(for indexPath: IndexPath) -> InfoTableViewCellViewModel
    func memberCellViewModel(for indexPath: IndexPath) -> MemberTableViewCellViewModelType
    func actionCellViewModel(for indexPath: IndexPath) -> ActionTableViewCellViewModel
    
    func didTapOnRow(at indexPath: IndexPath)
}

class TeamSettingsViewModel: TeamSettingsViewModelType {
    
    unowned let coordinator: MainFlow
    
    let signedInUser: SignedInUser
    let resolver: Swinject.Resolver
    let teamManager: TeamManagerType
    let locationSharingManager: LocationSharingManagerType
    let groupStorageManager: GroupStorageManagerType
    let nameSupplier: NameSupplierType
    let notifier: Notifier
    let tracker: TrackerType

    var team: Team

    var members: [Member]
    var admin: Bool
    var locationSharingStates: [LocationSharingState]

    weak var delegate: TeamSettingsViewController?

    var creatingMeetup = false
    
    private var teamObserverToken: ObserverToken?
    private var locationSharingStateObserverToken: ObserverToken?
    
    private var foregroundTransitionObserverToken: NSObjectProtocol?

    init(coordinator: MainFlow, signedInUser: SignedInUser, resolver: Swinject.Resolver, teamManager: TeamManagerType, locationSharingManager: LocationSharingManagerType, groupStorageManager: GroupStorageManagerType, nameSupplier: NameSupplierType, notifier: Notifier, tracker: TrackerType, group: Team, members: [Member], admin: Bool, locationSharingStates: [LocationSharingState]) {
        self.coordinator = coordinator
        self.signedInUser = signedInUser
        self.resolver = resolver
        self.teamManager = teamManager
        self.locationSharingManager = locationSharingManager
        self.groupStorageManager = groupStorageManager
        self.nameSupplier = nameSupplier
        self.notifier = notifier
        self.tracker = tracker

        self.team = group
        self.members = members
        self.admin = admin
        self.locationSharingStates = locationSharingStates

        teamObserverToken = groupStorageManager.observeTeam(groupId: self.team.groupId, queue: .main) { [unowned self] team, members in
            guard let team = team else { return }
            self.team = team
            self.members = members
            self.locationSharingStates = self.locationSharingManager.locationSharingStates(groupId: team.groupId)
            self.reloadSynchronously()
        }
        
        locationSharingStateObserverToken = locationSharingManager.observeLocationSharingState(groupId: team.groupId, queue: .main, onChange: { [unowned self] states in
            self.locationSharingStates = states
            self.reloadSynchronously()
        })
        
        foregroundTransitionObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [unowned self] _ in self.handleForegroundTransition() }
    }

    deinit {
        teamObserverToken = nil
        locationSharingStateObserverToken = nil
        
        foregroundTransitionObserverToken.map { NotificationCenter.default.removeObserver($0) }
    }

    enum Section: Int, CaseIterable {
        case name = 0
        case members = 1
        case meetups = 2
        case participation = 3
    }

    var numberOfSections: Int { return Section.allCases.count }
    
    var ownLocationSharingState: LocationSharingState {
        guard let locationSharingState = locationSharingStates.first(where: { $0.userId == self.signedInUser.userId }) else {
            let locationSharingState = locationSharingManager.locationSharingState(userId: signedInUser.userId, groupId: team.groupId)
            locationSharingStates.append(locationSharingState)
            return locationSharingState
        }
        return locationSharingState
    }
    
    func viewWillAppear() {
        delegate?.update()
    }

    func numberOfRowsIn(sectionIndex: Int) -> Int {
        guard let section = Section(rawValue: sectionIndex) else {
            assertionFailure("Invalid section: \(sectionIndex)")
            return 0
        }

        switch section {
        case .name: return 1
        case .members: return members.count + 1
        case .meetups: return 1
        case .participation:
            if admin {
                return 2
            } else {
                return 1
            }
        }
    }

    func cellType(for indexPath: IndexPath) -> TeamSettingsViewController.CellType {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Invalid section: \(indexPath.section)")
        }

        switch section {
        case .name: return .infoCell
        case .members: return indexPath.row < members.count ? .memberCell : .actionCell
        case .meetups: return .actionCell
        case .participation: return .actionCell
        }
    }

    private enum InfoCellType: Int {
        case name
    }

    private enum ParticipationCellType: Int {
        case leave
        case delete
    }

    private func infoCellType(for row: Int) -> InfoCellType {
        return InfoCellType(rawValue: row)!
    }

    private func participationCellType(for row: Int) -> ParticipationCellType {
        if admin {
            return ParticipationCellType(rawValue: row)!
        } else {
            return .leave
        }
    }

    func sectionHeader(for sectionIndex: Int) -> String? {
        guard let section = Section(rawValue: sectionIndex) else {
            assertionFailure("Invalid section: \(sectionIndex)")
            return nil
        }

        switch section {
        case .name: return nil
        case .members: return L10n.GroupSettings.Members.header
        case .meetups: return L10n.GroupSettings.LocationSharing.header
        case .participation: return L10n.GroupSettings.Participation.header
        }
    }
    
    func sectionFooter(for sectionIndex: Int) -> String? {
        return nil
    }

    func infoCellViewModel(for indexPath: IndexPath) -> InfoTableViewCellViewModel {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Invalid section: \(indexPath.section)")
        }

        switch section {
        case .name:
            switch infoCellType(for: indexPath.row) {
            case .name:
                return InfoTableViewCellViewModel(title: L10n.GroupSettings.Name.name,
                                                  value: nameSupplier.name(team: team),
                                                  shouldShowDisclosureIndicator: true)
            }
        default:
            fatalError()
        }
    }

    func memberCellViewModel(for indexPath: IndexPath) -> MemberTableViewCellViewModelType {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Invalid section: \(indexPath.section)")
        }

        switch section {
        case .members:
            let member = members[indexPath.row]
            let isTouchable = member.user != signedInUser && admin
            let isSharingLocation = isSharingLocation(userId: member.user.userId)
            return resolver.resolve(MemberTableViewCellViewModel.self, arguments: member.user, isTouchable, member.membership.admin, isSharingLocation)!
        default:
            fatalError("Invalid section")
        }
    }

    func actionCellViewModel(for indexPath: IndexPath) -> ActionTableViewCellViewModel {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Invalid section: \(indexPath.section)")
        }

        switch section {
        case .members:
            return ActionTableViewCellViewModel(title: L10n.GroupSettings.Members.add, isDestructive: false)
        case .meetups:
            return locationSharingCellViewModel()
        case .participation:
            return participationCellViewModel(at: indexPath.row)
        default:
            fatalError("Invalid section")
        }
    }
    
    func isSharingLocation(userId: UserId) -> Bool {
        return locationSharingStates.first { $0.userId == userId }?.enabled ?? false
    }

    func locationSharingCellViewModel() -> ActionTableViewCellViewModel {
        if ownLocationSharingState.enabled {
            return ActionTableViewCellViewModel(title: L10n.GroupSettings.LocationSharing.stop, isDestructive: false, isEnabled: true, isLoading: false)
        } else {
            return ActionTableViewCellViewModel(title: L10n.GroupSettings.LocationSharing.start, isDestructive: false, isEnabled: true, isLoading: false)
        }
    }

    func participationCellViewModel(at row: Int) -> ActionTableViewCellViewModel {
        let cellType = participationCellType(for: row)
        switch cellType {
        case .leave:
            return ActionTableViewCellViewModel(title: L10n.GroupSettings.Participation.leave, isDestructive: true, isEnabled: !admin, isLoading: isLeaving)
        case .delete:
            return ActionTableViewCellViewModel(title: L10n.GroupSettings.Participation.delete, isDestructive: true, isLoading: isDeleting)
        }
    }

    func didTapOnRow(at indexPath: IndexPath) {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Invalid section: \(indexPath.section)")
        }

        switch (section, indexPath.row) {
        case (.name, 0):
            coordinator.changeTeamName(for: team)
        case (.members, members.count):
            coordinator.showShareScreen(for: team)
        case (.members, let row):
            let member = members[row]
            didTapOnMember(member: member)
        case (.meetups, 0):
            didTapOnLocationSharingAction()
        case (.participation, let row):
            let cellType = participationCellType(for: row)
            switch cellType {
            case .leave:
                didTapOnLeaveButton()
            case .delete:
                didTapOnDeleteButton()
            }
        default:
            return
        }
    }

    var isLeaving: Bool = false {
        didSet {
            if isLeaving != oldValue {
                delegate?.tableView.reloadData()
            }
        }
    }
    var isDeleting: Bool = false {
        didSet {
            if isDeleting != oldValue {
                delegate?.tableView.reloadData()
            }
        }
    }

    func didTapOnLeaveButton() {
        guard !isLeaving && !isDeleting else { return }

        isLeaving = true
        firstly {
            self.coordinator.askForUserConfirmation(title: L10n.GroupSettings.Participation.ConfirmLeave.title,
                                                    message: L10n.GroupSettings.Participation.ConfirmLeave.body,
                                                    action: L10n.GroupSettings.Participation.ConfirmLeave.leave)
        }.then {
            self.teamManager.leave(self.team)
        }.done { _ in
            self.coordinator.didLeaveOrDeleteTeam()
        }.ensure {
            self.isLeaving = false
        }.catch { error in
            self.coordinator.failLeaveOrDeleteTeam(error: error)
        }
    }

    func didTapOnDeleteButton() {
        guard !isLeaving && !isDeleting else { return }

        isDeleting = true
        firstly {
            self.coordinator.askForUserConfirmation(title: L10n.GroupSettings.Participation.ConfirmDeletion.title,
                                                    message: L10n.GroupSettings.Participation.ConfirmDeletion.body,
                                                    action: L10n.GroupSettings.Participation.ConfirmDeletion.delete)
        }.then {
            self.teamManager.delete(self.team)
        }.done { _ in
            self.coordinator.didLeaveOrDeleteTeam()
        }.ensure {
            self.isDeleting = false
        }.done { _ in
            self.tracker.log(action: .deleteTeam, category: .app, detail: "SUCCESS")
        }.catch(policy: .allErrors) { error in
            self.tracker.log(action: .deleteTeam, category: .app, detail: error.isCancelled ? "CANCELLED" : "ERROR")
            guard !error.isCancelled else { return }
            self.coordinator.failLeaveOrDeleteTeam(error: error)
        }
    }

    func didTapOnLocationSharingAction() {
        if ownLocationSharingState.enabled {
            disableLocationSharing()
        } else {
            enableLocationSharing()
        }
    }
    
    private func enableLocationSharing() {
        firstly {
            coordinator.askForUserConfirmation(title: L10n.Team.StartLocationSharing.title,
                                               message: L10n.Team.StartLocationSharing.message)
        }.then {
            self.teamManager.setLocationSharing(in: self.team, enabled: true)
        }.catch { error in
            if (error as? TeamManagerError) == .notAuthorizedToUseLocation {
                let error = L10n.Error.TeamManager.LocationSharing.NotAuthorized.self
                firstly {
                    self.coordinator.askForUserConfirmation(title: error.title, message: error.message, action: error.openSettings)
                }.done {
                    UIApplication.openSettings()
                }.cauterize()
            } else {
                self.coordinator.show(error: error)
            }
        }
    }
    
    private func disableLocationSharing() {
        firstly {
            coordinator.askForUserConfirmation(title: L10n.Team.StopLocationSharing.title,
                                               message: L10n.Team.StopLocationSharing.message)
        }.then {
            self.teamManager.setLocationSharing(in: self.team, enabled: false)
        }.catch { error in
            self.coordinator.show(error: error)
        }
    }

    enum MemberOptions: ActionSheetOption {
        case remove
        case promote

        var style: UIAlertAction.Style {
            switch self {
            case .remove:
                return .destructive
            case .promote:
                return .default
            }
        }

        var description: String {
            switch self {
            case .remove:
                return L10n.GroupSettings.Members.Member.remove
            case .promote:
                return L10n.GroupSettings.Members.Member.promote
            }
        }
    }

    func didTapOnMember(member: Member) {
        firstly { () -> Promise<MemberOptions> in
            let userName = nameSupplier.name(user: member.user)
            return self.coordinator.showActionSheet(title: userName, message: nil, actions: MemberOptions.remove)
        }.done(on: .main) { option in
            switch option {
            case .remove:
                self.remove(member: member)
            case .promote:
                return
            }
        }.catch { error in
            self.coordinator.show(error: error)
        }
    }
    
    func remove(member: Member) {
        firstly {
            self.coordinator.askForUserConfirmation(title: L10n.GroupSettings.Members.Member.ConfirmRemoval.title,
                                                    message: L10n.GroupSettings.Members.Member.ConfirmRemoval.body,
                                                    action: L10n.GroupSettings.Members.Member.ConfirmRemoval.remove)
        }.then { () -> Promise<Void> in
            logger.debug("Removing group member \(member.user.publicName ?? "") with UserId \(member.user.userId.uuidString) from group.")
            return self.teamManager.deleteGroupMember(member.membership, from: self.team)
        }.done { _ in
            self.tracker.log(action: .removeMember, category: .app, detail: "SUCCESS")
        }.catch(policy: .allErrors) { error in
            self.tracker.log(action: .removeMember, category: .app, detail: error.isCancelled ? "CANCELLED" : "ERROR")
            guard !error.isCancelled else { return }
            self.coordinator.show(error: error)
        }
    }
    
    @available(*, unavailable)
    func promote(member: Member) {
        firstly { () -> Promise<Void> in
            let userName = nameSupplier.name(user: member.user)
            return self.coordinator.askForUserConfirmation(title: L10n.GroupSettings.Members.Member.ConfirmPromotion.title,
                                                           message: L10n.GroupSettings.Members.Member.ConfirmPromotion.body(userName),
                                                           action: L10n.GroupSettings.Members.Member.ConfirmPromotion.remove)
        }.done { _ in
            self.tracker.log(action: .promoteMember, category: .app, detail: "SUCCESS")
        }.catch(policy: .allErrors) { error in
            self.tracker.log(action: .promoteMember, category: .app, detail: error.isCancelled ? "CANCELLED" : "ERROR")
            guard !error.isCancelled else { return }
            self.coordinator.show(error: error)
        }
    }
    
    private func reloadSynchronously() {
        self.delegate?.update()
    }

    private func reload() {
        DispatchQueue.main.async { self.reloadSynchronously() }
    }
    
    @objc
    private func handleForegroundTransition() {
        do {
            guard let team = try groupStorageManager.loadTeam(team.groupId) else {
                DispatchQueue.main.async { self.coordinator.didLeaveOrDeleteTeam() }
                return
            }
            self.team = team
            self.members = try groupStorageManager.members(groupId: team.groupId)
            
            reload()
        } catch {
            logger.error("Error reloading data after transition to foreground: \(error)")
        }
    }
}
