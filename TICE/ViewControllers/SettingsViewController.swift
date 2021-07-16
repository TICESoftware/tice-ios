//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Swinject
import SwinjectStoryboard
import TICEAPIModels
import PromiseKit
import Eureka
import MessageUI
import SafariServices

class SettingsViewController: FormViewController {

    var viewModel: SettingsViewModel! {
        didSet {
            viewModel.delegate = self
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.form = viewModel.generateForm()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    @IBAction func didTapOnDeregister(_ sender: Any) {
        viewModel.didTapOnDeregister()
    }

    func triggerFeedback() {
        let alertController = UIAlertController(title: L10n.Settings.Feedback.AskForLogs.title, message: L10n.Settings.Feedback.AskForLogs.message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: L10n.Settings.Feedback.AskForLogs.agree, style: .default, handler: { _ in self.viewModel.sendFeedback(includingLogs: true) }))
        alertController.addAction(UIAlertAction(title: L10n.Settings.Feedback.AskForLogs.deny, style: .cancel, handler: { _ in self.viewModel.sendFeedback(includingLogs: false) }))
        show(alertController: alertController)
    }

    func showMailComposer(viewController: MFMailComposeViewController) {
        present(viewController, animated: true, completion: nil)
    }

    func setDeregisterButton(enabled: Bool) {
        guard let deregisterRow = form.rowBy(tag: SettingsViewModel.Row.deregister.rawValue) else {
            logger.error("Could not access deregister row.")
            return
        }
        deregisterRow.disabled = Condition(booleanLiteral: enabled)
        deregisterRow.evaluateDisabled()
    }

    func show(alertController: UIAlertController) {
        present(alertController, animated: true, completion: nil)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            return 18
        }

        return UITableView.automaticDimension
    }
}

extension SettingsViewController: MFMailComposeViewControllerDelegate {

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true) {
            switch result {
            case .failed:
                let errorDescription = error.map { String(describing: $0) } ?? "n/a"
                logger.error("Feedback mail could not be sent. Error: \(errorDescription)")
            case .sent:
                let alertController = UIAlertController(title: L10n.Settings.Feedback.ConfirmationAlert.title, message: nil, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: L10n.Settings.Feedback.ConfirmationAlert.button, style: .default, handler: nil))
                self.show(alertController: alertController)
            default:
                break
            }
        }
    }
}

enum SettingsViewModelError: LocalizedError {
    case userParticipatingInTeams

    var errorDescription: String? {
        switch self {
        case .userParticipatingInTeams: return L10n.Error.SettingsViewModel.userParticipatingInTeams
        }
    }
}

class SettingsViewModel {

    weak var coordinator: MainFlow!
    weak var delegate: SettingsViewController?

    let backend: TICEAPI
    let signedInUser: SignedInUser
    let teamManager: TeamManagerType
    let signedInUserManager: SignedInUserManagerType
    let locationManager: LocationManagerType
    let nameSupplier: NameSupplierType
    let tracker: TrackerType
    let demoManager: DemoManagerType
    
    let logHistoryOffsetUserFeedback: TimeInterval
    
    let signedInUserStorageManager: SignedInUserStorageManagerType
    let groupStorageManager: GroupStorageManagerType
    let postOfficeStorageManager: PostOfficeStorageManagerType
    let conversationStorageManager: ConversationStorageManagerType
    let locationStorageManager: LocationStorageManagerType
    let userStorageManager: UserStorageManagerType
	let chatStorageManager: ChatStorageManagerType
    let demoStorageManager: DemoStorageManagerType
    let cryptoStorageManager: DeletableStorageManagerType

