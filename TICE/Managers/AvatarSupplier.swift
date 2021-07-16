//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

protocol AvatarSupplierType {
    func avatar(user: User, size: CGSize, rounded: Bool) -> UIImage
    func avatar(team: Team, size: CGSize, rounded: Bool) -> UIImage
}

class AvatarSupplier: AvatarSupplierType {
    
    let signedInUser: SignedInUser
    let avatarGenerator: AvatarGeneratorType
    let nameSupplier: NameSupplierType
    let userManager: UserManagerType
    let teamManager: TeamManagerType
    let groupStorageManager: GroupStorageManagerType
    let demoManager: DemoManagerType

    init(signedInUser: SignedInUser, avatarGenerator: AvatarGeneratorType, nameSupplier: NameSupplierType, userManager: UserManagerType, teamManager: TeamManagerType, groupStorageManager: GroupStorageManagerType, demoManager: DemoManagerType) {
        self.signedInUser = signedInUser
        self.avatarGenerator = avatarGenerator
        self.nameSupplier = nameSupplier
        self.userManager = userManager
        self.teamManager = teamManager
        self.groupStorageManager = groupStorageManager
        self.demoManager = demoManager
    }
    
    func avatar(user: User, size: CGSize, rounded: Bool) -> UIImage {
        // return image from contact book if available

        // return public avatar if available
        
        // generate avatar from name and color based on userId
        let name = nameSupplier.name(user: user)
        return avatarGenerator.generateAvatar(name: name, userId: user.userId, size: size, rounded: rounded)
    }
    
    func avatar(team: Team, size: CGSize, rounded: Bool) -> UIImage {
        // return avatar from team settings if available

        let members: [Membership]
        do {
            members = try groupStorageManager.loadMemberships(groupId: team.groupId)
        } catch {
            return UIImage(named: "teamAvatar")!
        }
        
        guard members.count > 1 else { // empty or we are alone
            return UIImage(named: "person")!
        }
        
        if members.count == 2, let otherMember = members.first(where: { $0.userId != signedInUser.userId }) { // ourselves
            do {
                let otherUser = try groupStorageManager.user(for: otherMember)
                return avatar(user: otherUser, size: size, rounded: rounded)
            } catch {
                logger.error("Didn't find other user member: \(String(describing: error))")
                return UIImage(named: "teamAvatar")!
            }
        }
        
        return UIImage(named: "teamAvatar")!
    }
}
