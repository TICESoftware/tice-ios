//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation

struct BoundingBox: Decodable {
    struct Coordinate: Decodable {
        let lat: Double
        let lon: Double
    }
    
    let sw: Coordinate
    let ne: Coordinate
    
    func coordinateArray() -> [CLLocationCoordinate2D] {
        return [CLLocationCoordinate2D(latitude: sw.lat, longitude: sw.lon),
                CLLocationCoordinate2D(latitude: ne.lat, longitude: ne.lon)]
    }
}

protocol RegionGeocoderType {
    func currentLocaleRegion() -> BoundingBox
}

class RegionGeocoder: RegionGeocoderType {
    
    typealias ISO3316Alpha3 = String
    typealias ISO3316Alpha2 = String
    
    let decoder: JSONDecoder
    
    lazy var countriesBoundingBoxes: [ISO3316Alpha3: BoundingBox] = {
        // swiftlint:disable:next force_try
        let countriesBoundingBoxesData = try! Data(contentsOf: URL(fileReferenceLiteralResourceName: "countriesBoundingBoxes.json"))
        // swiftlint:disable:next force_try
        return try! self.decoder.decode([ISO3316Alpha3: BoundingBox].self, from: countriesBoundingBoxesData)
    }()
    lazy var iso3316Map: [ISO3316Alpha2: ISO3316Alpha3] = {
        // swiftlint:disable:next force_try
        let iso3316Data = try! Data(contentsOf: URL(fileReferenceLiteralResourceName: "iso3316.json"))
        // swiftlint:disable:next force_try
        return try! self.decoder.decode([ISO3316Alpha2: ISO3316Alpha3].self, from: iso3316Data)
    }()
    
    init(decoder: JSONDecoder) {
        self.decoder = decoder
    }
    
    func currentLocaleRegion() -> BoundingBox {
        guard let regionCode = Locale.current.regionCode else {
            return defaultRegion
        }
        return region(code: regionCode)
    }
    
    func region(code: String) -> BoundingBox {
        guard let alpha3Code = iso3316Map[code],
            let boundingBox = countriesBoundingBoxes[alpha3Code] else {
            return defaultRegion
        }
        return boundingBox
    }
    
    var defaultRegion: BoundingBox {
        BoundingBox(sw: BoundingBox.Coordinate(lat: 52.8, lon: 12.9),
                    ne: BoundingBox.Coordinate(lat: 52.4, lon: 13.8))
    }
}
