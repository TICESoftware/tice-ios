//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Chatto
import ChattoAdditions

class MessageInteractionHandler<Message: MessageModelProtocol, ViewModel: MessageViewModelProtocol>: BaseMessageInteractionHandlerProtocol {
    func userDidTapOnFailIcon(message: Message, viewModel: ViewModel, failIconView: UIView) {
    }
    
    func userDidTapOnAvatar(message: Message, viewModel: ViewModel) {
    }
    
    func userDidTapOnBubble(message: Message, viewModel: ViewModel) {
    }
    
    func userDidBeginLongPressOnBubble(message: Message, viewModel: ViewModel) {
    }
    
    func userDidEndLongPressOnBubble(message: Message, viewModel: ViewModel) {
    }
    
    func userDidSelectMessage(message: Message, viewModel: ViewModel) {
    }
    
    func userDidDeselectMessage(message: Message, viewModel: ViewModel) {
    }
    
    func userDidDoubleTapOnBubble(message: Message, viewModel: ViewModel) {
    }
}
