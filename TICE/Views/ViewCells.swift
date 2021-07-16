//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

class InfoTableViewCell: UITableViewCell {
    var viewModel: InfoTableViewCellViewModel! {
        didSet {
            textLabel?.text = viewModel.title
            detailTextLabel?.text = viewModel.value
            isUserInteractionEnabled = viewModel.shouldShowDisclosureIndicator
            
            if viewModel.isLoading {
                accessoryType = .none
                let activityIndicatorView = UIActivityIndicatorView(style: .medium)
                activityIndicatorView.startAnimating()
                self.accessoryView = activityIndicatorView
            } else {
                accessoryView = nil
                accessoryType = viewModel.shouldShowDisclosureIndicator ? .disclosureIndicator : .none
            }
        }
    }
}

struct InfoTableViewCellViewModel {
    let title: String
    let value: String
    let shouldShowDisclosureIndicator: Bool
    var isLoading: Bool = false
}

class MemberTableViewCell: UITableViewCell {

    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var avatarImageView: UIImageView!

    var viewModel: MemberTableViewCellViewModelType! {
        didSet {
            nameLabel?.text = viewModel.userName
            subtitleLabel?.text = viewModel.subtitle
            avatarImageView?.image = viewModel.avatar

            accessoryType = viewModel.isTouchable ? .disclosureIndicator : .none
            isUserInteractionEnabled = viewModel.isTouchable
        }
    }
}

protocol MemberTableViewCellViewModelType {
    var userName: String { get }
    var avatar: UIImage { get }
    var subtitle: String { get }
    var isTouchable: Bool { get }
}

struct ManualMemberTableViewCellViewModel: MemberTableViewCellViewModelType {
    var userName: String
    var avatar: UIImage
    var subtitle: String
    var isTouchable: Bool
}

struct MemberTableViewCellViewModel: MemberTableViewCellViewModelType {

    let nameSupplier: NameSupplierType
    let avatarSupplier: AvatarSupplierType

    var user: User
    var isAdmin: Bool
    var isTouchable: Bool
    var isSharingLocation: Bool

    init(nameSupplier: NameSupplierType, avatarSupplier: AvatarSupplierType, user: User, isTouchable: Bool, isAdmin: Bool, isSharingLocation: Bool) {
        self.nameSupplier = nameSupplier
        self.avatarSupplier = avatarSupplier
        self.user = user
        self.isTouchable = isTouchable
        self.isAdmin = isAdmin
        self.isSharingLocation = isSharingLocation
    }

    var userName: String {
        return nameSupplier.name(user: user)
    }

    var avatar: UIImage {
        return avatarSupplier.avatar(user: user, size: CGSize(width: 64, height: 64), rounded: false)
    }

    var subtitle: String {
        let memberDescription = isAdmin ? L10n.Group.Member.admin : L10n.Group.Member.member
        let locationSharingDescription = isSharingLocation ? L10n.Group.LocationSharing.active : nil
        return [memberDescription, locationSharingDescription].compactMap { $0 }.joined(separator: " · ")
    }
}

class ActionTableViewCell: UITableViewCell {
    var viewModel: ActionTableViewCellViewModel! {
        didSet {
            textLabel?.text = viewModel.title

            if viewModel.isLoading {
                let activityIndicatorView = UIActivityIndicatorView(style: .medium)
                self.accessoryView = activityIndicatorView
                activityIndicatorView.startAnimating()
                isUserInteractionEnabled = false
                textLabel?.textColor = UIColor.disabled
            } else {
                accessoryView = nil
                isUserInteractionEnabled = true
                textLabel?.textColor = viewModel.isDestructive ? UIColor.destructive : UIColor.highlight
            }

            if !viewModel.isEnabled {
                isUserInteractionEnabled = false
                textLabel?.textColor = UIColor.disabled
            }
        }
    }
}

struct ActionTableViewCellViewModel {
    let title: String
    let isDestructive: Bool
    let isEnabled: Bool

    var isLoading: Bool

    init(title: String, isDestructive: Bool = false, isEnabled: Bool = true, isLoading: Bool = false) {
        self.title = title
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.isLoading = isLoading
    }
}

class ToggleTableViewCell: UITableViewCell {
    
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var toggle: UISwitch!
    
    var viewModel: ToggleTableViewCellViewModel! {
        didSet {
            textLabel?.text = viewModel.title
            toggle.setOn(viewModel.value, animated: false)
        }
    }
}

struct ToggleTableViewCellViewModel {
    let title: String
    var value: Bool
}
