//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

protocol ApplicationStorageManagerType {
    func setApplicationIsRunningInForeground(_ value: Bool)
    func applicationIsActive() -> Bool
    func setStartFlowFinished(_ value: Bool)
    func startFlowFinished() -> Bool
}
