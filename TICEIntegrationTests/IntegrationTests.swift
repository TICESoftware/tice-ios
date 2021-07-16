//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import XCTest
import ConvAPI
import TICEAPIModels
import PromiseKit
import Shouter
import Valet
import Swinject
import Version
import GRDB
import Logging
import TICEAuth
import Cuckoo

@testable import TICE

class IntegrationTests: XCTestCase {

    var signedInUserManager: MockSignedInUserManagerType!
    var backend: TICEBackend!

    var deviceToken: Data!
    
    var privateSigningKey: PrivateKey!
    var publicKeys: UserPublicKeys!
    var signedInUser: SignedInUser! {
        didSet {
            stub(signedInUserManager) { stub in
                when(stub.requireSignedInUser()).thenReturn(signedInUser)
            }
        }
    }

    override func setUpWithError() throws {
        super.setUp()
        
        deviceToken = "deviceToken".data
        
        privateSigningKey = """
    -----BEGIN EC PRIVATE KEY-----
    MIHcAgEBBEIAgHEAuA8gfGnNUqYGYo2QgShxhd6MFxfig/o0KKPq9MScpf8/AMxv
    kVS5sJxCW2K7lnSs8aynlXcQrfAmt4ybfoOgBwYFK4EEACOhgYkDgYYABAAVumr0
    A4m3key2NeSJQ9f5ykPpOCSd3lJ54PW7cmV9a5jkRJx+65asndU/4Hk4IoiZ8GXa
    fndDggKDYPfg3VvzTADhw9XTa2G6LP3ubZI0jWM4MnT1AeU1CqFtzukXGHCAAhtM
    tldpHfIHDhRsa3tH9WSkL7EdbH2bWifefkxpiEBM9w==
    -----END EC PRIVATE KEY-----
    """.data
        
        let publicKey = """
    -----BEGIN PUBLIC KEY-----
    MIGbMBAGByqGSM49AgEGBSuBBAAjA4GGAAQAFbpq9AOJt5HstjXkiUPX+cpD6Tgk
    nd5SeeD1u3JlfWuY5EScfuuWrJ3VP+B5OCKImfBl2n53Q4ICg2D34N1b80wA4cPV
    02thuiz97m2SNI1jODJ09QHlNQqhbc7pFxhwgAIbTLZXaR3yBw4UbGt7R/VkpC+x
    HWx9m1on3n5MaYhATPc=
    -----END PUBLIC KEY-----
    """.data
        
        publicKeys = UserPublicKeys(
            signingKey: publicKey,
            identityKey: "identityKey".data,
            signedPrekey: "signedPrekey".data,
            prekeySignature: "prekeySignature".data,
            oneTimePrekeys: ["oneTimePrekey".data]
        )
        
        let url = Bundle(for: IntegrationTests.self).url(forResource: "Info", withExtension: "plist")!
        let infoPlist = NSDictionary(contentsOf: url)!
        let address = infoPlist["SERVER_ADDRESS"] as! String
        let testBaseURL = URL(string: address)!
        
        let sharedURLSession = URLSession.shared
        sharedURLSession.delegateQueue.maxConcurrentOperationCount = -1
        let urlSession = sharedURLSession

        let decoder = JSONDecoder.decoderWithFractionalSeconds
        let encoder = JSONEncoder.encoderWithFractionalSeconds

        let api = ConvAPI(requester: urlSession, encoder: encoder, decoder: decoder)
        signedInUserManager = MockSignedInUserManagerType()

        let logger = Logger(label: "software.tice.TICE.integrationTestLogging")
        let authManager = AuthManager(logger: logger)
        
        backend = TICEBackend(api: api, baseURL: testBaseURL, clientVersion: Version("1.8.0"), clientBuild: 127, clientPlatform: "iOS", authManager: authManager, signedInUserManager: signedInUserManager)
    }

    // MARK: Helper methods

    private func createUser() -> Promise<Void> {
        let publicName = "publicName"
        return firstly {
            backend.createUser(publicKeys: publicKeys, platform: .iOS, deviceId: deviceToken, verificationCode: "SIM-IOS", publicName: publicName)
        }.done {
            self.signedInUser = SignedInUser(
                userId: $0.userId,
                privateSigningKey: self.privateSigningKey,
                publicSigningKey: self.publicKeys.signingKey,
                publicName: publicName
            )
        }
    }

    // MARK: User

