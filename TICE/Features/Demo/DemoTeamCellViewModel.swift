//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

struct DemoTeamCellViewModel: TeamCellViewModelType {
    var title: String?
    var description: String?
    var avatar: UIImage
    var lastActivity: String?
    var hasUnreadMessages: Bool
    var statusIcon: UIImage?
}
