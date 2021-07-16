//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation
import PromiseKit
import PMKCoreLocation

protocol GeocoderType {
    func reverseGeocode(location: CLLocation) -> Promise<CLPlacemark>
}

class Geocoder: GeocoderType {
    
    let clGeocoder: CLGeocoder
    
    private let cache = NSCache<NSString, CLPlacemark>()
    
    init(clGeocoder: CLGeocoder) {
        self.clGeocoder = clGeocoder
    }
    
    func reverseGeocode(location: CLLocation) -> Promise<CLPlacemark> {
        let cacheAccuracy = 4 // 4 == ~4-11m. Source: https://en.wikipedia.org/wiki/Decimal_degrees#Precision
        let cacheKey = String(format: "%.\(cacheAccuracy)f %.\(cacheAccuracy)f", location.coordinate.longitude, location.coordinate.latitude) as NSString
        if let cachedPlacemark = cache.object(forKey: cacheKey) {
            return .value(cachedPlacemark)
        }
        
        guard !clGeocoder.isGeocoding else {
            return .init(error: PMKError.cancelled)
        }
        
        return clGeocoder.reverseGeocode(location: location).firstValue.get({ self.cache.setObject($0, forKey: cacheKey) })
    }
}
