//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Swinject
import SwinjectStoryboard
import SwinjectAutoregistration
import ConvAPI
import Shouter
import CoreLocation
import Valet
import UserNotifications
import Beekeeper
import Logging
import Sniffer
import GRDB
import TICEAuth
import Starscream
import X3DH
import DoubleRatchet

extension Container {
    public func registerSingleton<Service>(
        _ serviceType: Service.Type,
        name: String? = nil,
        factory: @escaping (Resolver) -> Service) {
        register(serviceType, name: name, factory: factory).inObjectScope(.container)
    }
}

class DependencyRegistrator {

    lazy var config: Config = {
        #if DEBUG
        return Config.infoPlist.overwrittenFromUserDefaults()
        #else
        return Config.infoPlist
        #endif
    }()

    func setupCommonContainer(container: Container) {
        setupCommonConfiguredHelpers(container: container, config: config)
        setupCommonSingletons(container: container, config: config)
    }

    func setupCommonConfiguredHelpers(container: Container, config: Config) {
        container.register(JSONDecoder.self) { _ in JSONDecoder.decoderWithFractionalSeconds }
        container.register(JSONEncoder.self) { _ in JSONEncoder.encoderWithFractionalSeconds }
        container.register(Logger.self) { _ in logger.swiftLogger }
        container.register(DeepLinkParserType.self) { r in
            return DeepLinkParser(teamManager: r~>, meetupManager: r~>, groupStorageManager: r~>, baseURL: config.backendBaseURL)
        }
        container.register(AvatarGeneratorType.self) { _ in
            return AvatarGenerator(colors: UIColor.palette)
        }
        container.autoregister(CLGeocoder.self, initializer: CLGeocoder.init)
        container.autoregister(GeocoderType.self, initializer: Geocoder.init).inObjectScope(.container)
        container.autoregister(AddressLocalizerType.self, initializer: AddressLocalizer.init).inObjectScope(.container)
        container.register(MigrationManagerType.self) { r in
            return MigrationManager(storageManager: r~>, minPreviousVersion: config.minPreviousVersion)
        }
        container.register(UpdateCheckerType.self) { r in
            return UpdateChecker(backendURL: config.backendBaseURL, api: r~>, currentVersion: config.buildNumber)
        }
        container.register(TeamChatDataSourceType.self) { r, team in
            return TeamChatDataSource(team: team,
                                  chatStorageManager: r~>,
                                  chatManager: r~>,
                                  signedInUser: r~>,
                                  messageSender: r~>,
                                  notifier: r~>,
                                  loadLimit: config.chatLoadLimit)
        }
    }

