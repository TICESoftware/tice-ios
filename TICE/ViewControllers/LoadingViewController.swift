//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import PromiseKit
import ConvAPI

protocol LoadingViewModelType {
    var delegate: LoadingViewController? { get set }
    func enter()
    func retry()
}

class LoadingViewController: UIViewController {

    var viewModel: LoadingViewModelType! {
        didSet {
            viewModel.delegate = self
        }
    }

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var bodyLabel: UILabel!
    @IBOutlet weak var retryContainer: UIStackView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.enter()
    }

    @IBAction func reloadButtonTapped(_ sender: Any?) {
        viewModel.retry()
    }

    func show(title: String?, body: String?) {
        titleLabel.text = title
        bodyLabel.text = body
    }
}

class ForceUpdateViewModel: LoadingViewModelType {

    let updateChecker: UpdateCheckerType
    let coordinator: AppFlow

    init(updateChecker: UpdateCheckerType, coordinator: AppFlow) {
        self.updateChecker = updateChecker
        self.coordinator = coordinator
    }

    var reloading = false
    weak var delegate: LoadingViewController?
    
    func enter() {
        checkVersion(delay: false)
    }
    
    func retry() {
        checkVersion(delay: true)
    }

    func checkVersion(delay: Bool) {
        guard !reloading else { return }
        reloading = true

        delegate?.activityIndicator.startAnimating()
        delegate?.retryContainer.isHidden = true

        after(seconds: delay ? 0.5 : 0.0).then {
            self.updateChecker.check()
        }.done {
            self.coordinator.finishUpdateChecking()
        }.catch { error in
            self.delegate?.retryContainer.isHidden = false

            if let updateCheckerError = error as? UpdateCheckerError {
                self.delegate?.show(title: L10n.Update.title, body: updateCheckerError.localizedDescription)
            } else {
                let nsError = error as NSError
                self.delegate?.show(title: L10n.Update.title, body: L10n.Update.Error.generic(error.localizedDescription, nsError.localizedRecoverySuggestion ?? L10n.Update.Error.recovery))
            }
        }.finally {
            self.reloading = false
            self.delegate?.activityIndicator.stopAnimating()
        }
    }
}
