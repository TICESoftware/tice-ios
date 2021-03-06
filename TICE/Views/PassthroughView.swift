//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)

        if view == self {
            return nil
        } else {
            return view
        }
    }
}

extension UIView {

    func constrainToParent() {
        constrainToParent(insets: .zero)
    }

    func constrainToParent(insets: UIEdgeInsets) {
        guard let parent = superview else { return }

        translatesAutoresizingMaskIntoConstraints = false
        let metrics: [String: Any] = ["left": insets.left, "right": insets.right, "top": insets.top, "bottom": insets.bottom]

        parent.addConstraints(["H:|-(left)-[view]-(right)-|", "V:|-(top)-[view]-(bottom)-|"].flatMap {
            NSLayoutConstraint.constraints(withVisualFormat: $0, metrics: metrics, views: ["view": self])
        })
    }
}
