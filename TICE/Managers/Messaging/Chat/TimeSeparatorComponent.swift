//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Chatto

class TimeSeparatorModel: ChatItemProtocol {
    let uid: String
    var type: String { ChatComponent.timeSeparator.rawValue }
    let date: String

    init(uid: String, date: String) {
        self.date = date
        self.uid = uid
    }
}

extension Date {
    // Have a timestamp formatter to avoid keep creating new ones. This improves performance
    private static let weekdayAndDateStampDateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.autoupdatingCurrent
        dateFormatter.dateFormat = "EEEE, MMM dd yyyy" // "Monday, Mar 7 2016"
        return dateFormatter
    }()

    func toWeekDayAndDateString() -> String {
        return Date.weekdayAndDateStampDateFormatter.string(from: self)
    }
}

public class TimeSeparatorPresenterBuilder: ChatItemPresenterBuilderProtocol {

    public func canHandleChatItem(_ chatItem: ChatItemProtocol) -> Bool {
        return chatItem is TimeSeparatorModel
    }

    public func createPresenterWithChatItem(_ chatItem: ChatItemProtocol) -> ChatItemPresenterProtocol {
        // swiftlint:disable:next force_cast
        return TimeSeparatorPresenter(timeSeparatorModel: chatItem as! TimeSeparatorModel)
    }

    public var presenterType: ChatItemPresenterProtocol.Type {
        return TimeSeparatorPresenter.self
    }
}

class TimeSeparatorPresenter: ChatItemPresenterProtocol {

    let timeSeparatorModel: TimeSeparatorModel
    init (timeSeparatorModel: TimeSeparatorModel) {
        self.timeSeparatorModel = timeSeparatorModel
    }

    private static let cellReuseIdentifier = TimeSeparatorCollectionViewCell.self.description()

    static func registerCells(_ collectionView: UICollectionView) {
        collectionView.register(TimeSeparatorCollectionViewCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
    }

    let isItemUpdateSupported = false

    func update(with chatItem: ChatItemProtocol) {}

    func dequeueCell(collectionView: UICollectionView, indexPath: IndexPath) -> UICollectionViewCell {
        return collectionView.dequeueReusableCell(withReuseIdentifier: TimeSeparatorPresenter.cellReuseIdentifier, for: indexPath)
    }

    func configureCell(_ cell: UICollectionViewCell, decorationAttributes: ChatItemDecorationAttributesProtocol?) {
        guard let timeSeparatorCell = cell as? TimeSeparatorCollectionViewCell else {
            assert(false, "expecting status cell")
            return
        }

        timeSeparatorCell.text = self.timeSeparatorModel.date
    }

    var canCalculateHeightInBackground: Bool {
        true
    }

    func heightForCell(maximumWidth width: CGFloat, decorationAttributes: ChatItemDecorationAttributesProtocol?) -> CGFloat {
        24
    }
}

class TimeSeparatorCollectionViewCell: UICollectionViewCell {

    private let label: UILabel = UILabel()

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
        self.label.bounds.size = self.label.sizeThatFits(self.contentView.bounds.size)
        self.label.center = self.contentView.center
    }
}
