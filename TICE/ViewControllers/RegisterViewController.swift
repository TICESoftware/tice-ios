//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import TICEAPIModels
import PromiseKit
import Swinject

enum RegisterState {
    case enabled
    case disabled(error: String?)
    case loading
}

class RegisterViewController: UIViewController, UITextFieldDelegate {
    var viewModel: RegisterViewModelType!

    @IBOutlet weak var registerButton: UIButton!
    @IBOutlet weak var cancelRegisteringButton: UIButton!
    @IBOutlet weak var buttonsContainer: UIView!
    @IBOutlet weak var publicNameTextField: UITextField!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        publicNameTextField.layer.borderColor = UIColor.warning.cgColor
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cancelRegisteringButton.isHidden = true
        viewModel.enter()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        publicNameTextField.becomeFirstResponder()
    }

    var publicName: String? {
        guard let name = publicNameTextField.text else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty ? trimmedName : nil
    }

    @IBAction func didTapOnRegisterButton(_ sender: Any) {
        viewModel.didTapOnRegister(publicName: publicName)
    }
    
    @IBAction func didTapCancelButton(_ sender: Any) {
        viewModel.didTapCancel()
    }
    
    @IBAction func textFieldDidChange(_ sender: Any) {
        viewModel.update(publicName: publicNameTextField.text)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == publicNameTextField {
            viewModel.didTapOnRegister(publicName: publicName)
        }
        return true
    }
    
    func updateRegisterButton(state: RegisterState) {
        switch state {
        case .loading:
            activityIndicator.startAnimating()
            registerButton.isEnabled = false
            registerButton.backgroundColor = .lightGray
            registerButton.setTitle("", for: .disabled)
            publicNameTextField.layer.borderWidth = 0
            publicNameTextField.isEnabled = false
        case .enabled:
            activityIndicator.stopAnimating()
            registerButton.isEnabled = true
            registerButton.backgroundColor = .highlightBackground
            publicNameTextField.layer.borderWidth = 0
            publicNameTextField.isEnabled = true
        case .disabled(let error):
            activityIndicator.stopAnimating()
            registerButton.isEnabled = false
            registerButton.backgroundColor = .lightGray
            registerButton.setTitle(L10n.Register.register, for: .disabled)
            publicNameTextField.isEnabled = true
            publicNameTextField.layer.borderWidth = error != nil ? 2 : 0
        }
    }
    
    func updateCancelButton(show: Bool) {
        cancelRegisteringButton.isHidden = !show
    }
}

class DebugRegisterViewController: RegisterViewController {

    @IBOutlet weak var groupIdentifierField: UITextField!
    @IBOutlet weak var plainModeSwitch: UISwitch!

    override func viewDidLoad() {
        super.viewDidLoad()

        plainModeSwitch.isOn = UserDefaults.standard.bool(forKey: "USE_PLAIN")
    }
    
    override func updateRegisterButton(state: RegisterState) {
        switch state {
        case .loading:
            activityIndicator.startAnimating()
            buttonsContainer.isHidden = true
        case .enabled:
            activityIndicator.stopAnimating()
            buttonsContainer.isHidden = false
        case .disabled:
            activityIndicator.stopAnimating()
            buttonsContainer.isHidden = false
        }
    }

    @IBAction override func didTapOnRegisterButton(_ sender: Any) {
        viewModel.didTapOnRegister(publicName: publicName)
    }

    @IBAction func didTapOnRegisterAndCreateGroupButton(_ sender: Any) {
        viewModel.didTapOnRegisterAndCreateGroup(publicName: publicName)
    }

    @IBAction func didTapOnRegisterAndJoinGroupButton(_ sender: Any) {
        let shareString = groupIdentifierField.text
        viewModel.didTapOnRegisterAndJoinGroup(publicName: publicName, shareString: shareString)
    }

    @IBAction func plainModeValueChanged(_ sender: UISwitch) {
        logger.debug("Set plain mode to \(sender.isOn)")
        UserDefaults.standard.set(sender.isOn, forKey: "USE_PLAIN")
    }
}

enum RegisterError: String, LocalizedError {
    case timeout
    case couldNotGetDeviceToken
    case invalidVerificationMessage
    case invalidInput
    case missingGroupId
    case invalidGroupURL

    var errorDescription: String? {
        return self.rawValue
    }
}

