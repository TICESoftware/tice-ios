//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import XCTest
import ConvAPI
import TICEAPIModels
import Shouter
import Version
import Cuckoo

@testable import TICE

class BackendTests: XCTestCase {
    
    var baseURL: URL!

    var jsonDecoder: JSONDecoder!
    var jsonEncoder: JSONEncoder!

    var userId: UserId!
    var groupId: GroupId!
    
    var api: MockAPI!
    var authHeader: Certificate!

    var backend: TICEBackend!

    override func setUp() {
        super.setUp()
        
        let address = "https://example.org"
        baseURL = URL(string: address)!
        
        jsonDecoder = JSONDecoder.decoderWithFractionalSeconds
        jsonEncoder = JSONEncoder.encoderWithFractionalSeconds
        
        userId = UserId(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        groupId = GroupId(uuidString: "F621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        
        let signedInUserManager = MockSignedInUserManagerType()
        let signedInUser = SignedInUser(userId: UserId(), privateSigningKey: "privateKey".data, publicSigningKey: "publicKey".data, publicName: nil)
        stub(signedInUserManager) { stub in
            when(stub.requireSignedInUser()).thenReturn(signedInUser)
        }
        
        api = MockAPI { _, _, _, _, _, _ in }
        let authManager = MockAuthManagerType()
        authHeader = "authHeader"
        stub(authManager) { stub in
            when(stub.generateAuthHeader(signingKey: signedInUser.privateSigningKey, userId: signedInUser.userId)).thenReturn(authHeader)
        }
        
        backend = TICEBackend(
            api: api,
            baseURL: baseURL,
            clientVersion: Version("1.0.0"),
            clientBuild: 42,
            clientPlatform: "Test",
            authManager: authManager,
            signedInUserManager: signedInUserManager
        )
    }
    
    override func tearDown() {
        super.tearDown()
        
        api = MockAPI { _, _, _, _, _, _ in }
    }

    // MARK: User
    
    func testVerifyRequest() {
        let expectation = self.expectation(description: "Callback")
        api.callback = { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .POST, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/verify", "Invalid resource")
            XCTAssertEqual(header, ["X-Platform": "Test", "X-Build": "42", "X-Version": "1.0.0"], "Header should only contain platform and build")
            XCTAssertNil(params, "Parameters should be nil")

            guard let body = body,
                let verifyRequest = try? self.jsonDecoder.decode(VerifyRequest.self, from: body) else {
                XCTFail("Invalid body")
                return nil
            }

            XCTAssertEqual(verifyRequest.platform, .iOS, "Incorrect platform")
            XCTAssertEqual(verifyRequest.deviceId, "6465766963654964", "Incorrect device id")
            expectation.fulfill()
            
            return nil
        }

        let deviceId = "deviceId".data
        backend.verify(deviceId: deviceId).cauterize()
        wait(for: [expectation])
    }
    
    func testCreateUserRequest() {
        let expectation = self.expectation(description: "Callback")

        let signingKey = "signingKey".data
        let identityKey = "identityKey".data
        let signedPrekey = "signedPrekey".data
        let prekeySignature = "prekeySignature".data
        let oneTimePrekeys = ["oneTimePrekey".data]

        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .POST, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/user", "Invalid resource")
            XCTAssertEqual(header, ["X-Platform": "Test", "X-Build": "42", "X-Version": "1.0.0"], "Header should only contain platform and build")
            XCTAssertNil(params, "Parameters should be nil")

            guard let body = body,
                let createUserRequest = try? self.jsonDecoder.decode(CreateUserRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(createUserRequest.publicKeys.signingKey, signingKey, "Incorrect identity key")
            XCTAssertEqual(createUserRequest.publicKeys.identityKey, identityKey, "Incorrect ephemeral key")
            XCTAssertEqual(createUserRequest.publicKeys.signedPrekey, signedPrekey, "Incorrect signed prekey")
            XCTAssertEqual(createUserRequest.publicKeys.prekeySignature, prekeySignature, "Incorrect prekeys")
            XCTAssertEqual(createUserRequest.publicKeys.oneTimePrekeys, oneTimePrekeys, "Incorrect prekeys")
            XCTAssertEqual(createUserRequest.platform, .iOS, "Incorrect platform")
            XCTAssertEqual(createUserRequest.deviceId, "6465766963654964", "Incorrect device id")
            XCTAssertEqual(createUserRequest.verificationCode, "SIM-IOS", "Incorrect verification code")
            XCTAssertEqual(createUserRequest.publicName, "publicName", "Incorrect public name")
            expectation.fulfill()
            
            return nil
        }

        let publicKeys = UserPublicKeys(signingKey: signingKey, identityKey: identityKey, signedPrekey: signedPrekey, prekeySignature: prekeySignature, oneTimePrekeys: oneTimePrekeys)
        let deviceId = "deviceId".data
        let verificationCode = "SIM-IOS"

        backend.createUser(publicKeys: publicKeys, platform: .iOS, deviceId: deviceId, verificationCode: verificationCode, publicName: "publicName").cauterize()
        wait(for: [expectation])
    }

    func testUpdateKeys() {
        let expectation = self.expectation(description: "Callback")

        let signingKey = "signingKey".data
        let identityKey = "identityKey".data
        let signedPrekey = "signedPrekey".data
        let prekeySignature = "prekeySignature".data
        let oneTimePrekeys = ["oneTimePrekey".data]

        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .PUT, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/user/\(self.userId.uuidString)", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")

            guard let body = body,
                let createUserRequest = try? self.jsonDecoder.decode(UpdateUserRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            guard let publicKeys = createUserRequest.publicKeys else {
                XCTFail("Public keys should not be nil.")
                return nil
            }

            XCTAssertEqual(publicKeys.signingKey, signingKey, "Incorrect identity key")
            XCTAssertEqual(publicKeys.identityKey, identityKey, "Incorrect ephemeral key")
            XCTAssertEqual(publicKeys.signedPrekey, signedPrekey, "Incorrect signed prekey")
            XCTAssertEqual(publicKeys.prekeySignature, prekeySignature, "Incorrect prekeys")
            XCTAssertEqual(publicKeys.oneTimePrekeys, oneTimePrekeys, "Incorrect prekeys")

            XCTAssertNil(createUserRequest.verificationCode, "Verification code should be nil")
            expectation.fulfill()
            
            return nil
        }

        let publicKeys = UserPublicKeys(signingKey: signingKey, identityKey: identityKey, signedPrekey: signedPrekey, prekeySignature: prekeySignature, oneTimePrekeys: oneTimePrekeys)

        backend.updateUser(userId: userId, publicKeys: publicKeys, deviceId: nil, verificationCode: nil, publicName: nil ).cauterize()
        wait(for: [expectation])
    }

    func testUpdateIdentityKey() {
        let expectation = self.expectation(description: "Callback")

        let signingKey = "signingKey".data
        let identityKey = "identityKey".data
        let signedPrekey = "signedPrekey".data
        let prekeySignature = "prekeySignature".data
        let oneTimePrekeys = ["oneTimePrekey".data]

        api.callback =  { method, baseURL, resource, header, params, body in
            defer {
                expectation.fulfill()
            }
            XCTAssertEqual(method, .PUT, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/user/\(self.userId.uuidString)", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")

            guard let body = body,
                let createUserRequest = try? self.jsonDecoder.decode(UpdateUserRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            guard let publicKeys = createUserRequest.publicKeys else {
                XCTFail("Public keys should not be nil.")
                return nil
            }

            XCTAssertEqual(publicKeys.signingKey, signingKey, "Incorrect identity key")
            XCTAssertEqual(publicKeys.identityKey, identityKey, "Incorrect ephemeral key")
            XCTAssertEqual(publicKeys.signedPrekey, signedPrekey, "Incorrect signed prekey")
            XCTAssertEqual(publicKeys.prekeySignature, prekeySignature, "Incorrect prekeys")
            XCTAssertEqual(publicKeys.oneTimePrekeys, oneTimePrekeys, "Incorrect prekeys")

            XCTAssertEqual(createUserRequest.verificationCode, "SIM-IOS", "Invalid verification code")
            
            return nil
        }

        let publicKeys = UserPublicKeys(signingKey: signingKey, identityKey: identityKey, signedPrekey: signedPrekey, prekeySignature: prekeySignature, oneTimePrekeys: oneTimePrekeys)

        backend.updateUser(userId: userId, publicKeys: publicKeys, deviceId: nil, verificationCode: "SIM-IOS", publicName: nil).cauterize()
        wait(for: [expectation])
    }

    func testUpdateDeviceId() {
        let expectation = self.expectation(description: "Callback")
        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .PUT, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/user/\(self.userId.uuidString)", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")

            guard let body = body,
                let createUserRequest = try? self.jsonDecoder.decode(UpdateUserRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(createUserRequest.deviceId, "6465766963654964", "Incorrect device id")

            XCTAssertNil(createUserRequest.publicKeys, "Public keys should be nil")
            XCTAssertNil(createUserRequest.verificationCode, "Verification code should be nil")
            expectation.fulfill()
            
            return nil
        }

        let deviceId = "deviceId".data

        backend.updateUser(userId: userId, publicKeys: nil, deviceId: deviceId, verificationCode: nil, publicName: nil).cauterize()
        wait(for: [expectation])
    }

    func testDeleteUserRequest() {
        let expectation = self.expectation(description: "Callback")
        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .DELETE, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/user/\(self.userId.uuidString)", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")

            XCTAssertNil(body, "Body should be nil")
            expectation.fulfill()
            
            return nil
        }

