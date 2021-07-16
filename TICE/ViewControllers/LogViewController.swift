//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import Foundation
import UIKit

class LogViewController: UIViewController {

    var textView: UITextView!
    var observationToken: ObserverToken?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Logs"

        navigationItem.setLeftBarButton(UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(trashButtonTouched)), animated: false)
        navigationItem.setRightBarButton(UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeButtonTouched)), animated: false)

        view.backgroundColor = .white
        
        textView = UITextView(frame: .zero)
        textView.isEditable = false
        textView.isUserInteractionEnabled = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .systemFont(ofSize: 13.0)
        textView.layoutManager.allowsNonContiguousLayout = false
        view.addSubview(textView)

        let layoutGuide = view!
        textView.contentInsetAdjustmentBehavior = .always
        textView.leadingAnchor.constraint(equalTo: layoutGuide.leadingAnchor).isActive = true
        textView.trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor).isActive = true
        textView.topAnchor.constraint(equalTo: layoutGuide.topAnchor).isActive = true
        textView.bottomAnchor.constraint(equalTo: layoutGuide.bottomAnchor).isActive = true

        do {
            observationToken = try logger.observeLogs { logs in
                DispatchQueue.main.async {
                    self.updateTextView(logs: logs.map(String.init(describing:)))
                }
            }
        } catch {
            logger.error("Failed to observe log database: \(String(describing: error))")
            show(error: error)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        do {
            let logs = try logger.getLogs(logLevel: .trace).map(String.init(describing:))
            updateTextView(logs: logs)
        } catch {
            logger.error("Failed to fetch logs: \(String(describing: error))")
            show(error: error)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.scrollToBottom()
    }
    
    @objc
    func closeButtonTouched(sender: Any?) {
        dismiss(animated: true, completion: nil)
    }
    
    @objc
    func trashButtonTouched(sender: Any?) {
        let alertController = UIAlertController(title: L10n.Logs.ConfirmDeletion.title,
                                                message: L10n.Logs.ConfirmDeletion.body,
                                                preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "alert_cancel", style: .cancel, handler: nil)
        let trashAction = UIAlertAction(title: "logs_delete", style: .destructive, handler: { _ in
            do {
                try logger.deleteAllLogs()
                self.dismiss(animated: true, completion: nil)
            } catch {
                logger.error("Failed to delete all logs: \(String(describing: error))")
            }
        })
        
        alertController.addAction(cancelAction)
        alertController.addAction(trashAction)
        
        present(alertController, animated: true, completion: nil)
    }
    
    func updateTextView(logs: [String]) {
        let wasScrolledToBottom = textView.isScrolledToBottom
        let text = logs.joined(separator: "\n") + "\n\n"
        
        let trimmedText = String(text.suffix(128_000)) // 128 KB is enough
        textView.text = trimmedText

        if wasScrolledToBottom {
            textView.scrollToBottom()
        }
    }
    
    func show(error: Error) {
        let message: String = String(describing: error)
        let alertController = UIAlertController(title: L10n.Alert.Error.title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default)
        alertController.addAction(okAction)
        
        present(alertController, animated: true, completion: nil)
    }
}
