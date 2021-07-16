//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

protocol AvatarGeneratorType {
    func generateInvalidUserAvatar(size: CGSize) -> UIImage
    func generateAvatar(name: String, userId: UserId, size: CGSize, rounded: Bool) -> UIImage
    func generateColor(userId: UserId) -> UIColor
    func extractLetters(name: String) -> String
}

class AvatarGenerator: AvatarGeneratorType {

    let colors: [UIColor]

    init(colors: [UIColor]) {
        self.colors = colors
    }

    func generateInvalidUserAvatar(size: CGSize) -> UIImage {
        let avatar = drawAvatar(letters: "",
                                backgroundColor: UIColor.gray.cgColor,
                                lettersColor: UIColor.white,
                                size: size)

        return avatar ?? UIImage()
    }
    
    func generateColor(userId: UserId) -> UIColor {
        let index = abs(userId.uuidString.hashCode) % colors.count
        return colors[index]
    }

    func generateAvatar(name: String, userId: UserId, size: CGSize, rounded: Bool) -> UIImage {
        let backgroundColor = generateColor(userId: userId).cgColor
        let letters = extractLetters(name: name)

        let avatar = drawAvatar(letters: letters,
                                backgroundColor: backgroundColor,
                                lettersColor: UIColor.white,
                                size: size,
                                rounded: rounded)

        return avatar ?? UIImage()
    }

    func extractLetters(name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let components = trimmedName.components(separatedBy: " ").filter { $0 != "" }
        switch (components.count, trimmedName.count) {
        case (0, _):
            return L10n.User.Avatar.default
        case (1, ...1):
            let string = components.first!
            return String(string[string.startIndex])
        case (1, 2...):
            let string = components.first!
            return String(string[string.startIndex...string.index(after: string.startIndex)])
        default:
            let letters: [String] = [components.first!, components.last!].map { component in
                return String(component[component.startIndex])
            }
            return letters.joined()
        }
    }

    private func drawAvatar(letters: String, backgroundColor: CGColor, lettersColor: UIColor, size: CGSize, rounded: Bool = false) -> UIImage? {
        let rect = CGRect(origin: .zero, size: size)

        UIGraphicsBeginImageContextWithOptions(rect.size, false, UIScreen.main.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        if rounded {
            let radius = min(size.width, size.height)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
            context.addPath(path.cgPath)
            context.clip()
        }

        context.setFillColor(backgroundColor)
        context.fill(rect)
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: NSParagraphStyle.default.mutableCopy(),
            .font: UIFont.systemFont(ofSize: min(size.height, size.width) / 2.0),
            .foregroundColor: lettersColor
        ]

        let lettersSize = letters.size(withAttributes: attributes)
        let lettersRect = CGRect(
            x: (rect.size.width - lettersSize.width) / 2.0,
            y: (rect.size.height - lettersSize.height) / 2.0,
            width: lettersSize.width,
            height: lettersSize.height
        )
        letters.draw(in: lettersRect, withAttributes: attributes)
        let avatarImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return avatarImage
    }
}
