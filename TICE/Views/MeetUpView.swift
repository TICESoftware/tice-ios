//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Observable

class MeetupView: UIView {

    @IBOutlet var button: UIButton!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var descriptionLabel: UILabel!
    @IBOutlet var blurContainer: UIVisualEffectView!
    @IBOutlet var iconView: UIImageView!
    @IBOutlet var disclosureIndicator: UIImageView!

    private var disposal = Disposal()

    var viewModel: MeetupViewModel! {
        didSet {
            viewModel.visible.observe { visible, _ in
                self.isHidden = !visible
            }.add(to: &disposal)

            viewModel.title.observe { title, _ in
                self.titleLabel.text = title
            }.add(to: &disposal)

            viewModel.titleColor.observe { titleColor, _ in
                self.titleLabel.textColor = titleColor
                self.disclosureIndicator.tintColor = titleColor
            }.add(to: &disposal)

            viewModel.description.observe { description, _ in
                self.descriptionLabel.text = description
                self.descriptionLabel.isHidden = description == nil
            }.add(to: &disposal)

            viewModel.descriptionColor.observe { descriptionColor, _ in
                self.descriptionLabel.textColor = descriptionColor
            }.add(to: &disposal)

            viewModel.backgroundColor.observe { backgroundColor, _ in
                self.blurContainer.contentView.backgroundColor = backgroundColor
            }.add(to: &disposal)
            
            viewModel.iconImage.observe { iconImage, _ in
                self.iconView.image = iconImage
            }.add(to: &disposal)

            viewModel.showDisclosureIndicator.observe { showDisclosureIndicator, _ in
                self.disclosureIndicator.isHidden = !showDisclosureIndicator
            }.add(to: &disposal)
        }
    }
}
