//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

func LocalizedString(_ key: String, comment: String? = nil, bundle: Bundle = Bundle.main) -> String {
    return NSLocalizedString(key, bundle: bundle, comment: comment ?? "")
}

func LocalizedFormattedString(_ key: String, _ formatted: String...) -> String {
    let formatString = LocalizedString(key)
    return String.init(format: formatString, arguments: formatted)
}

func LocalizedList(_ strings: [String]) -> String {
    switch strings.count {
    case 0: return ""
    case 1: return strings[0]
    case 2: return L10n.General.List.two(strings[0], strings[1])
    default:
        let start = L10n.General.List.start(strings[0], strings[1])
        let startAndMiddle = strings[2..<strings.count - 1].reduce(start) { prefix, name in
            return L10n.General.List.middle(prefix, name)
        }
        let startMiddleEnd = L10n.General.List.end(startAndMiddle, strings.last!)
        return startMiddleEnd
    }
}
