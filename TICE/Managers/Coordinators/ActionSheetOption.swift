//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

protocol ActionSheetOption: CustomStringConvertible {
    var style: UIAlertAction.Style { get }
}
