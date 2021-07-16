//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Observable

struct MeetupViewModel {

    var visible: MutableObservable<Bool>
    var title: MutableObservable<String>
    var titleColor: MutableObservable<UIColor>
    var description: MutableObservable<String?>
    var descriptionColor: MutableObservable<UIColor>
    var backgroundColor: MutableObservable<UIColor>
    var iconImage: MutableObservable<UIImage?>
    var showDisclosureIndicator: MutableObservable<Bool>

    init(visible: Bool, title: String, titleColor: UIColor, description: String?, descriptionColor: UIColor, backgroundColor: UIColor, iconImage: UIImage?, showDisclosureIndicator: Bool) {
        self.visible = MutableObservable(visible)
        self.title = MutableObservable(title)
        self.titleColor = MutableObservable(titleColor)
        self.description = MutableObservable(description)
        self.descriptionColor = MutableObservable(descriptionColor)
        self.backgroundColor = MutableObservable(backgroundColor)
        self.iconImage = MutableObservable(iconImage)
        self.showDisclosureIndicator = MutableObservable(showDisclosureIndicator)
    }
}
