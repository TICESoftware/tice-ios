//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Eureka
import TICEAPIModels
import PromiseKit

protocol CreateTeamViewModelDelegate: AnyObject {
    func showLoading()
    func hideLoading()
}

class CreateTeamViewController: FormViewController, CreateTeamViewModelDelegate {

    var viewModel: CreateTeamViewModel! {
        didSet {
            viewModel.delegate = self
        }
    }

    @IBOutlet weak var continueButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.enter()
        form = viewModel.generateForm()
    }

    @IBAction func continueButtonTapped(_ sender: Any) {
        view.endEditing(true)
        viewModel.done(form: form)
    }

    @IBAction func cancelButtonTapped(_ sender: Any) {
        viewModel.cancel()
    }

    func showLoading() {
        continueButton.isEnabled = false

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        continueButton.customView = activityIndicator
        activityIndicator.startAnimating()
    }

    func hideLoading() {
        continueButton.customView = nil
        continueButton.isEnabled = true
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            return 18
        }

        return UITableView.automaticDimension
    }
}

enum CreateTeamBasicSectionRow: Int, CaseIterable {
    case name

    var title: String {
        switch self {
        case .name:
            return L10n.CreateGroup.Basic.name
        }
    }
}

enum CreateTeamPermissionSectionRow: Int, CaseIterable {
    case permission
}

enum CreateTeamSection: Int, CaseIterable {
    case basic = 0
    case permissions = 1

    var title: String? {
        switch self {
        case .basic: return nil
        case .permissions: return L10n.CreateGroup.Permissions.header
        }
    }

    var rowCount: Int {
        switch self {
        case .basic: return CreateTeamBasicSectionRow.allCases.count
        case .permissions: return 0
        }
    }
}

class CreateTeamViewModel {

    weak var coordinator: CreateTeamFlow?
    weak var delegate: CreateTeamViewModelDelegate?

    let teamManager: TeamManagerType
    let nameSupplier: NameSupplierType
    let signedInUser: SignedInUser
    let tracker: TrackerType

    init(coordinator: CreateTeamFlow, teamManager: TeamManagerType, nameSupplier: NameSupplierType, signedInUser: SignedInUser, tracker: TrackerType) {
        self.coordinator = coordinator
        self.teamManager = teamManager
        self.nameSupplier = nameSupplier
        self.signedInUser = signedInUser
        self.tracker = tracker
    }

    var numberOfSections: Int {
        return CreateTeamSection.allCases.count
    }

    func section(at index: Int) -> CreateTeamSection {
        return CreateTeamSection(rawValue: index)!
    }

    func titleForSection(at sectionIndex: Int) -> String? {
        return section(at: sectionIndex).title
    }

    func numberOfRows(in sectionIndex: Int) -> Int {
        return section(at: sectionIndex).rowCount
    }

    func basicRow(at row: Int) -> CreateTeamBasicSectionRow {
        return CreateTeamBasicSectionRow(rawValue: row)!
    }

    func permissionRow(at row: Int) -> CreateTeamPermissionSectionRow {
        return CreateTeamPermissionSectionRow(rawValue: row)!
    }
    
    func enter() {
        tracker.log(action: .showCreateTeam, category: .createTeam, detail: coordinator?.source)
    }

    func done(form: Form) {

        let values = form.values()
        let name = values[Row.name.rawValue] as? String
        let shareLocation = values[Row.startLocationSharing.rawValue] as? Bool == true
        
        let joinMode = JoinMode.open
        let permissionMode = PermissionMode.everyone
        
        if shareLocation {
            tracker.log(action: .createTeamAndShareLocation, category: .createTeam)
        } else {
            tracker.log(action: .createTeam, category: .createTeam)
        }
        
        delegate?.showLoading()
        firstly {
            teamManager.createTeam(joinMode: joinMode, permissionMode: permissionMode, name: name, shareLocation: shareLocation, meetingPoint: nil)
        }.done { group in
            self.coordinator?.creatingDone(team: group)
        }.ensure {
            self.delegate?.hideLoading()
        }.catch { error in
            self.tracker.log(action: .error, category: .createTeam)
            self.coordinator?.fail(error: error)
        }
    }

    func cancel() {
        tracker.log(action: .cancel, category: .createTeam)
        coordinator?.cancel()
    }

    private enum Row: String {
        case name
        case startLocationSharing
        case meetingPoint
        case reminder
        case meetingTimeReminder
        case joinMode
        case permissionMode
    }

    func generateForm() -> Form {
        return Form()
        +++ Section()
        <<< SwitchRow(Row.startLocationSharing.rawValue) { row in
            row.title = L10n.CreateGroup.StartLocationSharing.title
            row.value = true
            row.cellSetup { cell, _ in
                cell.switchControl.accessibilityIdentifier = "createGroup_startLocationSharing"
            }
        }
        +++ Section()
        <<< TextRow(Row.name.rawValue) { row in
            row.title = L10n.CreateGroup.Basic.name
            row.placeholder = nameSupplier.groupNameByOwner(owner: signedInUser.userId)
            row.cellSetup { cell, _ in
                cell.textField.accessibilityIdentifier = "createGroup_basic_name"
            }
        }
    }
}
