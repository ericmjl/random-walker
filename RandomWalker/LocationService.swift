import CoreLocation
import Foundation
import SwiftUI

@MainActor
final class LocationService: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var locationError: Error?

    private var coordinateWaiter: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.activityType = .fitness
        manager.distanceFilter = 5
        authorizationStatus = manager.authorizationStatus
    }

    /// Whether the user can tap “plan”; denied/restricted blocks until Settings change.
    var canStartPlanning: Bool {
        switch authorizationStatus {
        case .denied, .restricted:
            return false
        case .notDetermined, .authorizedAlways, .authorizedWhenInUse:
            return true
        @unknown default:
            return false
        }
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdates() {
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
    }

    /// Uses a recent fix if available; otherwise waits for a one-shot `requestLocation` up to `maxWait`.
    func coordinateForWalkStart(maxWait: Duration = .seconds(25)) async -> CLLocationCoordinate2D? {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            return nil
        }

        let staleThreshold: TimeInterval = 30
        if let last = lastLocation, Date().timeIntervalSince(last.timestamp) < staleThreshold {
            return last.coordinate
        }

        return await withCheckedContinuation { continuation in
            coordinateWaiter = continuation
            manager.requestLocation()

            Task { @MainActor in
                try? await Task.sleep(for: maxWait)
                resumeCoordinateWaitIfNeeded(with: lastLocation?.coordinate)
            }
        }
    }

    private func resumeCoordinateWaitIfNeeded(with value: CLLocationCoordinate2D?) {
        guard let waiter = coordinateWaiter else { return }
        coordinateWaiter = nil
        waiter.resume(returning: value)
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in
            lastLocation = latest
            if let latest {
                resumeCoordinateWaitIfNeeded(with: latest.coordinate)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationError = error
            resumeCoordinateWaitIfNeeded(with: lastLocation?.coordinate)
        }
    }
}