        backend.deleteUser(userId: userId).cauterize()
        wait(for: [expectation])
    }

    func testGetUserRequest() {
        let expectation = self.expectation(description: "Callback")
        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .GET, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/user/\(self.userId.uuidString)", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")

            XCTAssertNil(body, "Body should be nil")
            expectation.fulfill()
            
            return nil
        }

        backend.getUser(userId: userId).cauterize()
        wait(for: [expectation])
    }

    func testGetUserKeysRequest() {
        let expectation = self.expectation(description: "Callback")
        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .POST, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/user/\(self.userId.uuidString)/keys", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")

            XCTAssertNil(body, "Body should be nil")
            expectation.fulfill()
            
            return nil
        }

        backend.getUserKeys(userId: userId).cauterize()
        wait(for: [expectation])
    }

    // MARK: Group

    func testCreateGroupRequest() {
        let expectation = self.expectation(description: "Callback")

        let encryptedSettings = "encryptedSettings".data
        let encryptedInternalSettings = "encryptedInternalSettings".data

        let selfSignedAdminCertificate = "Certificate"

        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .POST, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/group", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")

            guard let body = body,
                let createGroupRequest = try? self.jsonDecoder.decode(CreateGroupRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(createGroupRequest.type, .team, "Incorrect group type")
            XCTAssertEqual(createGroupRequest.joinMode, .open, "Incorrect join mode")
            XCTAssertEqual(createGroupRequest.permissionMode, .admin, "Incorrect permission mode")
            XCTAssertEqual(createGroupRequest.groupId, self.groupId, "Incorrect group id")
            XCTAssertEqual(createGroupRequest.selfSignedAdminCertificate, selfSignedAdminCertificate, "Incorrect admin certificate")
            XCTAssertEqual(createGroupRequest.encryptedSettings, encryptedSettings, "Incorrect encrypted settings")
            XCTAssertEqual(createGroupRequest.encryptedInternalSettings, encryptedInternalSettings, "Incorrect encrypted internal settings")
            expectation.fulfill()
            
            return nil
        }

        backend.createGroup(userId: userId, type: .team, joinMode: .open, permissionMode: .admin, groupId: groupId, parentGroup: nil, selfSignedAdminCertificate: selfSignedAdminCertificate, encryptedSettings: encryptedSettings, encryptedInternalSettings: encryptedInternalSettings).cauterize()

        wait(for: [expectation])
    }

    func testGetGroupInformation() {
        let expectation = self.expectation(description: "Callback")
        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .GET, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/group/\(self.groupId.uuidString)", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")
            XCTAssertNil(body, "Body should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")
            expectation.fulfill()
            
            return nil
        }

        backend.getGroupInformation(groupId: groupId, groupTag: nil).cauterize()
        wait(for: [expectation])
    }

    func testGetGroupInternals() {
        let expectation = self.expectation(description: "Callback")

        let serverSignedMembershipCertificate = "Certificate"

        api.callback =  { method, baseURL, resource, header, params, body in
            defer {
                expectation.fulfill()
            }

            XCTAssertEqual(method, .GET, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/group/\(self.groupId.uuidString)/internals", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")
            XCTAssertNil(body, "Body should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }


            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")
            XCTAssertEqual(header["X-ServerSignedMembershipCertificate"], serverSignedMembershipCertificate, "Incorrect header")
            
            return nil
        }

        backend.getGroupInternals(groupId: groupId, serverSignedMembershipCertificate: serverSignedMembershipCertificate, groupTag: nil).cauterize()
        wait(for: [expectation])
    }

    func testJoinGroupRequest() {
        let expectation = self.expectation(description: "Callback")

        let selfSignedMembershipCertificate = "selfSignedMembershipCertificate"
        let serverSignedAdminCertificate = "serverSignedAdminCertificate"
        let adminSignedMembershipCertificate = "adminSignedMembershipCertificate"

        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .POST, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/group/\(self.groupId.uuidString)/request", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")
            XCTAssertEqual(header["X-GroupTag"], "groupTag", "Incorrect header")

            guard let body = body,
                let joinGroupRequest = try? self.jsonDecoder.decode(JoinGroupRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(joinGroupRequest.selfSignedMembershipCertificate, selfSignedMembershipCertificate, "Incorrect self signed membership certificate")
            XCTAssertEqual(joinGroupRequest.serverSignedAdminCertificate, serverSignedAdminCertificate, "Incorrect server signed adminship certificate")
            XCTAssertEqual(joinGroupRequest.adminSignedMembershipCertificate, adminSignedMembershipCertificate, "Incorrect admin signed membership certificate")
            expectation.fulfill()
            
            return nil
        }

        backend.joinGroup(groupId: groupId, selfSignedMembershipCertificate: selfSignedMembershipCertificate, serverSignedAdminCertificate: serverSignedAdminCertificate, adminSignedMembershipCertificate: adminSignedMembershipCertificate, groupTag: "groupTag").cauterize()
        wait(for: [expectation])
    }

    func testAddGroupMemberRequest() {
        let expectation = self.expectation(description: "Callback")

        let userId = UserId(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let serverSignedMembershipCertificate = "serverSignedMembershipCertificate"

        let notificationRecipientUserId = UserId(uuidString: "A621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let encryptedMembership = "EncryptedMembership".data
        let notificationRecipientServerSignedMembershipCertificate = "notificationRecipientServerSignedMembershipCertificate"
        let tokenKey = "tokenKey".data
        let groupTag = "groupTag"

        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .POST, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/group/\(self.groupId.uuidString)/member", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")
            XCTAssertEqual(header["X-GroupTag"], "groupTag", "Incorrect header")

            guard let body = body,
                let addGroupMemberRequest = try? self.jsonDecoder.decode(AddGroupMemberRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(addGroupMemberRequest.encryptedMembership, encryptedMembership, "Incorrect membership user id")
            XCTAssertEqual(addGroupMemberRequest.userId, userId, "Incorrect server signed membership certificate")
            XCTAssertEqual(addGroupMemberRequest.newTokenKey, tokenKey.base64URLEncodedString(), "Incorrect token key")
            XCTAssertEqual(addGroupMemberRequest.notificationRecipients.count, 1, "Incorrect number of notification recipients")
            XCTAssertEqual(addGroupMemberRequest.notificationRecipients[0].userId, notificationRecipientUserId, "Incorrect notification recipient")
            XCTAssertEqual(addGroupMemberRequest.notificationRecipients[0].serverSignedMembershipCertificate, notificationRecipientServerSignedMembershipCertificate, "Incorrect notification recipient")
            expectation.fulfill()
            
            return nil
        }

        let notificationRecipient = NotificationRecipient(userId: notificationRecipientUserId, serverSignedMembershipCertificate: notificationRecipientServerSignedMembershipCertificate, priority: .alert)

        backend.addGroupMember(groupId: groupId, userId: userId, encryptedMembership: encryptedMembership, serverSignedMembershipCertificate: serverSignedMembershipCertificate, newTokenKey: tokenKey, groupTag: groupTag, notificationRecipients: [notificationRecipient]).cauterize()
        wait(for: [expectation])
    }

    func testUpdateGroupMemberRequest() {
        let expectation = self.expectation(description: "Callback")

        let notificationRecipientUserId = UserId(uuidString: "A621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let notificationRecipientServerSignedMembershipCertificate = "notificationRecipientServerSignedMembershipCertificate"

        let encryptedMembership = "encryptedMembership".data
        let tokenKey = "tokenKey".data
        let ownServerSignedMembershipCertificate = "ownServerSignedMembershipCertificate"

        let groupTag = "groupTag"

        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .PUT, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/group/\(self.groupId.uuidString)/member/\(tokenKey.base64URLEncodedString())", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")
            XCTAssertEqual(header["X-GroupTag"], groupTag, "Incorrect header")

            guard let body = body,
                let updateGroupMemberRequest = try? self.jsonDecoder.decode(UpdateGroupMemberRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(updateGroupMemberRequest.userId, self.userId, "Incorrect membership user id")
            XCTAssertEqual(updateGroupMemberRequest.encryptedMembership, encryptedMembership, "Incorrect encrypted membership")
            XCTAssertEqual(updateGroupMemberRequest.notificationRecipients.count, 1, "Incorrect notification recipients")
            XCTAssertEqual(updateGroupMemberRequest.notificationRecipients[0].userId, notificationRecipientUserId, "Incorrect notification recipients")
            XCTAssertEqual(updateGroupMemberRequest.notificationRecipients[0].serverSignedMembershipCertificate, notificationRecipientServerSignedMembershipCertificate, "Incorrect notification recipients")
            expectation.fulfill()
            
            return nil
        }

        let notificationRecipient = NotificationRecipient(userId: notificationRecipientUserId, serverSignedMembershipCertificate: notificationRecipientServerSignedMembershipCertificate, priority: .background)

        backend.updateGroupMember(groupId: groupId, userId: userId, encryptedMembership: encryptedMembership, serverSignedMembershipCertificate: ownServerSignedMembershipCertificate, tokenKey: tokenKey, groupTag: groupTag, notificationRecipients: [notificationRecipient]).cauterize()
        wait(for: [expectation])
    }

    func testDeleteGroupMemberRequest() {
        let expectation = self.expectation(description: "Callback")

        let notificationRecipientUserId = UserId(uuidString: "A621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let notificationRecipientServerSignedMembershipCertificate = "notificationRecipientServerSignedMembershipCertificate"

        let tokenKey = "tokenKey".data
        let userServerSignedMembershipCertificate = "userServerSignedMembershipCertificate"
        let ownServerSignedMmebershipCertificate = "ownServerSignedMembershipCertificate"

        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .DELETE, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/group/\(self.groupId.uuidString)/member/\(tokenKey.base64URLEncodedString())", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")
            XCTAssertEqual(header["X-GroupTag"], "groupTag", "Incorrect header")

            guard let body = body,
                let deleteGroupMemberRequest = try? self.jsonDecoder.decode(DeleteGroupMemberRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(deleteGroupMemberRequest.userId, self.userId, "Incorrect membership user id")
            XCTAssertEqual(deleteGroupMemberRequest.serverSignedMembershipCertificate, userServerSignedMembershipCertificate, "Incorrect membership certificate")
            XCTAssertEqual(deleteGroupMemberRequest.notificationRecipients.count, 1, "Incorrect notification recipients")
            XCTAssertEqual(deleteGroupMemberRequest.notificationRecipients[0].userId, notificationRecipientUserId, "Incorrect notification recipients")
            XCTAssertEqual(deleteGroupMemberRequest.notificationRecipients[0].serverSignedMembershipCertificate, notificationRecipientServerSignedMembershipCertificate, "Incorrect notification recipients")
            expectation.fulfill()
            
            return nil
        }

        let notificationRecipient = NotificationRecipient(userId: notificationRecipientUserId, serverSignedMembershipCertificate: notificationRecipientServerSignedMembershipCertificate, priority: .alert)

        backend.deleteGroupMember(groupId: groupId, userId: userId, userServerSignedMembershipCertificate: userServerSignedMembershipCertificate, ownServerSignedMembershipCertificate: ownServerSignedMmebershipCertificate, tokenKey: tokenKey, groupTag: "groupTag", notificationRecipients: [notificationRecipient]).cauterize()
        wait(for: [expectation])
    }

    func testDeleteGroupRequest() {
        let expectation = self.expectation(description: "Callback")

        let notificationRecipientUserId = UserId(uuidString: "A621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let recipientServerSignedMembershipCertificate = "recipientServerSignedMembershipCertificate"

        let serverSignedAdminCertificate = "serverSignedAdminCertificate"

        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .DELETE, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/group/\(self.groupId.uuidString)", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")
            XCTAssertEqual(header["X-GroupTag"], "groupTag", "Incorrect header")

            guard let body = body,
                let deleteGroupRequest = try? self.jsonDecoder.decode(DeleteGroupRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(deleteGroupRequest.serverSignedAdminCertificate, serverSignedAdminCertificate, "Incorrect adminship certificate")
            XCTAssertEqual(deleteGroupRequest.notificationRecipients.count, 1, "Incorrect number of notification recipients")
            XCTAssertEqual(deleteGroupRequest.notificationRecipients[0].userId, notificationRecipientUserId, "Incorrect recipient user id")
            XCTAssertEqual(deleteGroupRequest.notificationRecipients[0].serverSignedMembershipCertificate, recipientServerSignedMembershipCertificate, "Incorrect recipient membership certificate")
            expectation.fulfill()
            
            return nil
        }

        let notificationRecipient = NotificationRecipient(userId: notificationRecipientUserId, serverSignedMembershipCertificate: recipientServerSignedMembershipCertificate, priority: .alert)

        backend.deleteGroup(groupId: groupId, serverSignedAdminCertificate: serverSignedAdminCertificate, groupTag: "groupTag", notificationRecipients: [notificationRecipient]).cauterize()
        wait(for: [expectation])
    }

    func testUpdateSettingsRequest() {
        let expectation = self.expectation(description: "Callback")

        let notificationRecipientUserId = UserId(uuidString: "A621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

        let serverSignedAdminCertificate = "serverSignedAdminCertificate"
        let recipientServerSignedMembershipCertificate = "recipientServerSignedMembershipCertificate"

        let encryptedSettings = "encryptedSettings".data

        api.callback =  { method, baseURL, resource, header, params, body in
            defer {
                expectation.fulfill()
            }
            XCTAssertEqual(method, .PUT, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/group/\(self.groupId.uuidString)", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")
            XCTAssertEqual(header["X-GroupTag"], "groupTag", "Incorrect header")
            XCTAssertEqual(header["X-ServerSignedMembershipCertificate"], serverSignedAdminCertificate, "Incorrect header")

            guard let body = body,
                let updateSettingsRequest = try? self.jsonDecoder.decode(UpdateGroupInformationRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(updateSettingsRequest.newSettings, encryptedSettings, "Incorrect settings")
            
            return nil
        }

        let notificationRecipient = NotificationRecipient(userId: notificationRecipientUserId, serverSignedMembershipCertificate: recipientServerSignedMembershipCertificate, priority: .alert)

        backend.updateSettings(groupId: groupId, encryptedSettings: encryptedSettings, serverSignedMembershipCertificate: serverSignedAdminCertificate, groupTag: "groupTag", notificationRecipients: [notificationRecipient]).cauterize()
        wait(for: [expectation])
    }

    func testUpdateInternalSettingsRequest() {
        let expectation = self.expectation(description: "Callback")

        let notificationRecipientUserId = UserId(uuidString: "A621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

        let serverSignedAdminCertificate = "serverSignedAdminCertificate"
        let recipientServerSignedMembershipCertificate = "recipientServerSignedMembershipCertificate"

        let encryptedInternalSettings = "encryptedInternalSettings".data

        api.callback =  { method, baseURL, resource, header, params, body in
            defer {
                expectation.fulfill()
            }
            XCTAssertEqual(method, .PUT, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/group/\(self.groupId.uuidString)/internals", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")
            XCTAssertEqual(header["X-GroupTag"], "groupTag", "Incorrect header")
            XCTAssertEqual(header["X-ServerSignedMembershipCertificate"], serverSignedAdminCertificate, "Incorrect header")

            guard let body = body,
                let updateInternalSettingsRequest = try? self.jsonDecoder.decode(UpdateGroupInternalsRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(updateInternalSettingsRequest.newInternalSettings, encryptedInternalSettings, "Incorrect settings")
            
            return nil
        }

        let notificationRecipient = NotificationRecipient(userId: notificationRecipientUserId, serverSignedMembershipCertificate: recipientServerSignedMembershipCertificate, priority: .alert)

        backend.updateInternalSettings(groupId: groupId, encryptedInternalSettings: encryptedInternalSettings, serverSignedMembershipCertificate: serverSignedAdminCertificate, groupTag: "groupTag", notificationRecipients: [notificationRecipient]).cauterize()
        wait(for: [expectation])
    }

    // MARK: Message

    func testMessageRequest() {
        let expectation = self.expectation(description: "Callback")

        let messageId = MessageId(uuidString: "123E4567-E89B-12D3-A456-426655440000")!

        let serverSignedMembershipCertificate = "serverSignedMembershipCertificate"

        let notificationRecipientUserId = UserId(uuidString: "A621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let notificationRecipientServerSignedMembershipCertificate = "notificationRecipientServerSignedMembershipCertificate"

        let encryptedMessage = "encryptedMessage".data
        let encryptedMessageKey = "encryptedMessageKey".data

        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .POST, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/message", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")

            guard let body = body,
                let messageRequest = try? self.jsonDecoder.decode(SendMessageRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(messageRequest.id, messageId, "Incorrect message id")
            XCTAssertEqual(messageRequest.senderId, self.userId, "Incorrect sender id")
            XCTAssertEqual(messageRequest.encryptedMessage, encryptedMessage, "Incorrect encrypted message")
            XCTAssertEqual(messageRequest.serverSignedMembershipCertificate, serverSignedMembershipCertificate, "Incorrect server signed membership certificate")

            guard let collapseId = messageRequest.collapseId else {
                XCTFail("Collapse id should not be nil")
                return nil
            }

            guard let recipient = messageRequest.recipients.first else {
                XCTFail("Invalid recipients")
                return nil
            }

            XCTAssertEqual(recipient.userId, notificationRecipientUserId, "Invalid recipient")
            XCTAssertEqual(recipient.encryptedMessageKey, encryptedMessageKey, "Invalid recipient")
            XCTAssertEqual(recipient.serverSignedMembershipCertificate, notificationRecipientServerSignedMembershipCertificate, "Invalid recipient")

            XCTAssertEqual(collapseId, "0", "Incorrect collapse id")

            let dateFormatter = ISO8601DateFormatter.formatterWithFractionalSeconds
            let timestampString = dateFormatter.string(from: messageRequest.timestamp)
            XCTAssertEqual(timestampString, "2019-01-18T12:10:39.500Z", "Incorrect timestamp")
            expectation.fulfill()
            
            return nil
        }

        let timestamp = Date(timeIntervalSince1970: 1547813439.5)
        let recipient = Recipient(userId: notificationRecipientUserId, serverSignedMembershipCertificate: notificationRecipientServerSignedMembershipCertificate, encryptedMessageKey: encryptedMessageKey, conversationInvitation: nil)

        backend.message(id: messageId, senderId: userId, timestamp: timestamp, encryptedMessage: encryptedMessage, serverSignedMembershipCertificate: serverSignedMembershipCertificate, recipients: [recipient], priority: .background, collapseId: "0").cauterize()
        wait(for: [expectation])
    }

    func testGetMessagesRequest() {
        let expectation = self.expectation(description: "Callback")

        api.callback =  { method, baseURL, resource, header, params, body in
            defer {
                expectation.fulfill()
            }

            XCTAssertEqual(method, .GET, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/message", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")
            XCTAssertNil(body, "Body should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")
            
            return nil
        }

        backend.getMessages().cauterize()

        wait(for: [expectation])
    }

    func testRenewCertificateRequest() {
        let expectation = self.expectation(description: "Callback")

        let certificate = "Certificate"

        api.callback =  { method, baseURL, resource, header, params, body in
            XCTAssertEqual(method, .POST, "Invalid request method")
            XCTAssertEqual(baseURL, self.baseURL, "Invalid base URL")
            XCTAssertEqual(resource, "/certificates/renew", "Invalid resource")
            XCTAssertNil(params, "Parameters should be nil")

            guard let header = header else {
                XCTFail("Header should not be nil")
                return nil
            }

            XCTAssertEqual(header["X-Authorization"], self.authHeader, "Incorrect header")

            guard let body = body,
                let renewCertificateRequest = try? self.jsonDecoder.decode(RenewCertificateRequest.self, from: body) else {
                    XCTFail("Invalid body")
                    return nil
            }

            XCTAssertEqual(renewCertificateRequest.certificate, certificate, "Incorrect certificate")

            expectation.fulfill()
            
            return nil
        }
        backend.renewCertificate(certificate).cauterize()
        wait(for: [expectation])
    }
}
