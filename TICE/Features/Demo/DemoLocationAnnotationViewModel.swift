//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation
import PromiseKit
import Observable
import UIKit

class DemoLocationAnnotationViewModel: AnnotationDetailViewModel {
    
    var annotation: LocationAnnotation
    let demoManager: DemoManagerType
    let geocoder: GeocoderType
    let addressLocalizer: AddressLocalizerType
    
    weak var delegate: TeamMapViewController?
    
    var title: MutableObservable<String>
    var description: MutableObservable<String>
    var closeButtonVisible: MutableObservable<Bool>
    
    var avatar: MutableObservable<UIImage?>
    
    var primaryButtonTitle: MutableObservable<String>
    var primaryButtonEnabled: MutableObservable<Bool>
    var primaryButtonVisible: MutableObservable<Bool>
    
    var secondaryButtonTitle: MutableObservable<String>
    var secondaryButtonEnabled: MutableObservable<Bool>
    var secondaryButtonVisible: MutableObservable<Bool>
    
    init(annotation: LocationAnnotation, demoManager: DemoManagerType, geocoder: GeocoderType, addressLocalizer: AddressLocalizerType) {
        self.annotation = annotation
        self.demoManager = demoManager
        self.geocoder = geocoder
        self.addressLocalizer = addressLocalizer
        
        title = .init(L10n.LocationAnnotationDetail.title)
        description = .init("")
        closeButtonVisible = .init(true)
        
        avatar = .init(nil)
        
        primaryButtonTitle = .init(L10n.LocationAnnotationDetail.createMeetingPoint)
        primaryButtonEnabled = .init(true)
        primaryButtonVisible = .init(true)
        
        secondaryButtonTitle = .init("")
        secondaryButtonEnabled = .init(false)
        secondaryButtonVisible = .init(false)
        
        demoManager.didMarkLocation()
    }
    
    func update() {
        firstly {
            geocoder.reverseGeocode(location: annotation.location)
        }.done { [weak self] placemark in
            guard let self = self else { return }
            self.annotation.placemark = placemark
        }.ensure {
            self.updateDescription()
        }.cauterize()
    }
    
    func updateDescription() {
        description.wrappedValue = addressLocalizer.full(annotation: annotation)
    }
    
    func close() {
        demoManager.didHideAnnotation()
        delegate?.remove(annotation: annotation)
        delegate?.hideDetails()
    }
    
    func hide() {
        demoManager.didHideAnnotation()
        delegate?.hideDetails()
    }
    
    func primaryAction() {
        demoManager.didCreateMeetingPoint(location: annotation.location.coordinate)
        delegate?.show(meetingPoint: annotation.location.location)
        close()
    }
    
    func secondaryAction() {
        
    }
}