    init(coordinator: MainFlow, backend: TICEAPI, signedInUser: SignedInUser, teamManager: TeamManagerType, groupManager: GroupManagerType, signedInUserManager: SignedInUserManagerType, locationManager: LocationManagerType, nameSupplier: NameSupplierType, tracker: TrackerType, demoManager: DemoManagerType, logHistoryOffsetUserFeedback: TimeInterval, signedInUserStorageManager: SignedInUserStorageManagerType, groupStorageManager: GroupStorageManagerType, postOfficeStorageManager: PostOfficeStorageManagerType, conversationStorageManager: ConversationStorageManagerType, locationStorageManager: LocationStorageManagerType, userStorageManager: UserStorageManagerType, chatStorageManager: ChatStorageManagerType, demoStorageManager: DemoStorageManagerType, cryptoStorageManager: DeletableStorageManagerType) {
        self.coordinator = coordinator
        self.backend = backend
        self.signedInUser = signedInUser
        self.teamManager = teamManager
        self.signedInUserManager = signedInUserManager
        self.locationManager = locationManager
        self.nameSupplier = nameSupplier
        self.tracker = tracker
        self.demoManager = demoManager
        
        self.logHistoryOffsetUserFeedback = logHistoryOffsetUserFeedback

        self.signedInUserStorageManager = signedInUserStorageManager
        self.groupStorageManager = groupStorageManager
        self.postOfficeStorageManager = postOfficeStorageManager
        self.conversationStorageManager = conversationStorageManager
        self.locationStorageManager = locationStorageManager
        self.userStorageManager = userStorageManager
        self.chatStorageManager = chatStorageManager
        self.demoStorageManager = demoStorageManager
        self.cryptoStorageManager = cryptoStorageManager
    }

    enum Row: String {
        case name
        case readPrivacyPolicy
        case stopLocationSharing
        case giveFeedback
        case feedbackLogs
        case resetDemo
        case deregister
    }

    func generateForm() -> Form {
        let form = Form()
            +++ Section(footer: L10n.Settings.Name.footer)
            <<< TextRow(Row.name.rawValue) { row in
                row.title = L10n.Settings.Name.title
                row.placeholder = nameSupplier.name(user: signedInUser)
                row.value = signedInUser.publicName
                row.onChange { row in
                    print(row)
                }
                row.onCellHighlightChanged { _, row in
                    if !row.isHighlighted {
                        self.changedName(newName: row.value)
                    }
                }
            }
            +++ Section(header: L10n.Settings.Encryption.header,
                        footer: L10n.Settings.Encryption.footer)
            +++ Section(L10n.Settings.Other.header)
            <<< ButtonRow(Row.giveFeedback.rawValue) { row in
                row.title = L10n.Settings.Feedback.give
                row.cell.tintColor = UIColor.highlight
                row.cellUpdate { cell, _ in
                    cell.tintColor = UIColor.highlight
                    cell.textLabel?.textAlignment = .left
                }
                row.onCellSelection { _, _ in
                    self.delegate?.triggerFeedback()
                }
            }
            <<< ButtonRow(Row.resetDemo.rawValue) { row in
                row.title = L10n.Settings.Demo.reset
                row.cellSetup { cell, _ in
                    cell.accessibilityIdentifier = "settings_demo_reset"
                }
                row.cellUpdate { cell, _ in
                    cell.tintColor = UIColor.highlight
                    cell.textLabel?.textAlignment = .left
                }
                row.onCellSelection { _, _ in
                    self.resetDemo()
                }
            }
            <<< ButtonRow(Row.readPrivacyPolicy.rawValue) { row in
                row.title = L10n.Settings.Privacy.readPolicy
                row.cellUpdate { cell, _ in
                    cell.tintColor = UIColor.highlight
                    cell.textLabel?.textAlignment = .left
                }
                row.onCellSelection { _, _ in
                    self.openPrivacyPolicy()
                }
            }
            +++ Section(L10n.Settings.Account.header)
            <<< ButtonRow(Row.deregister.rawValue) { row in
                row.title = L10n.Settings.Account.delete
                row.cellSetup { cell, _ in
                    cell.accessibilityIdentifier = "settings_account_delete"
                }
                row.cellUpdate { cell, _ in
                    cell.tintColor = UIColor.destructive
                    cell.textLabel?.textAlignment = .left
                }
                row.onCellSelection { _, _ in
                    self.didTapOnDeregister()
                }
            }
        
        let versionFooter = L10n.Settings.About.footer("\(Bundle.main.appVersion)")
        let footerText: String
        #if PRODUCTION
        footerText = versionFooter
        #else
        let formattedRevision = "Revision \(Bundle.main.appRevision)\(Bundle.main.appRevisionDirty ? "*" : "")"
        footerText = "\(versionFooter)\n\(formattedRevision)"
        #endif
        
        form +++ Section(header: L10n.Settings.About.header,
                         footer: footerText)
        
        return form
    }

    func sendFeedback(includingLogs: Bool) {
        guard MFMailComposeViewController.canSendMail() else {
            logger.error("Device is not capable of sending mails.")
            let alertController = UIAlertController(title: L10n.Settings.Feedback.MailError.title, message: L10n.Settings.Feedback.MailError.message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: L10n.Settings.Feedback.MailError.button, style: .default, handler: nil))
            delegate?.show(alertController: alertController)
            return
        }
        
