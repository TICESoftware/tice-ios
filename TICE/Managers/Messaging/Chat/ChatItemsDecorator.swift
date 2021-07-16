//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Chatto
import ChattoAdditions

class ChatItemsDecorator: ChatItemsDecoratorProtocol {
    private enum Constants {
        static let shortSeparation: CGFloat = 3
        static let normalSeparation: CGFloat = 10
        static let timeIntervalThresholdToIncreaseSeparation: TimeInterval = 120
    }

    func decorateItems(_ chatItems: [ChatItemProtocol]) -> [DecoratedChatItem] {
        var decoratedChatItems = [DecoratedChatItem]()
        let calendar = Calendar.current

        for (index, chatItem) in chatItems.enumerated() {
            let next: ChatItemProtocol? = (index + 1 < chatItems.count) ? chatItems[index + 1] : nil
            let prev: ChatItemProtocol? = (index > 0) ? chatItems[index - 1] : nil

            let bottomMargin = self.separationAfterItem(chatItem, next: next)
            var showsTail = false
            var additionalItems = [DecoratedChatItem]()
            var addTimeSeparator = false

            if let currentMessage = chatItem as? MessageModelProtocol {
                if let nextMessage = next as? MessageModelProtocol {
                    showsTail = currentMessage.senderId != nextMessage.senderId
                } else {
                    showsTail = true
                }

                if self.showsStatusForMessage(currentMessage) {
                    additionalItems.append(
                        DecoratedChatItem(
                            chatItem: SendingStatusModel(uid: "\(currentMessage.uid)-decoration-status", status: currentMessage.status),
                            decorationAttributes: nil)
                    )
                }
            }
            
            if let currentMessage = chatItem as? DateableProtocol {
                if let previousMessage = prev as? DateableProtocol {
                    addTimeSeparator = !calendar.isDate(currentMessage.date, inSameDayAs: previousMessage.date)
                } else {
                    addTimeSeparator = true
                }
                
                if addTimeSeparator {
                    let timeSeperatorItem = TimeSeparatorModel(uid: "\(currentMessage.uid)-time-separator", date: currentMessage.date.toWeekDayAndDateString())
                    let dateTimeStamp = DecoratedChatItem(chatItem: timeSeperatorItem,
                                                          decorationAttributes: nil)
                    decoratedChatItems.append(dateTimeStamp)
                }
            }

            let messageDecorationAttributes = BaseMessageDecorationAttributes(
                canShowFailedIcon: true,
                isShowingTail: showsTail,
                isShowingAvatar: showsTail,
                isShowingSelectionIndicator: false,
                isSelected: false
            )

            decoratedChatItems.append(
                DecoratedChatItem(
                    chatItem: chatItem,
                    decorationAttributes: ChatItemDecorationAttributes(bottomMargin: bottomMargin, messageDecorationAttributes: messageDecorationAttributes)
                )
            )
            decoratedChatItems.append(contentsOf: additionalItems)
        }

        return decoratedChatItems
    }

    private func separationAfterItem(_ current: ChatItemProtocol?, next: ChatItemProtocol?) -> CGFloat {
        guard let nexItem = next else { return 0 }
        guard let currentMessage = current as? MessageModelProtocol else { return Constants.normalSeparation }
        guard let nextMessage = nexItem as? MessageModelProtocol else { return Constants.normalSeparation }

        if self.showsStatusForMessage(currentMessage) {
            return 0
        } else if currentMessage.senderId != nextMessage.senderId {
            return Constants.normalSeparation
        } else if nextMessage.date.timeIntervalSince(currentMessage.date) > Constants.timeIntervalThresholdToIncreaseSeparation {
            return Constants.normalSeparation
        } else {
            return Constants.shortSeparation
        }
    }

    private func showsStatusForMessage(_ message: MessageModelProtocol) -> Bool {
        return message.status == .failed || message.status == .sending
    }
}
