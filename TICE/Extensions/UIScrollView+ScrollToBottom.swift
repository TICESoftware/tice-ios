//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import UIKit

extension UITextView {
    func scrollToBottom() {
        guard !text.isEmpty else { return }
        scrollRangeToVisible(NSRange(location: text.count - 1, length: 1))
    }

    var isScrolledToBottom: Bool {
        let offsetY = max(0, contentSize.height - bounds.height)
        return contentOffset.y >= offsetY
    }
}
