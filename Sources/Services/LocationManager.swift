import Foundation
import CoreLocation
import WidgetKit
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationName: String = "" {
        didSet {
            // Share location name with widget
            sharedDefaults?.set(locationName, forKey: "locationName")
            // Trigger widget update
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let sharedDefaults = UserDefaults(suiteName: "group.sunday.widget")
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .fitness
        
        // Try to restore last known location from UserDefaults
        if let savedLat = UserDefaults.standard.object(forKey: "lastKnownLatitude") as? Double,
           let savedLon = UserDefaults.standard.object(forKey: "lastKnownLongitude") as? Double,
           let savedAlt = UserDefaults.standard.object(forKey: "lastKnownAltitude") as? Double {
            location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: savedLat, longitude: savedLon),
                altitude: savedAlt,
                horizontalAccuracy: 100,
                verticalAccuracy: 50,
                timestamp: Date()
            )
            
            // Also restore location name
            if let savedName = UserDefaults.standard.string(forKey: "lastKnownLocationName") {
                locationName = savedName
            }
        }
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        location = newLocation
        
        // Save location for offline use
        UserDefaults.standard.set(newLocation.coordinate.latitude, forKey: "lastKnownLatitude")
        UserDefaults.standard.set(newLocation.coordinate.longitude, forKey: "lastKnownLongitude")
        UserDefaults.standard.set(newLocation.altitude, forKey: "lastKnownAltitude")
        
        // Reverse geocode to get location name
        geocoder.reverseGeocodeLocation(newLocation) { [weak self] placemarks, error in
            guard let self = self,
                  let placemark = placemarks?.first else { return }
            
            DispatchQueue.main.async {
                // Prefer neighborhood, then locality, then administrative area
                if let neighborhood = placemark.subLocality {
                    self.locationName = neighborhood
                } else if let city = placemark.locality {
                    self.locationName = city
                } else if let area = placemark.administrativeArea {
                    self.locationName = area
                } else {
                    self.locationName = ""
                }
                
                // Save location name for offline use
                if !self.locationName.isEmpty {
                    UserDefaults.standard.set(self.locationName, forKey: "lastKnownLocationName")
                }
            }
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
        default:
            stopUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent error handling - errors are handled by checking location status
    }
}
