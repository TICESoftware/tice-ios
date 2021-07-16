//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

class ChatWidget: UIView {
    @IBOutlet var chatButton: UIButton!
    @IBOutlet var bubbleView: UIImageView!
    @IBOutlet var messageLabel: UILabel!
    @IBOutlet var avatarView: UIImageView!
    
    func setup() {
        let image = UIImage(named: "bubble")!
        bubbleView.image = image.resizableImage(withCapInsets: UIEdgeInsets(top: 18, left: 18, bottom: 24, right: 27), resizingMode: .stretch)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        
        if hitView == self {
            return nil
        }
        
        return hitView
    }
    
    func setText(_ text: String) {
        messageLabel.text = text
        let size = messageLabel.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        messageLabel.frame.size = size
    }
}
