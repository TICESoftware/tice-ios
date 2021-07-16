//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import Foundation
import UIKit
import Eureka
import TICEAPIModels
import PromiseKit
import CoreLocation

protocol CreateMeetupViewModelDelegate: AnyObject {
    func showLoading()
    func hideLoading()
}

class CreateMeetupViewController: FormViewController, CreateMeetupViewModelDelegate {

    var viewModel: CreateMeetupViewModel! {
        didSet {
            viewModel.delegate = self
        }
    }

    @IBOutlet weak var continueButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
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
        continueButton.startLoading()
    }

    func hideLoading() {
        continueButton.stopLoading()
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UITableView.automaticDimension
    }
}

private enum CreateMeetupBasicSectionRow: Int, CaseIterable {
    case name

    var title: String {
        switch self {
        case .name:
            return L10n.CreateMeetup.Basic.name
        }
    }
}

private enum CreateMeetupPermissionSectionRow: Int, CaseIterable {
    case permission
}

private enum CreateMeetupSection: Int, CaseIterable {
    case basic = 0
    case permissions = 1

    var title: String? {
        switch self {
        case .basic: return nil
        case .permissions: return L10n.CreateMeetup.Permissions.header
        }
    }

    var rowCount: Int {
        switch self {
        case .basic: return CreateTeamBasicSectionRow.allCases.count
        case .permissions: return 0
        }
    }
}

enum CreateMeetupError: LocalizedError {
    case invalidGroupJoinMode
    case invalidGroupPermissionMode

    var errorDescription: String? {
        switch self {
        case .invalidGroupJoinMode:
            return L10n.CreateMeetup.Error.invalidGroupJoinMode
        case .invalidGroupPermissionMode:
            return L10n.CreateMeetup.Error.invalidGroupPermissionMode
        }
    }
}

class CreateMeetupViewModel {

    weak var coordinator: MeetupCreationFlow?
    weak var delegate: CreateMeetupViewModelDelegate?

    let meetupManager: MeetupManagerType
    let teamManager: TeamManagerType
    let locationManager: LocationManagerType
    let addressLocalizer: AddressLocalizerType
    let team: Team?
    let meetingPoint: LocationAnnotation?

    init(coordinator: MeetupCreationFlow, meetupManager: MeetupManagerType, teamManager: TeamManagerType, locationManager: LocationManagerType, addressLocalizer: AddressLocalizerType, team: Team?, meetingPoint: LocationAnnotation?) {
        self.coordinator = coordinator
        self.meetupManager = meetupManager
        self.teamManager = teamManager
        self.locationManager = locationManager
        self.addressLocalizer = addressLocalizer
        self.team = team
        self.meetingPoint = meetingPoint
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

    func createTeam(form: Form) throws -> Promise<Team> {
        let values = form.values()
        let name = values[Row.groupName.rawValue] as? String ?? L10n.CreateMeetup.Basic.Name.default

        guard let internalJoinMode = values[Row.groupJoinMode.rawValue] as? JoinModeUIOption else {
            throw CreateMeetupError.invalidGroupJoinMode
        }
        guard let internalPermissionMode = values[Row.groupPermissionMode.rawValue] as? PermissionModeUIOption else {
            throw CreateMeetupError.invalidGroupPermissionMode
        }

        let joinMode = internalJoinMode.joinMode
        let permissionMode = internalPermissionMode.permissionMode
        return teamManager.createTeam(joinMode: joinMode, permissionMode: permissionMode, name: name, shareLocation: false, meetingPoint: nil)
    }

    func done(form: Form) {
        let location = meetingPoint?.location.location

        delegate?.showLoading()
        firstly {
            createTeamAndMeetup(form: form, location: location)
        }.done { meetup in
            self.coordinator?.done(meetup: meetup)
        }.ensure {
            self.delegate?.hideLoading()
        }.catch { error in
            self.coordinator?.fail(error: error)
        }
    }

    func createTeamAndMeetup(form: Form, location: Location?) -> Promise<Meetup> {
        firstly { () -> Promise<Team> in
            if let team = self.team {
                return .value(team)
            }
            return try self.createTeam(form: form)
        }.then { team in
            self.meetupManager.createMeetup(in: team, at: location, joinMode: JoinMode.open, permissionMode: PermissionMode.everyone)
        }
    }

    func cancel() {
        coordinator?.cancel()
    }

    private enum Row: String {
        case meetingPoint
        case groupName
        case groupJoinMode
        case groupPermissionMode
    }

    func generateForm() -> Form {
        let meetingPointDescription: String
        if let meetingPoint = meetingPoint {
            meetingPointDescription = addressLocalizer.short(annotation: meetingPoint)
        } else {
            meetingPointDescription = L10n.CreateMeetup.MeetingPoint.none
        }

        return Form()
            +++ Section(L10n.CreateMeetup.Group.header) { section in
                section.hidden = .init(booleanLiteral: self.team != nil)
            }
            <<< TextRow(Row.groupName.rawValue) { row in
                row.title = L10n.CreateMeetup.Group.Name.title
                row.placeholder = L10n.CreateMeetup.Group.Name.placeholder
                row.cellSetup { cell, row in
                    cell.textField.becomeFirstResponder()
                    row.reload()
                }
            }
            <<< PushRow<JoinModeUIOption>(Row.groupJoinMode.rawValue) { row in
                row.title = L10n.CreateMeetup.Group.accessibleBy
                row.options = [.open, .closed]
                row.disabled = .init(booleanLiteral: true)
                row.value = .open
            }
            <<< PushRow<PermissionModeUIOption>(Row.groupPermissionMode.rawValue) { row in
                row.title = L10n.CreateMeetup.Group.modifiableBy
                row.options = [.everyone, .admin]
                row.disabled = .init(booleanLiteral: true)
                row.value = .everyone
            }
            +++ Section(L10n.CreateMeetup.MeetingPoint.header)
            <<< LabelRow(Row.meetingPoint.rawValue) { row in
                row.title = L10n.CreateMeetup.MeetingPoint.title
                row.value = meetingPointDescription
            }
    }
}
