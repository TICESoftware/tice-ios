//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Pulley
import MapKit
import PromiseKit
import Swinject
import Chatto
import Observable

enum ParticipationStatus {
    case none
    case onlyOthersSharing
    case sharing
}

class TeamsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, ShowsLargeButton {
    
    enum CellReuseIdentifier: String {
        case groupCell
        case addGroupCell
        #if DEVELOPMENT
        case joinTeamCell
        #endif
    }
    
    enum CellType: Int {
        case demoTeamCell
        case teamCell
        case addTeamCell
        #if DEVELOPMENT
        case joinTeamCell
        #endif
    }

    @IBOutlet weak var tableView: UITableView!
    weak var addButton: UIButton!
    
    var showsLargeButton: Bool {
        return true
    }
    
    var largeButtonImage: UIImage? {
        return UIImage(named: "plus")
    }
    
    var largeButtonAction: (() -> Void)? {
        return { [weak self] in
            self?.didTapCreateGroup()
        }
    }
    
    var largeButtonAccessibilityIdentifier: String? {
        return "groups_add"
    }
    
    var mainNavigationController: MainNavigationController {
        // swiftlint:disable:next force_cast
        navigationController as! MainNavigationController
    }

    var viewModel: TeamsViewModel! {
        didSet {
            viewModel.delegate = self
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        update()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    func update() {
        viewModel.reload()
    }

    @IBAction func didTapSettingsButton() {
        viewModel.didTapSettings()
    }

    // MARK: UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.numberOfRows
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch viewModel.cellType(for: indexPath.row) {
        case .demoTeamCell:
            // swiftlint:disable:next force_cast
            let cell = tableView.dequeueReusableCell(withIdentifier: CellReuseIdentifier.groupCell.rawValue, for: indexPath) as! TeamCell
            cell.viewModel = viewModel.demoTeamCellViewModel(for: indexPath)
            return cell
        case .teamCell:
            // swiftlint:disable:next force_cast
            let cell = tableView.dequeueReusableCell(withIdentifier: CellReuseIdentifier.groupCell.rawValue, for: indexPath) as! TeamCell
            cell.viewModel = viewModel.teamCellViewModel(for: indexPath)
            return cell
        case .addTeamCell:
            return tableView.dequeueReusableCell(withIdentifier: CellReuseIdentifier.addGroupCell.rawValue, for: indexPath)
        #if DEVELOPMENT
        case .joinTeamCell:
            return tableView.dequeueReusableCell(withIdentifier: CellReuseIdentifier.joinTeamCell.rawValue, for: indexPath)
        #endif
        }
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return viewModel.trailingSwipeActions(for: indexPath)
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        viewModel.didTapRow(indexPath)
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        switch viewModel.cellType(for: indexPath.row) {
        case .demoTeamCell:
            return .delete
        case .teamCell:
            return .delete
        case .addTeamCell:
            return .none
        #if DEVELOPMENT
        case .joinTeamCell:
            return .none
        #endif
        }
    }

    @objc
    func didTapCreateGroup() {
        viewModel.createNewTeam(source: "BarButtonItem")
    }
    
    @objc
    func didTapJoinTeam() {
        viewModel.joinTeam()
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            return 14
        }

        return UITableView.automaticDimension
    }
}

class TeamsViewModel {

    unowned let coordinator: MainFlow

    let teamManager: TeamManagerType
    let groupManager: GroupManagerType
    let groupStorageManager: GroupStorageManagerType
    let locationSharingManager: LocationSharingManagerType
    let notifier: Notifier
    let signedInUser: SignedInUser
    let tracker: TrackerType
    let resolver: Swinject.Resolver
    let chatManager: ChatManagerType
    let nameSupplier: NameSupplierType
    let demoManager: DemoManagerType
    let authManager: AuthManagerType
    
    var teams: [Team]
    var demoTeam: DemoTeam?

    weak var delegate: TeamsViewController?
    
    private var disposal = Disposal()
    private var teamsObserverToken: ObserverToken?
    private var locationSharingStateObserverToken: ObserverToken?
    private var membersObserverToken: ObserverToken?
    private var messageUpdateObserverToken: ObserverToken?

