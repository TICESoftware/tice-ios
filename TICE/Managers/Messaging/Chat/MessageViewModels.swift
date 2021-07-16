//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import ChattoAdditions

class TextMessageViewModel: TextMessageViewModelProtocol {
    let text: String
    let cellAccessibilityIdentifier: String = "app.tice.chat.textMessage.cell"
    let bubbleAccessibilityIdentifier: String = "app.tice.chat.textMessage.bubble"

    public let messageViewModel: MessageViewModelProtocol

    init(text: String, messageViewModel: MessageViewModelProtocol) {
        self.text = text
        self.messageViewModel = messageViewModel
    }
}

class TextMessageViewModelBuilder: ViewModelBuilderProtocol {
    let messageViewModelBuilder = MessageViewModelDefaultBuilder()
    let userManager: UserManagerType
    let avatarSupplier: AvatarSupplierType

    init(userManager: UserManagerType, avatarSupplier: AvatarSupplierType) {
        self.userManager = userManager
        self.avatarSupplier = avatarSupplier
    }

    func createViewModel(_ model: TextMessage) -> TextMessageViewModel {
        let messageViewModel = self.messageViewModelBuilder.createMessageViewModel(model)
        let textMessageViewModel = TextMessageViewModel(text: model.text, messageViewModel: messageViewModel)

        if let userId = UserId(uuidString: model.senderId),
            let user = userManager.user(userId) {
            textMessageViewModel.avatarImage = .init(avatarSupplier.avatar(user: user, size: CGSize(width: 20, height: 20), rounded: true))
        }

        return textMessageViewModel
    }

    public func canCreateViewModel(fromModel model: Any) -> Bool {
        return model is TextMessage
    }
}

class PhotoMessageViewModel: PhotoMessageViewModelProtocol {
    var transferDirection: Observable<TransferDirection>
    var transferProgress: Observable<Double>
    var transferStatus: Observable<TransferStatus>
    var image: Observable<UIImage?>

    var imageSize: CGSize { return image.value?.size ?? CGSize.zero }
    let cellAccessibilityIdentifier: String = "app.tice.chat.photoMessage.cell"
    let bubbleAccessibilityIdentifier: String = "app.tice.chat.photoMessage.bubble"

    let messageViewModel: MessageViewModelProtocol

    init(photoMessage: PhotoMessage, messageViewModel: MessageViewModelProtocol) {
        self.transferDirection = photoMessage.isIncoming ? Observable(.download) : Observable(.upload)
        self.transferProgress = Observable(0.0)
        self.transferStatus = Observable(.idle)
        self.image = photoMessage.isIncoming ? Observable(nil) : Observable(photoMessage.image)

        self.messageViewModel = messageViewModel
    }
}

class PhotoMessageViewModelBuilder: ViewModelBuilderProtocol {

    let messageViewModelBuilder = MessageViewModelDefaultBuilder()
    let userManager: UserManagerType
    let avatarSupplier: AvatarSupplierType

    init(userManager: UserManagerType, avatarSupplier: AvatarSupplierType) {
        self.userManager = userManager
        self.avatarSupplier = avatarSupplier
    }

    func createViewModel(_ model: PhotoMessage) -> PhotoMessageViewModel {
        let messageViewModel = self.messageViewModelBuilder.createMessageViewModel(model)
        let photoMessageViewModel = PhotoMessageViewModel(photoMessage: model, messageViewModel: messageViewModel)

        if let userId = UserId(uuidString: model.senderId),
            let user = userManager.user(userId) {
            photoMessageViewModel.avatarImage = .init(avatarSupplier.avatar(user: user, size: CGSize(width: 20, height: 20), rounded: true))
        }

        return photoMessageViewModel
    }

    func canCreateViewModel(fromModel model: Any) -> Bool {
        return model is PhotoMessage
    }
}
