//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

protocol SignedInUserStorageManagerType: DeletableStorageManagerType {
    func store(signedInUser: SignedInUser) throws
    func loadSignedInUser() -> SignedInUser?
}
