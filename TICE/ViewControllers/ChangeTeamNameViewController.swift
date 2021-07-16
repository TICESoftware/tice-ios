//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Eureka
import TICEAPIModels
import PromiseKit

enum ChangeTeamNameError: LocalizedError {
    case empty
    case tooLong
    case wasRenamed

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Name can not be empty"
        case .tooLong:
            return "Name is too long"
        case .wasRenamed:
            return "Team was just renamed. Please try again."
        }
    }
}

class ChangeTeamNameViewController: FormViewController {

    weak var coordinator: ChangeNameFlow?

    @IBOutlet var doneButton: UIBarButtonItem!

    var teamManager: TeamManagerType!
    var nameSupplier: NameSupplierType!
    
    var team: Team!
    var groupNameLimit: Int!

    private enum Row: String {
        case name
    }

    @IBAction func didTapCancel() {
        self.coordinator?.cancel()
    }

    @IBAction func didTapFinish() {
        guard let team = self.team else { return }
        
        firstly { () -> Promise<Void> in
            let name = try validate(name: form.values()[Row.name.rawValue] as? String)
            return teamManager.setTeamName(team: team, name: name).recover { error -> Promise<Void> in
                guard let apiError = error as? APIError, case .invalidGroupTag = apiError.type else {
                    throw error
                }
                return self.teamManager.reload(team: team, reloadMeetup: false).get { reloadedTeam in
                    self.team = reloadedTeam
                }.then { reloadedTeam -> Promise<Void> in
                    guard reloadedTeam.name != name else { return .value }
                    guard team.name == reloadedTeam.name else { throw ChangeTeamNameError.wasRenamed }
                    return self.teamManager.setTeamName(team: reloadedTeam, name: name)
                }
            }
        }.done { _ in
            self.coordinator?.done()
        }.catch { error in
            self.coordinator?.show(error: error)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        form = Form()
            +++ Section("")
            <<< TextRow(Row.name.rawValue) { row in
                row.title = L10n.ChangeGroupName.Name.title
                row.value = team.name
                row.placeholder = nameSupplier.groupNameByOwner(owner: team.owner)
                row.cellSetup { cell, row in
                    cell.textField.becomeFirstResponder()
                    row.reload()
                }
                row.add(rule: RuleClosure(closure: { name -> ValidationError? in
                    do {
                        _ = try self.validate(name: name)
                        return nil
                    } catch {
                        return ValidationError(msg: error.localizedDescription)
                    }
                }))
                row.validationOptions = .validatesOnChange

                row.onRowValidationChanged { _, row in
                    self.doneButton.isEnabled = row.isValid
                }
            }
    }

    func validate(name: String?) throws -> String? {
        guard let name = name else {
            return nil
        }

        let trimmedName = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        guard trimmedName.count <= groupNameLimit else {
            throw ChangeTeamNameError.tooLong
        }

        guard !trimmedName.isEmpty else {
            return nil
        }
        
        return trimmedName
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            return 18
        }

        return UITableView.automaticDimension
    }
}
