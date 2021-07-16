//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Chatto

func executeOnMainQueue<T>(_ closure: () -> T) -> T {
    if Thread.isMainThread {
        return closure()
    } else {
        return DispatchQueue.main.sync {
            return closure()
        }
    }
}

class MetaMessage: ChatItemProtocol, ReadableMessageProtocol, DateableProtocol {
    
    let uid: String
    let message: String
    let date: Date
    
    var read: Bool
    
    var type: String { ChatComponent.meta.rawValue }

    init(uid: String, date: Date, message: String, read: Bool) {
        self.uid = uid
        self.date = date
        self.message = message
        self.read = read
    }
}

public class MetaMessagePresenterBuilder: ChatItemPresenterBuilderProtocol {

    public func canHandleChatItem(_ chatItem: ChatItemProtocol) -> Bool {
        return chatItem is MetaMessage
    }

    public func createPresenterWithChatItem(_ chatItem: ChatItemProtocol) -> ChatItemPresenterProtocol {
        // swiftlint:disable:next force_cast
        return MetaMessagePresenter(model: chatItem as! MetaMessage)
    }

    public var presenterType: ChatItemPresenterProtocol.Type {
        return MetaMessagePresenter.self
    }
}

class MetaMessagePresenter: ChatItemPresenterProtocol {

    let model: MetaMessage
    let sizingCell: MetaMessageCollectionViewCell
    let dateFormatter: DateFormatter
    
    init (model: MetaMessage) {
        self.model = model
        self.sizingCell = MetaMessageCollectionViewCell.sizingCell()
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateStyle = .none
        self.dateFormatter.timeStyle = .short
    }

    private static let cellReuseIdentifier = MetaMessageCollectionViewCell.self.description()

    static func registerCells(_ collectionView: UICollectionView) {
        collectionView.register(MetaMessageCollectionViewCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
    }

    let isItemUpdateSupported = false

    func update(with chatItem: ChatItemProtocol) {}

    func dequeueCell(collectionView: UICollectionView, indexPath: IndexPath) -> UICollectionViewCell {
        return collectionView.dequeueReusableCell(withReuseIdentifier: Self.cellReuseIdentifier, for: indexPath)
    }

    func configureCell(_ cell: UICollectionViewCell, decorationAttributes: ChatItemDecorationAttributesProtocol?) {
        guard let cell = cell as? MetaMessageCollectionViewCell else {
            assert(false, "expecting status cell")
            return
        }

        let timeString = dateFormatter.string(from: model.date)
        cell.text = "\(self.model.message) – \(timeString)"
    }

    var canCalculateHeightInBackground: Bool {
        true
    }

    func heightForCell(maximumWidth width: CGFloat, decorationAttributes: ChatItemDecorationAttributesProtocol?) -> CGFloat {
        executeOnMainQueue {
            let labelHeight = sizingCell.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            let bottomMargin = decorationAttributes?.bottomMargin ?? 0
            return 19 + labelHeight + bottomMargin
        }
    }
}

class MetaMessageCollectionViewCell: UICollectionViewCell {

    private let label: UILabel = UILabel()
    
    static func sizingCell() -> MetaMessageCollectionViewCell {
        executeOnMainQueue {
            let cell = MetaMessageCollectionViewCell(frame: CGRect.zero)
            return cell
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.commonInit()
    }

    private func commonInit() {
        self.label.font = UIFont.systemFont(ofSize: 12)
        self.label.numberOfLines = 0
        self.label.textAlignment = .center
        self.label.textColor = UIColor.gray
        self.contentView.addSubview(label)
    }

    var text: String = "" {
        didSet {
            if oldValue != text {
                self.setTextOnLabel(text)
            }
        }
    }

    private func setTextOnLabel(_ text: String) {
        self.label.text = text
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.label.bounds.size = self.label.sizeThatFits(self.contentView.bounds.size.bma_insetBy(dx: 8, dy: 0))
        self.label.center = self.contentView.center
    }
    
    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        return label.sizeThatFits(size)
    }
}
