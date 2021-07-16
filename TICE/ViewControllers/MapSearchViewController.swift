//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Pulley
import MapKit

class MapSearchViewController: UIViewController {
    
    var addressLocalizer: AddressLocalizerType!
    var tracker: TrackerType!
    
    @IBOutlet var searchBar: UISearchBar!
    @IBOutlet var tableView: UITableView!
    @IBOutlet var closeButton: UIButton!
    
    weak var delegate: TeamMapViewController?
    weak var mapViewController: MapViewControllerType?
    
    var items: [MKMapItem] = []
    var annotations: [LocationAnnotation] = []
    
    deinit {
        removeAnnotations()
    }
    
    override func viewDidLoad() {
        searchBar.placeholder = L10n.Map.Search.placeholder
        searchBar.becomeFirstResponder()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        mapViewController?.add(annotations: annotations)
    }
    
    @IBAction func didTapCloseButton(_ sender: Any) {
        delegate?.didTapCancelSearch(sender)
    }
    
}

extension MapSearchViewController: PulleyDrawerViewControllerDelegate {
    
    func supportedDrawerPositions() -> [PulleyPosition] {
        return [.partiallyRevealed, .open, .collapsed, .closed]
    }
    
    func drawerPositionDidChange(drawer: PulleyViewController, bottomSafeArea: CGFloat) {
        switch drawer.drawerPosition {
        case .open:
            break
        default:
            searchBar.resignFirstResponder()
        }
    }
}

extension MapSearchViewController: UISearchBarDelegate {
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        tracker.log(action: .searchMap, category: .app)
        
        removeAnnotations()
        searchBar.resignFirstResponder()
        delegate?.setDrawerPosition(position: .partiallyRevealed, animated: true)
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchBar.text
        
        if let region = mapViewController?.mapView.region {
            request.region = region
        }
        
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let response = response else {
                return
            }
            self.items = response.mapItems
            self.annotations = response.mapItems.map { LocationAnnotation(placemark: $0.placemark, addressLocalizer: self.addressLocalizer) }
            self.tableView.reloadData()
            
            self.mapViewController?.add(annotations: self.annotations)
            self.mapViewController?.fit(annotations: self.annotations, includeUserLocation: true, animated: true)
        }
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        delegate?.setDrawerPosition(position: .open, animated: true)
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        delegate?.setDrawerPosition(position: .open, animated: true)
    }
    
    private func removeAnnotations() {
        mapViewController?.remove(annotations: annotations)
    }
}

extension MapSearchViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "MapSearchResultCell", for: indexPath)
        cell.textLabel?.text = item.name
        cell.detailTextLabel?.text = addressLocalizer.full(placemark: item.placemark)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let annotation = annotations[indexPath.row]
        mapViewController?.show(newAnnotation: annotation)
        
        if let userLocation = mapViewController?.mapView.userLocation {
            mapViewController?.mapView.showAnnotations([annotation, userLocation], animated: true)
        }
    }
}