protocol RegisterViewModelType {
    var delegate: RegisterViewController? { get set }
    func enter()
    func update(publicName: String?)
    func didTapOnRegister(publicName: String?)
    func didTapCancel()
    func didTapOnRegisterAndCreateGroup(publicName: String?)
    func didTapOnRegisterAndJoinGroup(publicName: String?, shareString: String?)
}

struct CreateUserInfo {
    let createUserResponse: CreateUserResponse
    let publicKey: PublicKey
    let privateKey: PrivateKey
}

class RegisterViewModel: RegisterViewModelType {

    unowned let coordinator: RegisterFlow

    let cryptoManager: CryptoManagerType
    let conversationCryptoMiddleware: ConversationCryptoMiddlewareType
    let deviceTokenManager: DeviceTokenManagerType
    let signedInUserManager: SignedInUserManagerType
    let backend: TICEAPI
    let demoManager: DemoManagerType
    let notifier: Notifier
    let tracker: TrackerType
    let resolver: Swinject.Resolver
    let showCancelTimeout: TimeInterval
    let timeout: TimeInterval
    let backendBaseURL: URL

    weak var delegate: RegisterViewController?

    var registrationTimer: Timer?
    var cancelHandler: (() -> Void)?

    init(coordinator: RegisterFlow, cryptoManager: CryptoManagerType, conversationCryptoMiddleware: ConversationCryptoMiddlewareType, deviceTokenManager: DeviceTokenManagerType, signedInUserController: SignedInUserManagerType, backend: TICEAPI, demoManager: DemoManagerType, notifier: Notifier, tracker: TrackerType, resolver: Swinject.Resolver, showCancelTimeout: TimeInterval, timeout: TimeInterval, backendBaseURL: URL) {
        self.coordinator = coordinator
        self.cryptoManager = cryptoManager
        self.conversationCryptoMiddleware = conversationCryptoMiddleware
        self.deviceTokenManager = deviceTokenManager
        self.signedInUserManager = signedInUserController
        self.backend = backend
        self.demoManager = demoManager
        self.notifier = notifier
        self.tracker = tracker
        self.resolver = resolver
        self.showCancelTimeout = showCancelTimeout
        self.timeout = timeout
        self.backendBaseURL = backendBaseURL
    }

    func register(publicName: String?) -> Promise<SignedInUser> {
        tracker.log(action: .register, category: .register, detail: publicName != nil ? "NAMED" : "UNNAMED")
        
        delegate?.updateCancelButton(show: false)
        
        registrationTimer?.invalidate()
        registrationTimer = Timer.scheduledTimer(withTimeInterval: showCancelTimeout, repeats: false, block: { _ in
            DispatchQueue.main.async {
                self.delegate?.updateCancelButton(show: true)
            }
        })

        var canceled = false
        cancelHandler = { canceled = true }
        
        return firstly { () -> Promise<DeviceVerification> in
            deviceTokenManager.registerDevice(remoteNotificationsRegistry: UIApplication.shared, forceRefresh: false)
        }.timeout(seconds: timeout) {
            throw RegisterError.timeout
        }.then { deviceVerification -> Promise<SignedInUser> in
            guard !canceled else { throw PMKError.cancelled }
            self.registrationTimer?.invalidate()
            DispatchQueue.main.async { self.delegate?.updateCancelButton(show: false) }
            return self.createUser(deviceToken: deviceVerification.deviceToken, verificationCode: deviceVerification.verificationCode, publicName: publicName)
        }.get { signedInUser in
            try self.signedInUserManager.signIn(signedInUser)
            self.signedInUserManager.teamBroadcaster = self.resolver.resolve(TeamBroadcaster.self)!
            self.demoManager.didRegister()
        }.ensure {
            self.cancelHandler = nil
            self.registrationTimer = nil
            self.delegate?.updateCancelButton(show: false)
        }
    }

    var isRegistering = false {
        didSet { updateRegisterState() }
    }
    var publicName = "" {
        didSet { updateRegisterState() }
    }
    var error: String? {
        didSet { updateRegisterState() }
    }
    var registerState: RegisterState = .disabled(error: nil) {
        didSet { delegate?.updateRegisterButton(state: registerState) }
    }
    
    func enter() {
        delegate?.updateRegisterButton(state: registerState)
    }
    