        let composeMailViewController = MFMailComposeViewController()
        composeMailViewController.mailComposeDelegate = delegate

        composeMailViewController.setToRecipients(["feedback@ticeapp.com"])
        composeMailViewController.setSubject("TICE: Feedback")

        if includingLogs {
            let fileName = "logs_\(Bundle.main.verboseVersionString).zip"
            do {
                let logData = try logger.generateCompressedLogData(logLevel: .debug, since: Date().addingTimeInterval(logHistoryOffsetUserFeedback))
                composeMailViewController.addAttachmentData(logData, mimeType: "application/zip", fileName: fileName)
            } catch {
                logger.error("Failed to generate log attachment: \(String(describing: error))")
            }
        }

        delegate?.showMailComposer(viewController: composeMailViewController)
    }
    
    func didTapOnDeregister() {
        delegate?.setDeregisterButton(enabled: false)

        firstly { () -> Promise<Void> in
            guard self.teamManager.teams.isEmpty else {
                throw SettingsViewModelError.userParticipatingInTeams
            }
            
            return coordinator.askForUserConfirmation(title: L10n.Settings.Account.ConfirmDeletion.title,
                                                       message: L10n.Settings.Account.ConfirmDeletion.message,
                                                       action: L10n.Settings.Account.ConfirmDeletion.delete,
                                                       actionStyle: .destructive)
        }.then { () -> Promise<Void> in
            return self.backend.deleteUser(userId: self.signedInUser.userId)
        }.recover { error in
            if let apiError = error as? APIError,
                case .authenticationFailed = apiError.type {
                logger.warning("User isn't existing anymore. Finishing teardown.")
                return ()
            }
            throw error
        }.done { _ in
            try self.signedInUserManager.signOut()

            self.signedInUserStorageManager.deleteAllData()
            self.groupStorageManager.deleteAllData()
            self.postOfficeStorageManager.deleteAllData()
            self.conversationStorageManager.deleteAllData()
            self.locationStorageManager.deleteAllData()
            self.userStorageManager.deleteAllData()
            self.chatStorageManager.deleteAllData()
            self.demoStorageManager.deleteAllData()
            self.cryptoStorageManager.deleteAllData()

            self.deregister()
        }.done { _ in
            self.tracker.log(action: .deleteAccount, category: .app, detail: "SUCCESS")
        }.catch(policy: .allErrors) { error in
            self.tracker.log(action: .deleteAccount, category: .app, detail: error.isCancelled ? "CANCELLED" : "ERROR")
            guard !error.isCancelled else { return }
            
            logger.error("User could not be deleted. \(error.localizedDescription)")
            self.coordinator?.failDeregisterUser(error: error)
        }.finally {
            self.delegate?.setDeregisterButton(enabled: true)
        }
    }

    func changedName(newName: String?) {
        firstly { () -> Promise<Void> in
            backend.updateUser(userId: signedInUser.userId, publicKeys: nil, deviceId: nil, verificationCode: nil, publicName: newName)
        }.done { _ in
            try self.signedInUserManager.changePublicName(to: newName)
        }.done { _ in
            self.tracker.log(action: .changeName, category: .app, detail: "SUCCESS")
        }.catch(policy: .allErrors) { error in
            self.tracker.log(action: .changeName, category: .app, detail: error.isCancelled ? "CANCELLED" : "ERROR")
            guard !error.isCancelled else { return }
            
            logger.error("User could not be renamed. \(error.localizedDescription)")
            self.coordinator?.failRenameUser(error: error)
        }
    }

    func deregister() {
        let application = UIApplication.shared

        // swiftlint:disable force_cast
        let appDelegate = application.delegate as! AppDelegate
        let window = application.windows.first { $0.isKeyWindow }!
        // swiftlint:enable force_cast

        appDelegate.setup(window: window, application: application)
    }
    
    func openPrivacyPolicy() {
        let urlString = L10n.Settings.Privacy.url
        guard let url = URL(string: urlString) else { return }

        let safari = SFSafariViewController(url: url)
        delegate?.present(safari, animated: true, completion: nil)
    }
    
    func resetDemo() {
        tracker.log(action: .resetDemo, category: .app, detail: "Settings")
        demoManager.resetDemo()
        coordinator.show(title: L10n.Settings.Demo.DidReset.title, message: L10n.Settings.Demo.DidReset.body)
    }
}
