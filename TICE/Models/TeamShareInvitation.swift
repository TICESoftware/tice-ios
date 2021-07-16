//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import LinkPresentation

class TeamShareInvitation: NSObject, UIActivityItemSource {
    
    let nameSupplier: NameSupplierType
    let team: Team

    init(nameSupplier: NameSupplierType, team: Team) {
        self.nameSupplier = nameSupplier
        self.team = team
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return ""
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        switch activityType {
        case .some(.airDrop):
            return team.shareURL
        default:
            return L10n.Invite.invitation(nameSupplier.name(team: team), "\(team.shareURL)")
        }
    }

    func activityViewControllerLinkMetadata(_: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = team.shareURL
        metadata.url = metadata.originalURL
        metadata.title = L10n.Invite.Invitation.title(nameSupplier.name(team: team))
        metadata.imageProvider = NSItemProvider(contentsOf:
            Bundle.main.url(forResource: "tice_featured", withExtension: "png"))
        return metadata
    }
}
