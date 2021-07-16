//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import UIKit
import PromiseKit

class JoinTeamViewController: UITableViewController, JoinTeamViewModelDelegate {

    enum CellType: String {
        case infoCell
        case actionCell
    }

    var viewModel: JoinTeamViewModel!

    func reload() {
        tableView.reloadData()
    }

    func reloadCell(at indexPath: IndexPath) {
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }

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

    // MARK: UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        viewModel.didTapOnRow(at: indexPath)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            return 18
        }

        return UITableView.automaticDimension
    }
}

protocol JoinTeamViewModelDelegate: AnyObject {
    func reload()
    func reloadCell(at indexPath: IndexPath)
}

class JoinTeamViewModel {

    unowned let coordinator: MainFlow
    weak var delegate: JoinTeamViewModelDelegate?

    let teamManager: TeamManagerType
    let userManager: UserManagerType
    let nameSupplier: NameSupplierType
    var team: Team
    
    var ownerPromise: Promise<User>?

    var isJoining: Bool = false {
        didSet {
            if isJoining != oldValue {
                delegate?.reloadCell(at: IndexPath(row: ParticipationCellType.join.rawValue, section: Section.participation.rawValue))
            }
        }
    }

    init(coordinator: MainFlow, teamManager: TeamManagerType, nameSupplier: NameSupplierType, userManager: UserManagerType, team: Team) {
        self.coordinator = coordinator
        self.teamManager = teamManager
        self.nameSupplier = nameSupplier
        self.userManager = userManager
        self.team = team
        
        self.ownerPromise = firstly { () -> Promise<User> in
            return self.userManager.getUser(team.owner)
        }.get { _ in
            self.delegate?.reloadCell(at: IndexPath(row: InfoCellType.name.rawValue, section: Section.name.rawValue))
        }
    }

    enum Section: Int, CaseIterable {
        case name = 0
        case participation = 1
    }

    var numberOfSections: Int { return Section.allCases.count }

    func numberOfRowsIn(sectionIndex: Int) -> Int {
        guard let section = Section(rawValue: sectionIndex) else {
            assertionFailure("Invalid section: \(sectionIndex)")
            return 0
        }

        switch section {
        case .name: return 1
        case .participation: return 1
        }
    }

    func cellType(for indexPath: IndexPath) -> JoinTeamViewController.CellType {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Invalid section: \(indexPath.section)")
        }

        switch section {
        case .name: return .infoCell
        case .participation: return .actionCell
        }
    }

    private enum InfoCellType: Int {
        case name
    }

    private enum ParticipationCellType: Int {
        case join
    }

    private func infoCellType(for row: Int) -> InfoCellType {
        return InfoCellType(rawValue: row)!
    }

    private func participationCellType(for row: Int) -> ParticipationCellType {
        return .join
    }

    func sectionHeader(for sectionIndex: Int) -> String? {
        guard let section = Section(rawValue: sectionIndex) else {
            assertionFailure("Invalid section: \(sectionIndex)")
            return nil
        }

        switch section {
        case .name: return nil
        case .participation: return L10n.JoinGroup.Participation.header
        }
    }

    func infoCellViewModel(for indexPath: IndexPath) -> InfoTableViewCellViewModel {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Invalid section: \(indexPath.section)")
        }

        switch section {
        case .name:
            switch infoCellType(for: indexPath.row) {
            case .name:
                let owner = userManager.user(team.owner)
                let realName = team.name
                let isLoading = realName == nil && owner == nil
                return InfoTableViewCellViewModel(title: L10n.JoinGroup.Name.name,
                                                  value: isLoading ? "" : nameSupplier.name(team: team),
                                                  shouldShowDisclosureIndicator: false,
                                                  isLoading: isLoading)
            }
        default:
            fatalError()
        }
    }

    func actionCellViewModel(for indexPath: IndexPath) -> ActionTableViewCellViewModel {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Invalid section: \(indexPath.section)")
        }

        switch section {
        case .participation:
            return ActionTableViewCellViewModel(title: L10n.JoinGroup.Participation.join, isLoading: isJoining)
        default:
            fatalError("Invalid section")
        }
    }

    func didTapOnRow(at indexPath: IndexPath) {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Invalid section: \(indexPath.section)")
        }

        switch (section, indexPath.row) {
        case (.participation, 0): join()
        default: break
        }
    }

    func join() {
        guard !isJoining else { return }

        isJoining = true
        firstly {
            teamManager.join(team).recover { error -> Promise<Team> in
                guard let apiError = error as? APIError, case .invalidGroupTag = apiError.type else {
                    throw error
                }
                return self.teamManager.getOrFetchTeam(groupId: self.team.groupId, groupKey: self.team.groupKey).then { reloadedTeam -> Promise<Team> in
                    self.team = reloadedTeam
                    self.delegate?.reload()
                    return self.teamManager.join(reloadedTeam)
                }
            }
        }.done { team in
            self.coordinator.didJoinTeam(team: team)
        }.ensure {
            self.isJoining = false
        }.catch { error in
            self.coordinator.failJoinTeam(error: error)
        }
    }
}
