//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

class NameSupplier: NameSupplierType {

    let pseudonymGenerator: PseudonymGeneratorType
    let userManager: UserManagerType

    init(pseudonymGenerator: PseudonymGeneratorType, userManager: UserManagerType) {
        self.pseudonymGenerator = pseudonymGenerator
        self.userManager = userManager
    }
    
    func name(user: User) -> String {
        if let publicName = user.publicName {
            return publicName
        }

        return pseudonymGenerator.pseudonym(userId: user.userId)
    }
    
    func name(team: Team) -> String {
        if let name = team.name {
            return name
        }
        
        return groupNameByOwner(owner: team.owner)
    }
    
    func groupNameByOwner(owner userId: UserId) -> String {
        guard let owner = userManager.user(userId) else { return L10n.TeamName.unknown }
        
        let ownerName = name(user: owner)
        let locale = Bundle.main.preferredLocalizations.first
        let useSpecialGenetiveGerman = locale == "de" && ["s", "x", "z"].contains(ownerName.last)
        let useSpecialGenetiveEnglish = locale == "en" && ["s"].contains(ownerName.last)
        
        if useSpecialGenetiveGerman || useSpecialGenetiveEnglish {
            return L10n.TeamName.Owner.s(ownerName)
        } else {
            return L10n.TeamName.owner(ownerName)
        }
    }
}
