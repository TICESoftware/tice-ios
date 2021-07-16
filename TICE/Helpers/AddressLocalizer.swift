//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Contacts
import CoreLocation
import OpenLocationCode

protocol AddressLocalizerType {
    func short(annotation: Annotation) -> String
    func short(placemark: CLPlacemark) -> String
    
    func full(annotation: Annotation) -> String
    func full(placemark: CLPlacemark) -> String
    
    func generic(coordinate: CLLocationCoordinate2D, relativeTo: CLLocationCoordinate2D?) -> String
}

class AddressLocalizer: AddressLocalizerType {

    private let locationManager: LocationManagerType
    private let formatter: CNPostalAddressFormatter

    init(locationManager: LocationManagerType) {
        self.formatter = CNPostalAddressFormatter()
        self.formatter.style = .mailingAddress
        self.locationManager = locationManager
    }
    
    func short(annotation: Annotation) -> String {
        guard let placemark = annotation.placemark else {
            return generic(coordinate: annotation.location.coordinate, relativeTo: locationManager.currentUserLocation?.coordinate)
        }
        return short(placemark: placemark)
    }

    func short(placemark: CLPlacemark) -> String {
        guard let postalAddress = placemark.postalAddress,
            let address = formatter.string(from: postalAddress) as String?,
            let firstLine = address.components(separatedBy: "\n").first,
            !firstLine.isEmpty else {
                return generic(placemark: placemark, relativeTo: locationManager.currentUserLocation?.coordinate)
        }

        return firstLine
    }
    
    func full(annotation: Annotation) -> String {
        guard let placemark = annotation.placemark else {
            return generic(coordinate: annotation.location.coordinate, relativeTo: locationManager.currentUserLocation?.coordinate)
        }
        return full(placemark: placemark)
    }

    func full(placemark: CLPlacemark) -> String {
        guard let postalAddress = placemark.postalAddress,
            let address = formatter.string(from: postalAddress) as String?,
            !address.isEmpty else {
                return generic(placemark: placemark, relativeTo: locationManager.currentUserLocation?.coordinate)
        }

        let components = address.components(separatedBy: "\n")
        let oneLine = components.joined(separator: ", ")
        return oneLine
    }
    
    func generic(placemark: CLPlacemark, relativeTo: CLLocationCoordinate2D? = nil) -> String {
        guard let location = placemark.location else {
            return L10n.Map.Location.unknown
        }
        return generic(coordinate: location.coordinate, relativeTo: relativeTo)
    }
    
    func generic(coordinate: CLLocationCoordinate2D, relativeTo: CLLocationCoordinate2D? = nil) -> String {
        guard let plusCode = plusCode(coordinate: coordinate, relativeTo: relativeTo) else {
            return String(format: "%.3f, %.3f", coordinate.longitude, coordinate.latitude)
        }
        return plusCode
    }
    
    func plusCode(coordinate: CLLocationCoordinate2D, relativeTo: CLLocationCoordinate2D? = nil) -> String? {
        guard let fullCode = OpenLocationCode.encode(latitude: coordinate.latitude, longitude: coordinate.longitude) else { return nil }
        
        if let relativeTo = relativeTo {
            return OpenLocationCode.shorten(code: fullCode, latitude: relativeTo.latitude, longitude: relativeTo.longitude)
        } else {
            return fullCode
        }
    }
}
