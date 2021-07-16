//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import PromiseKit
import TICEAPIModels
import Swinject
import Observable

class MeetupSettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak var tableView: UITableView!

    @IBOutlet weak var participationTitle: LocalizableLabel!
    @IBOutlet weak var participationBody: LocalizableLabel!
    @IBOutlet weak var participationButton: LocalizableButton!
    
    @IBOutlet weak var locationSharingSwitch: UISwitch!
    @IBOutlet weak var locationSharingWarning: UILabel!
    
    @IBOutlet var menuButton: UIBarButtonItem!

    enum CellType: String {
        case memberCell
        case actionCell
    }

    var viewModel: MeetupSettingsViewModelType! {
        didSet {
            viewModel.delegate = self
        }
    }
    var disposal = Disposal()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.rightBarButtonItem = viewModel.showMenuButton.wrappedValue ? menuButton : nil

        viewModel.participationButtonMode.observe(.main) { [weak self] value, _ in
            self?.participationTitle.localizationKey = value.titleKey
            self?.participationBody.localizationKey = value.bodyKey
            self?.participationButton.localizationKey = value.buttonTitleKey
            self?.participationButton.setTitleColor(.white, for: .normal)
            self?.participationButton.backgroundColor = value.buttonDestructive ? UIColor.destructive : UIColor.highlightBackground
        }.add(to: &disposal)
        
        viewModel.showMenuButton.observe(.main) { [weak self] show, _ in
            self?.navigationItem.rightBarButtonItem = show ? self?.menuButton : nil
        }.add(to: &disposal)
        
        viewModel.locationSharingEnabled.observe(.main) { [weak self] enabled, _ in
            self?.locationSharingSwitch.setOn(enabled, animated: false)
            self?.locationSharingWarning.isHidden = enabled
        }.add(to: &disposal)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.update()
    }

    @IBAction func didTapParticipationButton(_ sender: UIButton) {
        viewModel.didTapOnParticipationAction()
    }
    
    @IBAction func didTapMenuButton(_ sender: Any) {
        viewModel.didTapOnMenuButton()
    }
    
    @IBAction func didToggleLocationSharing(_ sender: Any) {
        viewModel.locationSharingEnabled.wrappedValue = locationSharingSwitch.isOn
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.numberOfSections
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.numberOfRowsIn(sectionIndex: section)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellType = viewModel.cellType(for: indexPath)

        switch cellType {
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

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return viewModel.sectionHeader(for: section)
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return viewModel.sectionFooter(for: section)
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        viewModel.didTapOnRow(at: indexPath)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let cellType = viewModel.cellType(for: indexPath)
        switch cellType {
        case .memberCell:
            return 56
        case .actionCell:
            return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UITableView.automaticDimension
    }

    func startParticipationButtonLoading() {
        participationButton.startLoading()
    }

    func stopParticipationButtonLoading() {
        participationButton.stopLoading()
    }
}

protocol MeetupSettingsViewModelType {
    
    var delegate: MeetupSettingsViewController? { get set }
    
    var participationButtonMode: MutableObservable<MeetupSettingsViewModel.ParticipationViewMode> { get }
    var showMenuButton: MutableObservable<Bool> { get }
    var locationSharingEnabled: MutableObservable<Bool> { get }
    var numberOfSections: Int { get }

    func numberOfRowsIn(sectionIndex: Int) -> Int
    func cellType(for indexPath: IndexPath) -> MeetupSettingsViewController.CellType
    func memberCellViewModel(for indexPath: IndexPath) -> MemberTableViewCellViewModelType
    func actionCellViewModel(for indexPath: IndexPath) -> ActionTableViewCellViewModel
    
    func sectionHeader(for sectionIndex: Int) -> String?
    func sectionFooter(for sectionIndex: Int) -> String?
    
    func didTapOnRow(at indexPath: IndexPath)
    func didTapOnParticipationAction()
    func didTapOnMenuButton()
    
    func update()
}

class MeetupSettingsViewModel: MeetupSettingsViewModelType {

    unowned let coordinator: MainFlow
    
    let meetupManager: MeetupManagerType
    let teamManager: TeamManagerType
    let groupStorageManager: GroupStorageManagerType
    let locationManager: LocationManagerType
    let signedInUser: SignedInUser
    let nameSupplier: NameSupplierType
    let notifier: Notifier
    let resolver: Swinject.Resolver
    let tracker: TrackerType

    var team: Team
    var meetup: Meetup
    var participating: Bool
    var members: [Member]
    var teamMembers: [Member] = []
    var nonMembers: [Member]
    var admin: Bool
    var participationAction: ParticipationAction

    struct ParticipationViewMode {
        var titleKey: String
        var bodyKey: String
        var buttonTitleKey: String
        
        var buttonDestructive: Bool

        static var join: ParticipationViewMode = .init(titleKey: "meetupSettings_participation_join_title",
                                                       bodyKey: "meetupSettings_participation_join_body",
                                                       buttonTitleKey: "meetupSettings_participation_join_join",
                                                       buttonDestructive: false)

        static var leave: ParticipationViewMode = .init(titleKey: "meetupSettings_participation_leave_title",
                                                        bodyKey: "meetupSettings_participation_leave_body",
                                                        buttonTitleKey: "meetupSettings_participation_leave_leave",
                                                        buttonDestructive: false)

        static var delete: ParticipationViewMode = .init(titleKey: "meetupSettings_participation_delete_title",
                                                         bodyKey: "meetupSettings_participation_delete_body",
                                                         buttonTitleKey: "meetupSettings_participation_delete_delete",
                                                         buttonDestructive: false)
    }

    var participationButtonMode: MutableObservable<ParticipationViewMode>
    var showMenuButton: MutableObservable<Bool>
    var locationSharingEnabled: MutableObservable<Bool>
    
    var disposal = Disposal()
    weak var delegate: MeetupSettingsViewController?
    
    private var meetupObserverToken: ObserverToken?
    private var teamObserverToken: ObserverToken?
    private var participatingObserverToken: ObserverToken?
    
    private var foregroundTransitionObserverToken: NSObjectProtocol?

    init(coordinator: MainFlow, meetupManager: MeetupManagerType, teamManager: TeamManagerType, groupStorageManager: GroupStorageManagerType, locationManager: LocationManagerType, signedInUser: SignedInUser, nameSupplier: NameSupplierType, notifier: Notifier, tracker: TrackerType, resolver: Swinject.Resolver, team: Team, meetup: Meetup, participating: Bool, members: [Member], nonMembers: [Member], admin: Bool) {
        self.coordinator = coordinator
        self.meetupManager = meetupManager
        self.teamManager = teamManager
        self.groupStorageManager = groupStorageManager
        self.locationManager = locationManager
        self.signedInUser = signedInUser
        self.nameSupplier = nameSupplier
        self.notifier = notifier
        self.tracker = tracker
        self.team = team
        self.meetup = meetup
        self.participating = participating
        self.resolver = resolver
        self.members = members
        self.nonMembers = nonMembers
        self.admin = admin

        self.participationAction = .join
        self.participationButtonMode = .init(.join)
        self.showMenuButton = .init(false)
        self.locationSharingEnabled = .init(meetup.locationSharingEnabled && !locationManager.notAuthorizedToUseLocation)
        
        update()
        
        meetupObserverToken = groupStorageManager.observeMeetup(groupId: meetup.groupId, queue: .main) { [unowned self] meetup, members in
            guard let meetup = meetup else { return }
            self.meetup = meetup
            self.members = members
            self.nonMembers = self.nonMembers(teamMembers: self.teamMembers, meetupMembers: members)
            self.reloadSynchronously()
        }
        
        teamObserverToken = groupStorageManager.observeTeam(groupId: meetup.teamId, queue: .main) { [unowned self] _, teamMembers in
            self.teamMembers = teamMembers
            self.nonMembers = self.nonMembers(teamMembers: teamMembers, meetupMembers: self.members)
            self.reloadSynchronously()
        }
        
        participatingObserverToken = groupStorageManager.observeIsMember(groupId: meetup.groupId, userId: signedInUser.userId, queue: .main) { [unowned self] participating in
            self.participating = participating
            self.reloadSynchronously()
        }
        
        foregroundTransitionObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [unowned self] _ in self.handleForegroundTransition() }
        
        meetupManager.reload(meetup: meetup).catch({ logger.error($0) })
    }
    
    deinit {
        meetupObserverToken = nil
        teamObserverToken = nil
        participatingObserverToken = nil
        
        foregroundTransitionObserverToken.map { NotificationCenter.default.removeObserver($0) }
    }

    func update() {
        participationAction = loadParticipationAction()
        participationButtonMode.wrappedValue = participationAction.participationViewMode
        showMenuButton.wrappedValue = participationAction != .delete && isTeamAdmin()
    }
    
    func isTeamAdmin() -> Bool {
        if let teamMembership = try? groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: meetup.teamId),
            teamMembership.admin {
            return true
        } else {
            return false
        }
    }
    
    enum ParticipationAction {
        case delete
        case leave
        case join
        
        var participationViewMode: ParticipationViewMode {
            switch self {
            case .delete:
                return .delete
            case .leave:
                return .leave
            case .join:
                return .join
            }
        }
    }

    func loadParticipationAction() -> ParticipationAction {
        if participating {
            if admin {
                return .delete
            } else {
                return .leave
            }
        } else {
            return .join
        }
    }

    enum Section: Int, CaseIterable {
        case participants = 0
        case nonParticipants = 1
        case inviteParticipants = 2
    }
    
    var sections: [Section] {
        return nonMembers.isEmpty ? [.participants, .inviteParticipants] : [.participants, .nonParticipants, .inviteParticipants]
    }
    
    var numberOfSections: Int {
        return sections.count
    }

    func numberOfRowsIn(sectionIndex: Int) -> Int {
        let section = sections[sectionIndex]
        switch section {
        case .participants: return members.count
        case .nonParticipants: return nonMembers.count
        case .inviteParticipants: return 1
        }
    }

    func cellType(for indexPath: IndexPath) -> MeetupSettingsViewController.CellType {
        let section = sections[indexPath.section]
        switch section {
        case .participants: return .memberCell
        case .nonParticipants: return .memberCell
        case .inviteParticipants: return .actionCell
        }
    }

    func sectionHeader(for sectionIndex: Int) -> String? {
        let section = sections[sectionIndex]
        switch section {
        case .participants: return L10n.MeetupSettings.Participants.header
        case .nonParticipants: return L10n.MeetupSettings.NonParticipants.header
        case .inviteParticipants: return nil
        }
    }

    func sectionFooter(for sectionIndex: Int) -> String? {
        return nil
    }

    func memberCellViewModel(for indexPath: IndexPath) -> MemberTableViewCellViewModelType {
        let section = sections[indexPath.section]
        switch section {
        case .participants:
            let member = members[indexPath.row]
            let isTouchable = member.user != signedInUser && admin
            return resolver.resolve(MemberTableViewCellViewModel.self, arguments: member.user, isTouchable, member.membership.admin)!
        case .nonParticipants:
            let member = nonMembers[indexPath.row]
            return resolver.resolve(MemberTableViewCellViewModel.self, arguments: member.user, false, false)!
        case .inviteParticipants:
            fatalError()
        }
    }
    
    func actionCellViewModel(for indexPath: IndexPath) -> ActionTableViewCellViewModel {
        let section = sections[indexPath.section]
        switch section {
        case .inviteParticipants:
            return ActionTableViewCellViewModel(title: L10n.GroupSettings.Members.add)
        case .participants, .nonParticipants:
            fatalError()
        }
    }

    func didTapOnRow(at indexPath: IndexPath) {
        let section = sections[indexPath.section]
        switch section {
        case .participants:
            let member = members[indexPath.row]
            didTapOnParticipant(member: member)
        case .inviteParticipants:
            coordinator.showShareScreen(for: team)
        default:
            break
        }
    }
    
    func didTapOnMenuButton() {
        enum MeetupOptions: ActionSheetOption {
            case deleteMeetup

            var style: UIAlertAction.Style {
                switch self {
                case .deleteMeetup:
                    return .destructive
                }
            }
            
            var description: String {
                switch self {
                case .deleteMeetup:
                    return L10n.MeetupSettings.Participation.Delete.delete
                }
            }
        }
        
        firstly {
            self.coordinator.showActionSheet(title: nil,
                                             message: nil,
                                             actions: MeetupOptions.deleteMeetup,
                                             cancel: L10n.Alert.cancel)
        }.get { _ in
            self.delegate?.startParticipationButtonLoading()
        }.then(on: .main) { option -> Promise<Void> in
            switch option {
            case .deleteMeetup:
                return self.coordinator.askForUserConfirmation(title: L10n.MeetupSettings.Menu.DeleteMeetup.Confirmation.title,
                                                               message: L10n.MeetupSettings.Menu.DeleteMeetup.Confirmation.body,
                                                               action: L10n.MeetupSettings.Menu.DeleteMeetup.Confirmation.delete,
                                                               actionStyle: .destructive)
            }
        }.ensure {
            self.delegate?.stopParticipationButtonLoading()
        }.then {
            return self.meetupManager.delete(self.meetup)
        }.catch { error in
            self.coordinator.failLeaveOrDeleteMeetup(error: error)
        }
    }

    enum MemberOptions: ActionSheetOption {
        case remove

        var style: UIAlertAction.Style {
            switch self {
            case .remove:
                return .destructive
            }
        }

        var description: String {
            switch self {
            case .remove:
                return L10n.MeetupSettings.Participants.Participant.remove
            }
        }
    }

    func didTapOnParticipant(member: Member) {
        let userName = nameSupplier.name(user: member.user)

        firstly { () -> Promise<MemberOptions> in
            return self.coordinator.showActionSheet(title: userName, message: nil, actions: MemberOptions.remove)
        }.then(on: .main) { option -> Promise<Void> in
            switch option {
            case .remove:
                return self.coordinator.askForUserConfirmation(title: L10n.MeetupSettings.Participants.Participant.ConfirmRemoval.title,
                                                               message: L10n.MeetupSettings.Participants.Participant.ConfirmRemoval.body(userName),
                                                               action: L10n.MeetupSettings.Participants.Participant.ConfirmRemoval.remove)
            }
        }.then { () -> Promise<Void> in
            logger.debug("Removing group member \(userName) with UserId \(member.user.userId.uuidString) from group.")
            return self.meetupManager.deleteGroupMember(member.membership, from: self.meetup)
        }.done { _ in
            self.tracker.log(action: .removeMember, category: .app, detail: "SUCCESS")
        }.catch(policy: .allErrors) { error in
            self.tracker.log(action: .removeMember, category: .app, detail: error.isCancelled ? "CANCELLED" : "ERROR")
            guard !error.isCancelled else { return }
            self.coordinator.show(error: error)
        }
    }

    func didTapOnParticipationAction() {
        switch participationAction {
        case .join:
            join()
        case .leave:
            leave()
        case .delete:
            delete()
        }
    }

    func join() {
        tracker.log(action: .joinMeetup, category: .app)
        
        delegate?.startParticipationButtonLoading()
        firstly {
            meetupManager.join(meetup).recover { error -> Promise<Void> in
                guard let apiError = error as? APIError, case .invalidGroupTag = apiError.type else {
                    throw error
                }
                return self.meetupManager.reload(meetup: self.meetup).then { reloadedMeetup -> Promise<Void> in
                    self.meetup = reloadedMeetup
                    return self.meetupManager.join(reloadedMeetup)
                }
            }
            
        }.done(on: .main) {
            self.coordinator.didJoinMeetup()
        }.catch(on: .main) { error in
            self.coordinator.failJoinTeam(error: error)
        }.finally {
            self.delegate?.stopParticipationButtonLoading()
        }
    }

    func leave() {
        tracker.log(action: .leaveMeetup, category: .app)
        
        delegate?.startParticipationButtonLoading()
        firstly {
            meetupManager.leave(meetup)
        }.catch(on: .main) { error in
            self.coordinator.failLeaveOrDeleteMeetup(error: error)
        }.finally {
            self.delegate?.stopParticipationButtonLoading()
        }
    }

    func delete() {
        tracker.log(action: .deleteMeetup, category: .app, detail: nil, number: Double(members.count))
        
        delegate?.startParticipationButtonLoading()
        firstly {
            meetupManager.delete(meetup)
        }.catch(on: .main) { error in
            self.coordinator.failLeaveOrDeleteMeetup(error: error)
        }.finally {
            self.delegate?.stopParticipationButtonLoading()
        }
    }
    
    private func nonMembers(teamMembers: [Member], meetupMembers: [Member]) -> [Member] {
        teamMembers.filter { member in !meetupMembers.contains(where: { $0.user == member.user }) }
    }
    
    private func reloadSynchronously() {
        self.delegate?.tableView?.reloadData()
        self.update()
    }
    
    func reload() {
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
            
            guard let meetupId = team.meetupId,
                  let meetup = try groupStorageManager.loadMeetup(meetupId) else {
                DispatchQueue.main.async { self.coordinator.didLeaveOrDeleteMeetup() }
                return
            }
            self.meetup = meetup
            
            let teamMembers = try groupStorageManager.members(groupId: team.groupId)
            self.members = try groupStorageManager.members(groupId: meetup.groupId)
            self.nonMembers = nonMembers(teamMembers: teamMembers, meetupMembers: self.members)
            self.participating = try groupStorageManager.isMember(userId: signedInUser.userId, groupId: meetup.groupId)
            
            reload()
        } catch {
            logger.error("Error reloading data after transition to foreground: \(error)")
        }
    }
}
