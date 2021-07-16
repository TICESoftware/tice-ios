//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

struct DemoMemberTableViewCellViewModel: MemberTableViewCellViewModelType {
    
    let demoManager: DemoManagerType
    var user: DemoUser
    
    init(demoManager: DemoManagerType, user: DemoUser) {
        self.demoManager = demoManager
        self.user = user
    }
    
    var userName: String { return user.name }
    
    var avatar: UIImage { return demoManager.avatar(demoUser: user) }
    
    var subtitle: String { return user.role }
    
    var isTouchable: Bool { return false }
}
