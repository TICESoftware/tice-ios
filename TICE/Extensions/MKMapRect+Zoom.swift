//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import MapKit

extension MKMapRect {

    func zoomed(minimumZoom: Double = 750) -> MKMapRect {

        var width = self.width
        var height = self.height

        var needChange = false
        if width < minimumZoom {
            width = minimumZoom
            needChange = true
        }
        
        if height < minimumZoom {
            height = minimumZoom
            needChange = true
        }

        if needChange {
            let minX = midX - width / 2
            let minY = midY - height / 2
            return MKMapRect(x: minX, y: minY, width: width, height: height)
        }

        return self
    }

}