    func setupCommonSingletons(container: Container, config: Config) {
        container.registerSingleton(Notifier.self) { _ in Shouter.default }
        container.registerSingleton(TICEAPI.self) { r in
            return TICEBackend(api: r~>,
                               baseURL: config.backendBaseURL,
                               clientVersion: config.version,
                               clientBuild: config.buildNumber,
                               clientPlatform: config.platform,
                               authManager: r~>,
                               signedInUserManager: r~>)
        }
        container.registerSingleton(API.self) { r in
            let api = ConvAPI(requester: r~>)
            api.decoder = r~>
            api.encoder = r~>
            return api
        }
        container.registerSingleton(URLSessionConfiguration.self) { _ in
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.urlCache = nil
            sessionConfiguration.httpCookieAcceptPolicy = .never
            sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            sessionConfiguration.shouldUseExtendedBackgroundIdleMode = true
            sessionConfiguration.timeoutIntervalForRequest = 30
            return sessionConfiguration
        }
        container.registerSingleton(AsynchronousRequester.self) { r in
            let sharedURLSession = URLSession(configuration: r~>)
            sharedURLSession.delegateQueue.maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount
            return sharedURLSession
        }
        // swiftlint:disable:next force_cast
        container.registerSingleton(EnvelopeReceiverDelegate?.self) { r in r.resolve(PostOfficeType.self) as! PostOffice }
        container.registerSingleton(PushReceiverType.self) { r in
            let pushReceiver = PushReceiver(decoder: r~>, timeout: config.pushReceiverTimeout)
            pushReceiver.delegate = r~>
            return pushReceiver
        }
        container.registerSingleton(Container.self) { _ in
            return container
        }
        container.registerSingleton(PseudonymGeneratorType.self) { _ in
            return PseudonymGenerator(url: config.pseudonymNamesFileURL)
        }
        container.register(UserDefaults.self) { _ in
            return UserDefaults(suiteName: config.appGroupName)!
        }
        container.registerSingleton(Valet.self) { _ in
            return Valet.sharedAccessGroupValet(with: Identifier(nonEmpty: config.valetId)!, accessibility: .afterFirstUnlock)
        }
        container.registerSingleton(DatabaseManagerType.self) { r in
            return DatabaseManager(valet: r~>,
                                   container: r~>,
                                   cryptoManager: CryptoManager(),
                                   tableCreator: r~>,
                                   databaseURL: config.databaseURL,
                                   databaseKeyLength: config.databaseKeyLength)
        }
        container.register(DatabaseReader.self) { r in
            return r.resolve(DatabaseWriter.self)!
        }
        container.autoregister(CryptoManagerType.self, initializer: CryptoManager.init).inObjectScope(.container)
        container.autoregister(AuthManagerType.self, initializer: AuthManager.init).inObjectScope(.container)
        container.autoregister(TableCreatorType.self, initializer: TableCreator.init).inObjectScope(.container)
        container.autoregister(SignedInUserStorageManagerType.self, initializer: SignedInUserStorageManager.init).inObjectScope(.container)
        container.autoregister(ServerCertificateStorageManagerType.self.self, initializer: ServerCertificateStorageManager.init).inObjectScope(.container)
        container.autoregister(ApplicationStorageManagerType.self, initializer: ApplicationStorageManager.init).inObjectScope(.container)
        container.autoregister(GroupStorageManagerType.self, initializer: GroupStorageManager.init).inObjectScope(.container)
        container.autoregister(PostOfficeStorageManagerType.self, initializer: PostOfficeStorageManager.init).inObjectScope(.container)
        container.autoregister(ConversationStorageManagerType.self, initializer: ConversationStorageManager.init).inObjectScope(.container)
        container.autoregister(LocationStorageManagerType.self, initializer: LocationStorageManager.init).inObjectScope(.container)
        container.autoregister(UserStorageManagerType.self, initializer: UserStorageManager.init).inObjectScope(.container)
        container.autoregister(ChatStorageManagerType.self, initializer: ChatStorageManager.init).inObjectScope(.container)
        container.autoregister(MessageSenderType.self, initializer: MessageSender.init).inObjectScope(.container)
        container.autoregister(RegionGeocoderType.self, initializer: RegionGeocoder.init).inObjectScope(.container)
        container.autoregister(VersionStorageManagerType.self, initializer: VersionStorageManager.init).inObjectScope(.container)
        container.autoregister(X3DHType.self, initializer: X3DH.init).inObjectScope(.container)
        container.autoregister(DoubleRatchetProviderType.self, initializer: DoubleRatchetProvider.init).inObjectScope(.container)

        container.register(ConversationCryptoMiddlewareType.self) { r in
            return ConversationCryptoMiddleware(cryptoManager: r~>,
                                                cryptoStorageManager: r~>,
                                                handshake: r~>,
                                                doubleRatchetProvider: r~>,
                                                encoder: r~>,
                                                decoder: r~>,
                                                logger: r~>,
                                                maxSkip: config.cryptoParams.maxSkip,
                                                maxCache: config.cryptoParams.maxCache,
                                                info: config.cryptoParams.info,
                                                oneTimePrekeyCount: config.cryptoParams.maxOneTimePrekeyCount)
        }
        container.registerSingleton(MailboxType.self) { r in
            return Mailbox(backend: r~>,
                           signedInUser: r~>,
                           cryptoManager: r~>,
                           conversationManager: r~>,
                           encoder: r~>)
        }
        container.register(CryptoStorageManagerType.self) { r in
            return CryptoStorageManager(valet: r~>,
                                        userDefaults: r~>,
                                        database: r~>,
                                        encoder: r~>,
                                        decoder: r~>,
                                        oneTimePrekeysMaxCount: config.cryptoParams.maxOneTimePrekeyCount)
        }
        container.registerSingleton(ConversationManagerType.self) { r in
            return ConversationManager(cryptoManager: r~>,
                                       conversationCryptoMiddleware: r~>,
                                       storageManager: r~>,
                                       postOffice: r~>,
                                       backend: r~>,
                                       decoder: r~>,
                                       tracker: r~>,
                                       collapsingConversationIdentifier: config.collapsingConversationIdentifier,
                                       nonCollapsingConversationIdentifier: config.nonCollapsingConversationIdentifier,
                                       resendResetTimeout: config.resendResetTimeout)
        }
        container.registerSingleton(PostOfficeType.self) { r in
        return PostOffice(storageManager: r~>,
                          backend: r~>,
                          envelopeCacheTime: config.envelopeCacheTime)
        }
        
        container.registerSingleton(LocationSharingManagerType.self) { r in
            return LocationSharingManager(locationStorageManager: r~>,
                                          groupManager: r~>,
                                          groupStorageManager: r~>,
                                          userManager: r~>,
                                          signedInUser: r~>,
                                          postOffice: r~>,
                                          notifier: r~>,
                                          checkTime: config.checkOutdatedLocationSharingStateInterval,
                                          locationMaxAge: config.locationMaxAge)
        }

        container.registerSingleton(MeetupManagerType.self) { r in
            return MeetupManager(groupManager: r~>,
                                 groupStorageManager: r~>,
                                 signedInUser: r~>,
                                 cryptoManager: r~>,
                                 authManager: r~>,
                                 locationManager: r~>,
                                 backend: r~>,
                                 encoder: r~>,
                                 decoder: r~>,
                                 tracker: r~>,
                                 reloadTimeout: config.meetupReloadTimeout)
        }

        container.registerSingleton(TeamBroadcaster.self) { r in
            // swiftlint:disable:next force_cast
            return r.resolve(TeamManagerType.self) as! TeamManager
        }

        container.autoregister(GroupNotificationReceiverType.self, initializer: GroupNotificationReceiver.init).inObjectScope(.container)
        container.autoregister(ChatMessageReceiverType.self, initializer: ChatMessageReceiver.init).inObjectScope(.container)
        container.autoregister(UserManagerType.self, initializer: UserManager.init).inObjectScope(.container)
        container.autoregister(GroupManagerType.self, initializer: GroupManager.init).inObjectScope(.container)
        container.autoregister(TeamManagerType.self, initializer: TeamManager.init).inObjectScope(.container)
        container.autoregister(NameSupplierType.self, initializer: NameSupplier.init).inObjectScope(.container)
        container.autoregister(DeviceTokenManagerType.self, initializer: DeviceTokenManager.init).inObjectScope(.container)
        container.autoregister(TooFewOneTimePrekeysHandlerType.self, initializer: TooFewOneTimePrekeysHandler.init).inObjectScope(.container)
        container.autoregister(ChatManagerType.self, initializer: ChatManager.init).inObjectScope(.container)

        container.registerSingleton(WebSocketType.self) { _ in
            return WebSocket(url: config.backendWebSocketURL)
        }
        
        container.registerSingleton(WebSocketReceiver.self) { r in
            let webSocketReceiver = WebSocketReceiver(webSocket: r~>,
                                                      signedInUserManager: r~>,
                                                      authManager: r~>,
                                                      decoder: r~>,
                                                      notifier: r~>,
                                                      reconnectTime: config.webSocketReconnectTime)
            webSocketReceiver.delegate = r~>
            return webSocketReceiver
        }
        
        let locationManager = CLLocationManager()
        container.registerSingleton(CLLocationManagerType.self) { _ in locationManager }
        container.autoregister(InstallationDateStorageManagerType.self, initializer: InstallationDateStorageManager.init).inObjectScope(.container)
        
        container.registerSingleton(LocationManagerType.self) { r in
            return LocationManager(clLocationManager: r~>,
                                   locationStorageManager: r~>,
                                   userManager: r~>,
                                   postOffice: r~>,
                                   notifier: r~>,
                                   tracker: r~>,
                                   signedInUser: r~>,
                                   locationResendTimeout: config.locationResendTimeout,
                                   locationMaxAge: config.locationMaxAge)
        }

        container.registerSingleton(SignedInUserManagerType.self) { r in
            return SignedInUserManager(signedInUserStorageManager: r~>,
                                       userStorageManager: r~>,
                                       notifier: r~>,
                                       tracker: r~>,
                                       container: container,
                                       resolver: r~>)
        }

        container.registerSingleton(UNUserNotificationCenterType.self) { _ in
            return UNUserNotificationCenter.current()
        }

        container.register(Storage.self) { r in
            return r.resolve(UserDefaults.self)!
        }

        container.registerSingleton(BeekeeperType.self) { r in
            return Beekeeper(product: config.trackerParams.product,
                             dispatcher: r~>,
                             storage: r~>)
        }

        container.register(Signer.self) { _ in
            return RequestSigner(secret: config.trackerParams.secret)
        }

        container.register(Dispatcher.self) { r in
            return URLDispatcher(baseURL: config.trackerParams.baseURL,
                                 path: config.trackerParams.path,
                                 signer: r~>,
                                 timeout: config.trackerParams.timeout,
                                 maxBatchSize: config.trackerParams.maxBatchSize,
                                 backend: r~>)
        }

        container.autoregister(AvatarSupplierType.self, initializer: AvatarSupplier.init).inObjectScope(.container)
        container.autoregister(NotificationManagerType.self, initializer: NotificationManager.init).inObjectScope(.container)
        container.autoregister(TrackerType.self, initializer: Tracker.init).inObjectScope(.container)
        
        #if !EXTENSION
        container.autoregister(DemoStorageManagerType.self, initializer: DemoStorageManager.init).inObjectScope(.container)
        container.autoregister(DemoManagerType.self, initializer: DemoManager.init).inObjectScope(.container)
        #endif
    }
}