    func testVerificationError() {
        let exp = expectation(description: "Completion")

        let deviceId = "deviceId".data

        firstly {
            backend.verify(deviceId: deviceId)
        }.done {
            XCTFail("Verify should have produced an error.")
        }.catch { error in
            guard let appError = error as? APIError else {
                XCTFail("Verification request failed.")
                return
            }

            XCTAssertEqual(appError.type, .pushFailed, "Wrong error type")
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }

    func testCreateUserWithoutPublicName() throws {
        let exp = expectation(description: "Completion")

        firstly {
            backend.createUser(publicKeys: publicKeys, platform: .iOS, deviceId: deviceToken, verificationCode: "SIM-IOS", publicName: "publicName")
        }.catch {
            XCTFail($0.localizedDescription)
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }
    
    func testCreateUserWithPublicName() throws {
        let exp = expectation(description: "Completion")

        firstly {
            backend.createUser(publicKeys: publicKeys, platform: .iOS, deviceId: deviceToken, verificationCode: "SIM-IOS", publicName: "publicName")
        }.catch {
            XCTFail($0.localizedDescription)
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }

    func testDeleteUser() {
        let exp = expectation(description: "Completion")

        firstly {
            createUser()
        }.then {
            self.backend.deleteUser(userId: self.signedInUser.userId)
        }.catch {
            XCTFail($0.localizedDescription)
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }
    
    func testGetUser() {
        let exp = expectation(description: "Completion")

        firstly {
            createUser()
        }.then {
            self.backend.getUser(userId: self.signedInUser.userId)
        }.done { userResponse in
            XCTAssertEqual(userResponse.userId, self.signedInUser.userId)
            XCTAssertEqual(userResponse.publicName, self.signedInUser.publicName)
            XCTAssertEqual(userResponse.publicSigningKey, self.signedInUser.publicSigningKey)
        }.catch {
            XCTFail($0.localizedDescription)
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }

    func testGetUserKeys() {
        let exp = expectation(description: "Completion")

        firstly {
            createUser()
        }.then {
            self.backend.getUserKeys(userId: self.signedInUser.userId)
        }.done { userPublicKeysResponse in
            XCTAssertEqual(userPublicKeysResponse.identityKey, self.publicKeys.identityKey)
            XCTAssertEqual(userPublicKeysResponse.signingKey, self.publicKeys.signingKey)
            XCTAssertEqual(userPublicKeysResponse.signedPrekey, self.publicKeys.signedPrekey)
            XCTAssertEqual(userPublicKeysResponse.prekeySignature, self.publicKeys.prekeySignature)
            XCTAssertEqual(userPublicKeysResponse.oneTimePrekey, self.publicKeys.oneTimePrekeys.first!)
        }.catch {
            XCTFail($0.localizedDescription)
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }

    func testUpdateUserPublicKeys() {
        let exp = expectation(description: "Completion")

        let updatedPublicKeys = UserPublicKeys(
            signingKey: publicKeys.signingKey,
            identityKey: publicKeys.identityKey,
            signedPrekey: "newSignedPrekey".data,
            prekeySignature: "newPrekeySignature".data,
            oneTimePrekeys: ["newOneTimePrekey".data]
        )
        
        firstly {
            createUser()
        }.then { () -> Promise<Void> in
            self.backend.updateUser(userId: self.signedInUser.userId, publicKeys: updatedPublicKeys, deviceId: nil, publicName: nil)
        }.then {
            self.backend.getUserKeys(userId: self.signedInUser.userId)
        }.done { userPublicKeysResponse in
            XCTAssertEqual(userPublicKeysResponse.identityKey, updatedPublicKeys.identityKey)
            XCTAssertEqual(userPublicKeysResponse.signingKey, updatedPublicKeys.signingKey)
            XCTAssertEqual(userPublicKeysResponse.signedPrekey, updatedPublicKeys.signedPrekey)
            XCTAssertEqual(userPublicKeysResponse.prekeySignature, updatedPublicKeys.prekeySignature)
            XCTAssertEqual(userPublicKeysResponse.oneTimePrekey, updatedPublicKeys.oneTimePrekeys.first!)
        }.catch {
            XCTFail($0.localizedDescription)
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }
    
    func testUpdateUserPublicName() {
        let exp = expectation(description: "Completion")
        
        let updatedPublicName = "updatedPublicName"
        
        firstly {
            createUser()
        }.then { () -> Promise<Void> in
            self.backend.updateUser(userId: self.signedInUser.userId, publicKeys: nil, deviceId: nil, publicName: updatedPublicName)
        }.then {
            self.backend.getUser(userId: self.signedInUser.userId)
        }.done { userReponse in
            XCTAssertEqual(userReponse.publicName, updatedPublicName)
        }.catch {
            XCTFail($0.localizedDescription)
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }

    // MARK: Group
    
    func testGroupInterface() {
        let exp = expectation(description: "Completion")
        
        var groupId = GroupId()
        var encryptedSettings = "encryptedSettings".data
        var encryptedInternalSettings = "encryptedInternalSettings".data
        
        var encryptedMembership = "encryptedMembership".data
        let tokenKey = "tokenKey".data
        
        var serverSignedAdminCertificate: Certificate!
        var groupTag: String!
        
        var notificationRecipient: NotificationRecipient!
        
        firstly {
            createUser()
        }.then { () -> Promise<CreateGroupResponse> in
            self.backend.createGroup(
                userId: self.signedInUser.userId,
                type: .team,
                joinMode: .open,
                permissionMode: .everyone,
                groupId: groupId,
                parentGroup: nil,
                selfSignedAdminCertificate: "adminCertificate",
                encryptedSettings: encryptedSettings,
                encryptedInternalSettings: encryptedInternalSettings
            )
        }.then { createGroupResponse -> Promise<UpdatedEtagResponse> in
            groupTag = createGroupResponse.groupTag
            serverSignedAdminCertificate = createGroupResponse.serverSignedAdminCertificate
            notificationRecipient = NotificationRecipient(userId: self.signedInUser.userId, serverSignedMembershipCertificate: serverSignedAdminCertificate, priority: nil)
            
            // Add group member
            
            return self.backend.addGroupMember(
                groupId: groupId,
                userId: self.signedInUser.userId,
                encryptedMembership: encryptedMembership,
                serverSignedMembershipCertificate: createGroupResponse.serverSignedAdminCertificate,
                newTokenKey: tokenKey,
                groupTag: groupTag,
                notificationRecipients: [notificationRecipient]
            )
        }.then { updatedEtagResponse -> Promise<GroupInformationResponse> in
            groupTag = updatedEtagResponse.groupTag
            
            // Get group information
            
            return self.backend.getGroupInformation(groupId: groupId, groupTag: nil)
        }.then { groupInformationResponse -> Promise<GroupInternalsResponse> in
            
            XCTAssertEqual(groupInformationResponse.groupId, groupId)
            XCTAssertEqual(groupInformationResponse.joinMode, .open)
            XCTAssertEqual(groupInformationResponse.permissionMode, .everyone)
            XCTAssertEqual(groupInformationResponse.type, .team)
            XCTAssertEqual(groupInformationResponse.encryptedSettings, encryptedSettings)
            XCTAssertEqual(groupInformationResponse.url, URL(string: "https://develop.tice.app/group/\(groupId)"))
            
            // Get group internals
            
            return self.backend.getGroupInternals(groupId: groupId, serverSignedMembershipCertificate: serverSignedAdminCertificate, groupTag: nil)
        }.then { groupInternalsResponse -> Promise<JoinGroupResponse> in
            
            XCTAssertEqual(groupInternalsResponse.groupId, groupId)
            XCTAssertEqual(groupInternalsResponse.joinMode, .open)
            XCTAssertEqual(groupInternalsResponse.permissionMode, .everyone)
            XCTAssertEqual(groupInternalsResponse.type, .team)
            XCTAssertEqual(groupInternalsResponse.encryptedSettings, encryptedSettings)
            XCTAssertEqual(groupInternalsResponse.url, URL(string: "https://develop.tice.app/group/\(groupId)"))
            XCTAssertEqual(groupInternalsResponse.encryptedInternalSettings, encryptedInternalSettings)
            XCTAssertTrue(groupInternalsResponse.children.isEmpty)
            XCTAssertEqual(groupInternalsResponse.encryptedMemberships, [encryptedMembership])
            XCTAssertNil(groupInternalsResponse.parentEncryptedGroupKey)
            XCTAssertNil(groupInternalsResponse.parentGroupId)
            
            // Join group
            
            return self.backend.joinGroup(groupId: groupId, selfSignedMembershipCertificate: "selfSignedMembershipCertificate", serverSignedAdminCertificate: nil, adminSignedMembershipCertificate: nil, groupTag: groupTag)
        }.then { _ -> Promise<UpdatedEtagResponse> in
            // Update member
            
            encryptedMembership = "updatedEncryptedMembership".data
            
            return self.backend.updateGroupMember(
                groupId: groupId,
                userId: self.signedInUser.userId,
                encryptedMembership: encryptedMembership,
                serverSignedMembershipCertificate: serverSignedAdminCertificate,
                tokenKey: tokenKey,
                groupTag: groupTag,
                notificationRecipients: [notificationRecipient]
            )
        }.then { updatedEtagResponse -> Promise<UpdatedEtagResponse> in
            groupTag = updatedEtagResponse.groupTag
            
            // Update settings
            
            encryptedSettings = "updatedEncryptedSettings".data
            
            return self.backend.updateSettings(
                groupId: groupId,
                encryptedSettings: encryptedSettings,
                serverSignedMembershipCertificate: serverSignedAdminCertificate,
                groupTag: groupTag,
                notificationRecipients: [notificationRecipient]
            )
        }.then { updatedEtagResponse -> Promise<UpdatedEtagResponse> in
            groupTag = updatedEtagResponse.groupTag
            
            // Update internals
            
            encryptedInternalSettings = "updatedEncryptedInternalSettings".data
            
            return self.backend.updateInternalSettings(
                groupId: groupId,
                encryptedInternalSettings: encryptedInternalSettings,
                serverSignedMembershipCertificate: serverSignedAdminCertificate,
                groupTag: groupTag,
                notificationRecipients: [notificationRecipient]
            )
        }.then { updatedEtagResponse -> Promise<UpdatedEtagResponse> in
            groupTag = updatedEtagResponse.groupTag
            
            // Delete member
            
            return self.backend.deleteGroupMember(
                groupId: groupId,
                userId: self.signedInUser.userId,
                userServerSignedMembershipCertificate: serverSignedAdminCertificate,
                ownServerSignedMembershipCertificate: serverSignedAdminCertificate,
                tokenKey: tokenKey,
                groupTag: groupTag,
                notificationRecipients: []
            )
        }.then { updatedEtagResponse -> Promise<Void> in
            groupTag = updatedEtagResponse.groupTag
            
            // Delete group
            
            groupId = GroupId()
            return firstly { () -> Promise<CreateGroupResponse> in
                self.backend.createGroup(
                    userId: self.signedInUser.userId,
                    type: .team,
                    joinMode: .open,
                    permissionMode: .everyone,
                    groupId: groupId,
                    parentGroup: nil,
                    selfSignedAdminCertificate: "adminCertificate",
                    encryptedSettings: encryptedSettings,
                    encryptedInternalSettings: encryptedInternalSettings
                )
            }.then { createGroupResponse -> Promise<Void> in
                serverSignedAdminCertificate = createGroupResponse.serverSignedAdminCertificate
                groupTag = createGroupResponse.groupTag
                
                return self.backend.deleteGroup(
                    groupId: groupId,
                    serverSignedAdminCertificate: serverSignedAdminCertificate,
                    groupTag: groupTag,
                    notificationRecipients: [notificationRecipient]
                )
            }
        }.catch {
            XCTFail($0.localizedDescription)
        }.finally {
            exp.fulfill()
        }
        
        wait(for: [exp])
    }
    
    func testSendMessage() {
        let exp = expectation(description: "Completion")

        let groupId = GroupId()
        var serverSignedAdminCertificate: Certificate!
        var groupTag: String!
        
        var otherSignedInUser: SignedInUser!
        var serverSignedUserCertificate: Certificate!
        
        let encryptedMessage = "encryptedMessage".data
        let encryptedMessageKey = "encryptedMessageKey".data
        
        firstly { () -> Promise<Void> in
            createUser()
        }.then { () -> Promise<CreateUserResponse> in
            self.backend.createUser(
                publicKeys: self.publicKeys,
                platform: .iOS,
                deviceId: self.deviceToken,
                verificationCode: "SIM-IOS",
                publicName: nil
            )
        }.then { createUserResponse -> Promise<Void> in
            otherSignedInUser = SignedInUser(
                userId: createUserResponse.userId,
                privateSigningKey: self.privateSigningKey,
                publicSigningKey: self.publicKeys.signingKey,
                publicName: nil
            )
            
            return firstly { () -> Promise<CreateGroupResponse> in
                self.backend.createGroup(
                    userId: self.signedInUser.userId,
                    type: .team,
                    joinMode: .open,
                    permissionMode: .everyone,
                    groupId: groupId,
                    parentGroup: nil,
                    selfSignedAdminCertificate: "adminCertificate",
                    encryptedSettings: "encryptedSettings".data,
                    encryptedInternalSettings: "encryptedInternalSettings".data
                )
            }.then { createGroupResponse -> Promise<UpdatedEtagResponse> in
                serverSignedAdminCertificate = createGroupResponse.serverSignedAdminCertificate
                
                return self.backend.addGroupMember(
                    groupId: groupId,
                    userId: self.signedInUser.userId,
                    encryptedMembership: "encryptedMembership".data,
                    serverSignedMembershipCertificate: createGroupResponse.serverSignedAdminCertificate,
                    newTokenKey: "tokenKey".data,
                    groupTag: createGroupResponse.groupTag,
                    notificationRecipients: []
                )
            }.then { updatedEtagResponse -> Promise<JoinGroupResponse> in
                groupTag = updatedEtagResponse.groupTag
                
                stub(self.signedInUserManager) { stub in
                    when(stub.requireSignedInUser()).thenReturn(otherSignedInUser)
                }
                
                return self.backend.joinGroup(
                    groupId: groupId,
                    selfSignedMembershipCertificate: "userCertificate",
                    serverSignedAdminCertificate: nil,
                    adminSignedMembershipCertificate: nil,
                    groupTag: updatedEtagResponse.groupTag)
            }.then { joinGroupResponse -> Promise<UpdatedEtagResponse> in
                serverSignedUserCertificate = joinGroupResponse.serverSignedMembershipCertificate
                
                return self.backend.addGroupMember(
                    groupId: groupId,
                    userId: otherSignedInUser.userId,
                    encryptedMembership: "encryptedMembership".data,
                    serverSignedMembershipCertificate: joinGroupResponse.serverSignedMembershipCertificate,
                    newTokenKey: "tokenKey".data,
                    groupTag: groupTag,
                    notificationRecipients: []
                )
            }.done { updatedEtagResponse in
                groupTag = updatedEtagResponse.groupTag
            }
        }.then { () -> Promise<Void> in
            self.backend.message(
                id: MessageId(),
                senderId: otherSignedInUser.userId,
                timestamp: Date(),
                encryptedMessage: encryptedMessage,
                serverSignedMembershipCertificate: serverSignedUserCertificate,
                recipients: Set([Recipient(userId: self.signedInUser.userId, serverSignedMembershipCertificate: serverSignedAdminCertificate, encryptedMessageKey: encryptedMessageKey, conversationInvitation: nil)]),
                priority: .deferred,
                collapseId: nil
            )
        }.then { () -> Promise<GetMessagesResponse> in
            stub(self.signedInUserManager) { stub in
                when(stub.requireSignedInUser()).thenReturn(self.signedInUser)
            }
            
            return self.backend.getMessages()
        }.done { getMessagesResponse in
            guard let envelope = getMessagesResponse.messages.first,
                  case let payloadContainer = envelope.payloadContainer,
                  let payload = payloadContainer.payload as? EncryptedPayloadContainer else {
                XCTFail()
                return
            }
            
            XCTAssertEqual(envelope.senderId, otherSignedInUser.userId)
            XCTAssertEqual(envelope.payloadContainer.payloadType, .encryptedPayloadContainerV1)
            XCTAssertEqual(payload.ciphertext, encryptedMessage)
            XCTAssertEqual(payload.encryptedKey, encryptedMessageKey)
        }.catch {
            XCTFail($0.localizedDescription)
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }
    
    func testRenewCertificate() {
        let exp = expectation(description: "Completion")
        
        firstly { () -> Promise<Void> in
            createUser()
        }.then { () -> Promise<CreateGroupResponse> in
            self.backend.createGroup(
                userId: self.signedInUser.userId,
                type: .team,
                joinMode: .open,
                permissionMode: .everyone,
                groupId: GroupId(),
                parentGroup: nil,
                selfSignedAdminCertificate: "adminCertificate",
                encryptedSettings: "encryptedSettings".data,
                encryptedInternalSettings: "encryptedInternalSettings".data
            )
        }.then {
            self.backend.renewCertificate($0.serverSignedAdminCertificate)
        }.catch {
            XCTFail($0.localizedDescription)
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }
}
