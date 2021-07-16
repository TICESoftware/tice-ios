//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

public class InternalReceiver: Receiver {
    weak var delegate: EnvelopeReceiverDelegate?
}