    func update(publicName: String?) {
        self.publicName = publicName ?? ""
        
        if self.publicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.error = L10n.Register.Name.emptyError
        } else {
            self.error = nil
        }
        
        self.updateRegisterState()
    }
    
    func updateRegisterState() {
        if isRegistering {
            self.registerState = .loading
            return
       }
        
        if let error = error {
            self.registerState = .disabled(error: error)
            return
        }
        
        if publicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.registerState = .disabled(error: nil)
            return
        }
        
        self.registerState = .enabled
    }
    
    func didTapOnRegister(publicName: String?) {
        guard !isRegistering else { return }
        
        isRegistering = true
        updateRegisterState()
        
        let startTime = Date()
        logger.info("User will register")
        firstly { () -> Promise<SignedInUser> in
            return register(publicName: publicName)
        }.done { _ in
            logger.info("User did register")
            self.tracker.log(action: .didRegister, category: .register, detail: nil, number: -startTime.timeIntervalSinceNow)
            self.coordinator.finish()
        }.catch(policy: .allErrors) { error in
            logger.error("Could not register. Reason: \(String(describing: error))")
            self.tracker.log(action: .error, category: .register, detail: String(describing: error), number: -startTime.timeIntervalSinceNow)
            
            if case .cancelled = error as? PMKError { return }
            self.coordinator.fail(error: error)
        }.finally {
            self.isRegistering = false
        }
    }
    
    func didTapCancel() {
        cancelHandler?()
    }

    func didTapOnRegisterAndCreateGroup(publicName: String?) {
        firstly { () -> Promise<SignedInUser> in
            isRegistering = true
            return register(publicName: publicName)
        }.then { _ -> Promise<Team> in
            let teamManager = self.resolver.resolve(TeamManagerType.self)!
            return teamManager.createTeam(joinMode: .open, permissionMode: .admin, name: nil, shareLocation: false, meetingPoint: nil)
        }.done { _ in
            self.coordinator.finish()
        }.ensure {
            self.isRegistering = true
        }.catch { error in
            self.coordinator.fail(error: error)
        }
    }

    func didTapOnRegisterAndJoinGroup(publicName: String?, shareString: String?) {

        guard let shareString = shareString,
            let truncated = shareString.split(separator: "/").last else {
            self.coordinator.fail(error: RegisterError.missingGroupId)
            return
        }

        let groupString = String(truncated)

        firstly { () -> Promise<SignedInUser> in
            self.isRegistering = true
            return register(publicName: publicName)
        }.then { _ -> Promise<Team> in
            let baseURL = self.backendBaseURL.absoluteString
            guard let url = URL(string: "\(baseURL)/group/\(groupString)") else {
                throw RegisterError.invalidGroupURL
            }

            let deepLinkParser = self.resolver.resolve(DeepLinkParserType.self)!
            return deepLinkParser.team(url: url)
        }.then { team -> Promise<Team> in
            let teamManager = self.resolver.resolve(TeamManagerType.self)!
            return teamManager.join(team)
        }.done { _ in
            self.coordinator.finish()
        }.ensure {
            self.isRegistering = false
        }.catch { error in
            self.coordinator.fail(error: error)
        }
    }

    func createUser(deviceToken: Data, verificationCode: String, publicName: String?) -> Promise<SignedInUser> {
        return firstly { () -> Promise<(CreateUserResponse, KeyPair)> in
            let signingKeyPair = try cryptoManager.generateSigningKeyPair()
            let publicKeyMaterial = try conversationCryptoMiddleware.renewHandshakeKeyMaterial(privateSigningKey: signingKeyPair.privateKey)
            let userPublicKeys = UserPublicKeys(signingKey: signingKeyPair.publicKey, identityKey: publicKeyMaterial.identityKey, signedPrekey: publicKeyMaterial.signedPrekey, prekeySignature: publicKeyMaterial.prekeySignature, oneTimePrekeys: publicKeyMaterial.oneTimePrekeys)
            return backend.createUser(publicKeys: userPublicKeys, platform: .iOS, deviceId: deviceToken, verificationCode: verificationCode, publicName: publicName).map { ($0, signingKeyPair) }
        }.map { createUserResponse, signingKeyPair in
            SignedInUser(userId: createUserResponse.userId, privateSigningKey: signingKeyPair.privateKey, publicSigningKey: signingKeyPair.publicKey, publicName: publicName)
        }
    }
}
