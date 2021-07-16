//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

class LocalizableLabel: UILabel {

    @IBInspectable var localizationKey: String = "" {
        didSet {
            #if TARGET_INTERFACE_BUILDER
                let bundle = Bundle(for: type(of: self))
                text = bundle.localizedString(forKey: localizationKey, value: "", table: nil)
            #else
                text = NSLocalizedString(localizationKey, comment: "")
            #endif
            accessibilityIdentifier = localizationKey
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        preferredMaxLayoutWidth = frame.size.width
        layoutIfNeeded()
    }
}

class LocalizableButton: UIButton {

    @IBInspectable var localizationKey: String = "" {
        didSet {
            #if TARGET_INTERFACE_BUILDER
                let bundle = Bundle(for: type(of: self))
                setTitle(bundle.localizedString(forKey: localizationKey, value: "", table: nil), for: .normal)
            #else
                setTitle(NSLocalizedString(localizationKey, comment: ""), for: .normal)
            #endif
            accessibilityIdentifier = localizationKey
        }
    }

    override func setTitle(_ title: String?, for state: UIControl.State) {
        #if TARGET_INTERFACE_BUILDER
            let bundle = Bundle(for: type(of: self))
            super.setTitle(bundle.localizedString(forKey: localizationKey, value: "", table: nil), for: .normal)
        #else
            super.setTitle(title, for: state)
        #endif
    }

}

class LocalizableNavigationItem: UINavigationItem {
    @IBInspectable var localizationKey: String = "" {
        didSet {
            #if TARGET_INTERFACE_BUILDER
                let bundle = Bundle(for: type(of: self))
                title = bundle.localizedString(forKey: localizationKey, value: "", table: nil)
            #else
                title = NSLocalizedString(localizationKey, comment: "")
            #endif
        }
    }
}

class LocalizableBarButtonItem: UIBarButtonItem {
    @IBInspectable var localizationKey: String = "" {
        didSet {
            #if TARGET_INTERFACE_BUILDER
                let bundle = Bundle(for: type(of: self))
                title = bundle.localizedString(forKey: localizationKey, value: "", table: nil)
            #else
                title = NSLocalizedString(localizationKey, comment: "")
            #endif
            accessibilityIdentifier = localizationKey
        }
    }
}

class LocalizableTextField: UITextField {
    @IBInspectable var placeholderLocalizationKey: String = "" {
        didSet {
            #if TARGET_INTERFACE_BUILDER
                let bundle = Bundle(for: type(of: self))
                self.placeholder = bundle.localizedString(forKey: placeholderLocalizationKey, value: "", table: nil)
            #else
                self.placeholder = NSLocalizedString(placeholderLocalizationKey, comment: "")
            #endif
            accessibilityIdentifier = placeholderLocalizationKey
        }
    }
}
