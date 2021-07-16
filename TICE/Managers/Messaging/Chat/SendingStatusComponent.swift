//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import UIKit
import Foundation
import Chatto
import ChattoAdditions

// This is a dirty implementation that shows what's needed to add a new type of element

class SendingStatusModel: ChatItemProtocol {
    let uid: String

    var type: String { return ChatComponent.sendingStatus.rawValue }
    let status: MessageStatus

    init (uid: String, status: MessageStatus) {
        self.uid = uid
        self.status = status
    }
}

public class SendingStatusPresenterBuilder: ChatItemPresenterBuilderProtocol {

    public func canHandleChatItem(_ chatItem: ChatItemProtocol) -> Bool {
        chatItem is SendingStatusModel
    }

    public func createPresenterWithChatItem(_ chatItem: ChatItemProtocol) -> ChatItemPresenterProtocol {
        // swiftlint:disable:next force_cast
        SendingStatusPresenter(statusModel: chatItem as! SendingStatusModel)
    }

    public var presenterType: ChatItemPresenterProtocol.Type {
        SendingStatusPresenter.self
    }
}

class SendingStatusPresenter: ChatItemPresenterProtocol {

    let statusModel: SendingStatusModel
    init (statusModel: SendingStatusModel) {
        self.statusModel = statusModel
    }

    static func registerCells(_ collectionView: UICollectionView) {
        collectionView.register(UINib(nibName: "SendingStatusCollectionViewCell", bundle: Bundle(for: self)), forCellWithReuseIdentifier: "SendingStatusCollectionViewCell")
    }

    let isItemUpdateSupported = false

    func update(with chatItem: ChatItemProtocol) {}

    func dequeueCell(collectionView: UICollectionView, indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SendingStatusCollectionViewCell", for: indexPath)
        return cell
    }

    func configureCell(_ cell: UICollectionViewCell, decorationAttributes: ChatItemDecorationAttributesProtocol?) {
        guard let statusCell = cell as? SendingStatusCollectionViewCell else {
            assert(false, "expecting status cell")
            return
        }

        let attrs = [
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: 10.0),
            NSAttributedString.Key.foregroundColor: self.statusModel.status == .failed ? UIColor.red : UIColor.black
        ]
        statusCell.text = NSAttributedString(
            string: self.statusText(),
            attributes: attrs)
    }

    func statusText() -> String {
        switch self.statusModel.status {
        case .failed:
            return L10n.Chat.SendingCell.failed
        case .sending:
            return L10n.Chat.SendingCell.sending
        default:
            return ""
        }
    }

    var canCalculateHeightInBackground: Bool {
        true
    }

    func heightForCell(maximumWidth width: CGFloat, decorationAttributes: ChatItemDecorationAttributesProtocol?) -> CGFloat {
        19
    }
}

class SendingStatusCollectionViewCell: UICollectionViewCell {

    @IBOutlet private weak var label: UILabel!

    var text: NSAttributedString? {
        didSet {
            self.label.attributedText = self.text
        }
    }
}
