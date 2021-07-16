//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Swinject
import SwinjectStoryboard
import PromiseKit

protocol Coordinator: AnyObject {
    var storyboard: UIStoryboard { get }
    var window: UIWindow { get }
    var resolver: Swinject.Resolver { get }
    
    var children: [Coordinator] { get set }
}

extension Coordinator {
    
    func show(title: String?, message: String?, okActionTitle: String = L10n.Alert.ok, completion: (() -> Void)? = nil) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: okActionTitle, style: .default, handler: { _ in
            completion?()
        })
        alertController.addAction(okAction)
        window.topMostViewController?.present(alertController, animated: true, completion: nil)
    }

    func show(error: Error?, okActionTitle: String = L10n.Alert.ok, completion: (() -> Void)? = nil) {
        let title = L10n.Alert.Error.title
        let message: String = error?.localizedDescription ?? L10n.Alert.Error.body
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: okActionTitle, style: .default, handler: { _ in
            completion?()
        })
        alertController.addAction(okAction)
        window.topMostViewController?.present(alertController, animated: true, completion: nil)
    }
    
    func askForUserInput(title: String, message: String, placeholder: String? = "", action: String = L10n.Alert.ok, cancel: String = L10n.Alert.cancel, actionStyle: UIAlertAction.Style = .default) -> Promise<String?> {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        var inputTextField: UITextField?
        alertController.addTextField(configurationHandler: { textField in
            textField.placeholder = placeholder
            inputTextField = textField
        })
        
        let (promise, resolver) = Promise<String?>.pending()
        let okAction = UIAlertAction(title: action, style: actionStyle, handler: { _ in
            resolver.fulfill(inputTextField?.text)
        })
        let cancelAction = UIAlertAction(title: cancel, style: .cancel, handler: { _ in
            resolver.reject(PMKError.cancelled)
        })
        alertController.addAction(okAction)
        alertController.addAction(cancelAction)
        window.topMostViewController?.present(alertController, animated: true, completion: nil)
        return promise
    }

    func askForUserConfirmation(title: String, message: String, action: String = L10n.Alert.ok, cancel: String = L10n.Alert.cancel, actionStyle: UIAlertAction.Style = .default) -> Promise<Void> {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        let (promise, resolver) = Promise<Void>.pending()
        let okAction = UIAlertAction(title: action, style: actionStyle, handler: { _ in
            resolver.fulfill(())
        })
        let cancelAction = UIAlertAction(title: cancel, style: .cancel, handler: { _ in
            resolver.reject(PMKError.cancelled)
        })
        alertController.addAction(okAction)
        alertController.addAction(cancelAction)
        window.topMostViewController?.present(alertController, animated: true, completion: nil)
        return promise
    }

    func showActionSheet<E: ActionSheetOption>(title: String?, message: String?, actions: E..., cancel: String? = L10n.Alert.cancel) -> Promise<E> {
        let actionSheetController = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        let (promise, resolver) = Promise<E>.pending()

        for action in actions {
            let alertAction = UIAlertAction(title: action.description, style: action.style) { _ in
                resolver.fulfill(action)
            }
            actionSheetController.addAction(alertAction)
        }

        if let cancel = cancel {
            let cancelAction = UIAlertAction(title: cancel, style: .cancel) { _ in
                resolver.reject(PMKError.cancelled)
            }
            actionSheetController.addAction(cancelAction)
        }

        window.topMostViewController?.present(actionSheetController, animated: true, completion: nil)
        return promise
    }

    func remove(child: Coordinator) {
        children.removeAll(where: { $0 === child })
    }
}
