//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

class MockTracker: TrackerType {
    func start() {}
    
    func logSessionStart() {}
    
    func logSessionEnd() {}
    
    func log(action: TrackerAction, category: TrackerCategory) {}
    
    func log(action: TrackerAction, category: TrackerCategory, detail: String?) {}
    
    func log(action: TrackerAction, category: TrackerCategory, detail: String?, number: Double?) {}
}
