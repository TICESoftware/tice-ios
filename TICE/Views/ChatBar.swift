//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import UIKit
import Foundation
import ChattoAdditions

class ChatBar: ChatInputBar {
    
    @IBOutlet weak var internalTextView: ExpandableTextView!
    
    class func loadCustomNib() -> ChatBar {
        // swiftlint:disable:next force_cast
        let view = Bundle(for: self).loadNibNamed("ChatBar", owner: nil, options: nil)!.first as! ChatBar
        view.translatesAutoresizingMaskIntoConstraints = false
        view.frame = CGRect.zero
        return view
    }
    
    override func textView(_ textView: UITextView, shouldChangeTextIn nsRange: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            self.presenter?.onSendButtonPressed()
            self.delegate?.inputBarSendButtonPressed(self)
            return false
        }
        return super.textView(textView, shouldChangeTextIn: nsRange, replacementText: text)
    }
    
    var isEnabled: Bool = true {
        didSet {
            internalTextView.isEditable = isEnabled
        }
    }
}
