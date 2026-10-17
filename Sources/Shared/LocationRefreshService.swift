import Foundation
import CoreLocation

/// Run by the settings app in the background when a screensaver starts.
/// This service never asks for authorization or displays user interface.
/// Storage stays in the companion's ordinary Application Support directory;
/// it never opens another app's protected container.
final class LocationRefreshService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let completion: () -> Void
    private var timeout: Timer?
    private var running = false
    private var requestedLocation = false
    private var completed = false

    init(completion: @escaping () -> Void) {
        self.completion = completion
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
    }

    func start() {
        guard !running, !completed else { return }
        running = true
        guard OceanPreferences.load().coordinateSource == .current,
              CLLocationManager.locationServicesEnabled() else {
            finish()
            return
        }
        timeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.finish()
        }
        refreshIfAuthorized()
    }

    private func refreshIfAuthorized() {
        guard running, !completed else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requestedLocation else { return }
            requestedLocation = true
            manager.requestLocation()
        case .notDetermined, .denied, .restricted:
            // Authorization is exclusively an interactive settings-app action.
            finish()
        @unknown default:
            finish()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running, !completed,
              let location = locations.last(where: { $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 120 }) else { return }
        let coordinate = GeographicCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        guard coordinate.isValid else { return }
        // Preserve a manual location or rendering change saved while the request was in flight.
        var preferences = OceanPreferences.load()
        if preferences.coordinateSource == .current {
            preferences.coordinate = coordinate
            preferences.savedDate = Date()
            // A background refresh must never interrupt the locked-screen experience.
            // Interactive saves surface the same storage errors in the settings window.
            try? preferences.save()
        }
        finish()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish() }

    private func finish() {
        guard !completed else { return }
        completed = true
        running = false
        timeout?.invalidate()
        timeout = nil
        manager.stopUpdatingLocation()
        manager.delegate = nil
        completion()
    }
}
