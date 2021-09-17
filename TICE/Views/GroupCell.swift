//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Chatto
import ChattoAdditions

class TeamCell: UITableViewCell {
    @IBOutlet weak var avatarView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var unreadView: UIImageView!
    @IBOutlet weak var iconImageView: UIImageView!

    var viewModel: TeamCellViewModelType! {
        didSet {
            avatarView.image = viewModel.avatar
            titleLabel.text = viewModel.title
            descriptionLabel.text = viewModel.description
            statusLabel.text = viewModel.lastActivity
            unreadView.isHidden = !viewModel.hasUnreadMessages
            iconImageView.image = viewModel.statusIcon
            iconImageView.isHidden = viewModel.statusIcon == nil
        }
    }
}

protocol TeamCellViewModelType {
    var title: String? { get }
    var description: String? { get }
    var avatar: UIImage { get }
    var lastActivity: String? { get }
    var hasUnreadMessages: Bool { get }
    var statusIcon: UIImage? { get }
}

struct TeamCellViewModel: TeamCellViewModelType {
    
    let signedInUser: SignedInUser
    let nameSupplier: NameSupplierType
    let avatarSupplier: AvatarSupplierType
    let chatManager: ChatManagerType

    private var team: Team
    private var lastUpdated: Date
    private var participationStatus: ParticipationStatus
    private var members: [Member]

    init(team: Team, lastUpdated: Date, participationStatus: ParticipationStatus, members: [Member], groupStorageManager: GroupStorageManagerType, signedInUser: SignedInUser, nameSupplier: NameSupplierType, avatarSupplier: AvatarSupplierType, chatManager: ChatManagerType) {
        self.signedInUser = signedInUser
        self.nameSupplier = nameSupplier
        self.avatarSupplier = avatarSupplier
        self.chatManager = chatManager
        self.team = team
        self.lastUpdated = lastUpdated
        self.participationStatus = participationStatus
        self.members = members
    }

    var title: String? {
        return nameSupplier.name(team: team)
    }

    var description: String? {
        let userNames = members.sorted(by: { left, right in
            guard left.user.userId != self.signedInUser.userId else { return false }
            guard right.user.userId != self.signedInUser.userId else { return true }
            return left.user.userId.uuidString < right.user.userId.uuidString
        }).map { member -> String in
            if member.user.userId == signedInUser.userId {
                let you = L10n.Name.you
                return members.count == 1 ? you.capitalized : you
            } else {
                return nameSupplier.name(user: member.user)
            }
        }
        return LocalizedList(userNames)
    }
    
    var avatar: UIImage {
        return avatarSupplier.avatar(team: team, size: CGSize(width: 128, height: 128), rounded: false)
    }
    
    var lastActivity: String? {
        if Calendar.current.isDateInToday(lastUpdated) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .none
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: lastUpdated)
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .none
            return dateFormatter.string(from: lastUpdated)
        }
    }
    
    var hasUnreadMessages: Bool {
        return !chatManager.unreadMessages(groupId: team.groupId).isEmpty
    }

    var statusIcon: UIImage? {
        switch participationStatus {
        case .none:
            return nil
        case .onlyOthersSharing:
            return UIImage(named: "invited")
        case .sharing:
            return UIImage(named: "tracking")
        }
    }
}