    init(coordinator: MainFlow, notifier: Notifier, teamManager: TeamManagerType, groupManager: GroupManagerType, groupStorageManager: GroupStorageManagerType, locationSharingManager: LocationSharingManagerType, chatManager: ChatManagerType, chatStorageManager: ChatStorageManagerType, signedInUser: SignedInUser, tracker: TrackerType, nameSupplier: NameSupplierType, demoManager: DemoManagerType, authManager: AuthManagerType, resolver: Swinject.Resolver, teams: [Team]) {
        self.coordinator = coordinator
        self.teamManager = teamManager
        self.groupManager = groupManager
        self.groupStorageManager = groupStorageManager
        self.locationSharingManager = locationSharingManager
        self.notifier = notifier
        self.signedInUser = signedInUser
        self.tracker = tracker
        self.resolver = resolver
        self.chatManager = chatManager
        self.nameSupplier = nameSupplier
        self.demoManager = demoManager
        self.authManager = authManager
        
        self.teams = teams
        self.teams.sort(by: sortByImportance)
        
        demoManager.demoTeam.observe(.main) { [weak self] demoTeam, _ in
            self?.demoTeam = demoManager.isDemoEnabled ? demoTeam : nil
            self?.reloadSynchronously()
        }.add(to: &disposal)
        
        teamsObserverToken = self.groupStorageManager.observeTeams(queue: .main) { [unowned self] _ in
            self.reloadSynchronously()
        }
        
        locationSharingStateObserverToken = locationSharingManager.observeLocationSharingState(queue: .main) { [unowned self] _ in
            self.reloadSynchronously()
        }
        
        membersObserverToken = self.groupStorageManager.observeMembers(queue: .main) { [unowned self] _ in
            self.reloadSynchronously()
        }
        
        messageUpdateObserverToken = chatStorageManager.observeMessageUpdates(queue: .main) { [unowned self] in
            self.reloadSynchronously()
        }
    }

    deinit {
        teamsObserverToken = nil
        locationSharingStateObserverToken = nil
        membersObserverToken = nil
        messageUpdateObserverToken = nil
    }

    var numberOfRows: Int {
        #if DEVELOPMENT
        return demoTeamsCount + teams.count + 2
        #else
        return demoTeamsCount + teams.count + 1
        #endif
    }
    
    var demoTeamsCount: Int {
        demoTeam != nil ? 1 : 0
    }

    func cellType(for rowIndex: Int) -> TeamsViewController.CellType {
        switch rowIndex {
        case 0..<demoTeamsCount:
            return .demoTeamCell
        case demoTeamsCount..<(demoTeamsCount + teams.count):
            return .teamCell
        case demoTeamsCount + teams.count:
            return .addTeamCell
        #if DEVELOPMENT
        case demoTeamsCount + teams.count + 1:
            return .joinTeamCell
        #endif
        default:
            return .addTeamCell
        }
    }
    
    func demoTeamFor(row: Int) -> DemoTeam {
        return demoTeam!
    }

    func teamFor(row: Int) -> Team {
        return teams[row - demoTeamsCount]
    }
    
    func participationStatus(groupId: GroupId) throws -> ParticipationStatus {
        let ownLocationSharingState = locationSharingManager.locationSharingState(userId: signedInUser.userId, groupId: groupId)
        let othersLocationSharingState = locationSharingManager.othersLocationSharingState(ownUserId: signedInUser.userId, groupId: groupId)
        return ownLocationSharingState.enabled ? .sharing : (othersLocationSharingState.contains { $0.enabled } ? .onlyOthersSharing : .none)
    }
    
    func sortByImportance(lhs: Team, rhs: Team) -> Bool {
        let lhsLastUpdated = lastUpdated(team: lhs)
        let rhsLastUpdated = lastUpdated(team: rhs)
        return lhsLastUpdated > rhsLastUpdated
    }
    
