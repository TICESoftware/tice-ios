//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import Shouter
import PromiseKit
import TICEAPIModels
import CoreLocation

@testable import TICE

class GroupTests: XCTestCase {

    func testShareURL() {
        let groupKey = "groupKey".data
        let groupURL = URL(string: "https://tice.app/group/1")!
        let team = Team(groupId: GroupId(), groupKey: groupKey, owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "groupTag", url: groupURL, name: nil, meetupId: nil)
        XCTAssertEqual(team.shareURL.absoluteString, groupURL.absoluteString + "#" + "\(groupKey.base64URLEncodedString())", "Invalid share url")
    }
}
