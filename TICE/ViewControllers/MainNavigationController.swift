//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

protocol ShowsLargeButton {
    var showsLargeButton: Bool { get }
    var largeButtonAccessibilityIdentifier: String? { get }
    var largeButtonImage: UIImage? { get }
    var largeButtonAction: (() -> Void)? { get }
}

class MainNavigationController: UINavigationController {
    
    var largeButtonAction: (() -> Void)?
    
    lazy var largeButton: UIButton! = {
        let button = UIButton()
        button.contentHorizontalAlignment = .fill
        button.contentVerticalAlignment = .fill
        button.imageEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 16)
        button.backgroundColor = .highlightBackground
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(didTapLargeButton), for: .touchUpInside)
        return button
    }()
    
    @objc
    func didTapLargeButton() {
        largeButtonAction?()
    }
    
    private func addLargeButton() {
        navigationBar.subviews.forEach { subview in
            let stringFromClass = NSStringFromClass(subview.classForCoder)
            guard stringFromClass.contains("UINavigationBarLargeTitleView") else { return }
            subview.subviews.forEach { label in
                guard label is UILabel else { return }
                subview.addSubview(largeButton)
                NSLayoutConstraint.activate([
                    subview.rightAnchor.constraint(equalTo: largeButton.rightAnchor, constant: 0),
                    subview.bottomAnchor.constraint(equalTo: largeButton.bottomAnchor, constant: 0),
                    largeButton.heightAnchor.constraint(equalToConstant: 60),
                    largeButton.widthAnchor.constraint(equalToConstant: 68)
                ])
            }
        }
    }
    
    public func showLargeButton(_ show: Bool, animated: Bool = true) {
        if show && largeButton.superview == nil {
            addLargeButton()
        }
        
        if animated {
            UIView.animate(withDuration: 0.2) {
                self.largeButton.alpha = show ? 1.0 : 0.0
            }
        } else {
            self.largeButton.alpha = show ? 1.0 : 0.0
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if let vc = self.topMostViewController as? ShowsLargeButton, vc.showsLargeButton {
            self.largeButton.setImage(vc.largeButtonImage, for: .normal)
            self.largeButton.accessibilityIdentifier = vc.largeButtonAccessibilityIdentifier
            self.largeButtonAction = vc.largeButtonAction
            showLargeButton(true)
        } else {
            showLargeButton(false)
        }
    }
}