    func lastUpdated(team: Team) -> Date {
        let ownLocationSharingStateLastUpdated = locationSharingManager.locationSharingState(userId: signedInUser.userId, groupId: team.groupId).lastUpdated
        let othersLocationSharingStateLastUpdated = locationSharingManager.othersLocationSharingState(ownUserId: signedInUser.userId, groupId: team.groupId).map(\.lastUpdated).max(by: <)
        let lastMessageDate = (chatManager.lastMessage(for: team.groupId) as? DateableProtocol)?.date
        let membership = try? groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: team.groupId).serverSignedMembershipCertificate
        let joinDate: Date? = try? membership.map(authManager.membershipCertificateCreationDate(certificate:))
        
        let datesOrNil: [Date?] = [ownLocationSharingStateLastUpdated, othersLocationSharingStateLastUpdated, lastMessageDate, joinDate]
        let dates = datesOrNil.compactMap { $0 }
        return dates.max(by: <) ?? .distantPast
    }
    
    func demoTeamCellViewModel(for indexPath: IndexPath) -> DemoTeamCellViewModel {
        let team = demoTeamFor(row: indexPath.row)
        
        let names = team.members.map(\.name) + [L10n.Name.you]
        let description = LocalizedList(names)
        
        return DemoTeamCellViewModel(title: team.name,
                                     description: description,
                                     avatar: demoManager.teamAvatar,
                                     lastActivity: nil,
                                     hasUnreadMessages: false,
                                     statusIcon: nil)
    }

    func teamCellViewModel(for indexPath: IndexPath) -> TeamCellViewModel {
        let team = teamFor(row: indexPath.row)
        let lastUpdated = lastUpdated(team: team)
        var participationStatus: ParticipationStatus
        var members: [Member]
        do {
            participationStatus = try self.participationStatus(groupId: team.groupId)
            members = try groupStorageManager.members(groupId: team.groupId)
        } catch {
            logger.error("Failed to load data for team cell: \(String(describing: error))")
            participationStatus = .none
            members = []
        }

        return resolver.resolve(TeamCellViewModel.self, arguments: team, members, lastUpdated, participationStatus)!
    }

    func createNewTeam(source: String) {
        coordinator.createTeam(source: source)
    }
    
    func joinTeam() {
        firstly {
            self.coordinator.askForUserInput(title: L10n.Teams.JoinTeam.title, message: L10n.Teams.JoinTeam.body, placeholder: L10n.Teams.JoinTeam.placeholder, action: L10n.Teams.JoinTeam.action)
        }.then { input -> Promise<Team> in
            let urlRegex = "(http|https)\\:\\/\\/[a-zA-Z0-9\\-\\.]+\\.[a-zA-Z]{2,3}(\\/\\S*)?"
            let groupIDHashKeyRegex = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}#[a-zA-Z0-9_-]+"
            guard let input = input else {
                throw RegisterError.invalidInput
            }
            
            if let urlRange = input.range(of: urlRegex, options: .regularExpression), !urlRange.isEmpty,
               let teamURL = URL(string: String(input[urlRange])) {
                let deepLinkParser = self.resolver.resolve(DeepLinkParserType.self)!
                return deepLinkParser.team(url: teamURL)
            } else if let groupIdHashKeyRange = input.range(of: groupIDHashKeyRegex, options: .regularExpression), !groupIdHashKeyRange.isEmpty {
                let groupIdHashKeyComponents = String(input[groupIdHashKeyRange]).components(separatedBy: "#")
                
                guard groupIdHashKeyComponents.count == 2,
                      let groupId = GroupId(uuidString: groupIdHashKeyComponents[0]),
                      let groupKey = Data(base64URLEncoded: groupIdHashKeyComponents[1]) else {
                    throw RegisterError.invalidInput
                }
                
                return self.teamManager.getOrFetchTeam(groupId: groupId, groupKey: groupKey)
            } else {
                throw RegisterError.invalidInput
            }
        }.then { team -> Promise<Team> in
            let teamManager = self.resolver.resolve(TeamManagerType.self)!
            return teamManager.join(team)
        }.catch(policy: .allErrors) { error in
            guard !error.isCancelled else { return }
            self.coordinator.show(error: error)
        }
    }
    
    func leave(team: Team) {
        firstly {
            self.coordinator.askForUserConfirmation(title: L10n.GroupSettings.Participation.ConfirmLeave.title,
                                                    message: L10n.GroupSettings.Participation.ConfirmLeave.body,
                                                    action: L10n.GroupSettings.Participation.ConfirmLeave.leave)
        }.then {
            self.teamManager.leave(team)
        }.done {
            self.tracker.log(action: .leaveTeam, category: .app, detail: "SUCCESS")
        }.catch(policy: .allErrors) { error in
            self.tracker.log(action: .leaveTeam, category: .app, detail: error.isCancelled ? "CANCELLED" : "ERROR")
            guard !error.isCancelled else { return }
            self.coordinator.failLeaveOrDeleteTeam(error: error)
        }
    }

    func delete(team: Team) {
        firstly {
            self.coordinator.askForUserConfirmation(title: L10n.GroupSettings.Participation.ConfirmDeletion.title,
                                                    message: L10n.GroupSettings.Participation.ConfirmDeletion.body,
                                                    action: L10n.GroupSettings.Participation.ConfirmDeletion.delete)
        }.then {
            self.teamManager.delete(team)
        }.done {
            self.tracker.log(action: .deleteTeam, category: .app, detail: "SUCCESS")
        }.catch(policy: .allErrors) { error in
            self.tracker.log(action: .deleteTeam, category: .app, detail: error.isCancelled ? "CANCELLED" : "ERROR")
            guard !error.isCancelled else { return }
            self.coordinator.failLeaveOrDeleteTeam(error: error)
        }
    }
    
    func didTapRow(_ indexPath: IndexPath) {
        switch cellType(for: indexPath.row) {
        case .demoTeamCell:
            didTapDemoTeam(for: indexPath)
        case .teamCell:
            didTapTeam(for: indexPath)
        case .addTeamCell:
            createNewTeam(source: "Cell")
        #if DEVELOPMENT
        case .joinTeamCell:
            joinTeam()
        #endif
        }
    }
    
    func didTapDemoTeam(for indexPath: IndexPath) {
        let demoTeam = demoTeamFor(row: indexPath.row)
        coordinator.showTeamScreen(demoTeam: demoTeam, animated: true)
    }

    func didTapTeam(for indexPath: IndexPath) {
        let team = teamFor(row: indexPath.row)
        coordinator.showTeamScreen(team: team, animated: true)
    }

    func didTapSettings() {
        coordinator.didTapSettings()
    }
    
    func trailingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let type = cellType(for: indexPath.row)
        
        switch type {
        case .demoTeamCell:
            let deleteAction = UIContextualAction(style: .destructive, title: L10n.Teams.Demo.Editing.delete, handler: { _, _, completion in
                self.tracker.log(action: .endDemo, category: .demo, detail: "Teams")
                self.demoManager.endDemo()
                self.reload()
                completion(true)
            })
            return UISwipeActionsConfiguration(actions: [deleteAction])
        case .teamCell:
            let team = teamFor(row: indexPath.row)
            do {
                let action: UIContextualAction
                if try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: team.groupId).admin {
                    action = UIContextualAction(style: .destructive, title: L10n.Teams.Editing.delete, handler: { _, _, completion in
                        self.delete(team: team)
                        completion(true)
                    })
                } else {
                    action = UIContextualAction(style: .destructive, title: L10n.Teams.Editing.leave, handler: { _, _, completion in
                        self.leave(team: team)
                        completion(true)
                    })
                }
                return UISwipeActionsConfiguration(actions: [action])
            } catch {
                logger.error("Error determining admin status in team \(team.groupId).")
                return nil
            }
        default:
            return nil
        }
    }
    
    private func reloadSynchronously() {
        self.teams.sort(by: sortByImportance)
        self.delegate?.tableView?.reloadData()
    }
    
    func reload() {
        DispatchQueue.main.async { self.reloadSynchronously() }
    }
}
