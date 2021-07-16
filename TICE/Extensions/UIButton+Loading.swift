//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

extension UIBarButtonItem {
    func startLoading() {
        isEnabled = false

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        customView = activityIndicator
        activityIndicator.startAnimating()
    }

    func stopLoading() {
        customView = nil
        isEnabled = true
    }
}

extension UIButton {
    func startLoading() {
        isEnabled = false

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.tag = 808404
        activityIndicator.hidesWhenStopped = true
        activityIndicator.accessibilityHint = self.title(for: .normal)

        setTitle(nil, for: .normal)
        addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        activityIndicator.startAnimating()
    }

    func stopLoading() {
        guard let activityIndicator = self.viewWithTag(808404) as? UIActivityIndicatorView else { return }
        activityIndicator.stopAnimating()
        activityIndicator.removeFromSuperview()

        setTitle(activityIndicator.accessibilityHint, for: .normal)
        
        isEnabled = true
    }
}
