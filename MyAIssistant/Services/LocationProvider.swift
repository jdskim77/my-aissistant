import CoreLocation
import Foundation
import os.log

/// Thin CLLocationManager wrapper that exposes async authorization + one-shot
/// location fetch. Kept deliberately minimal — weather only needs a reduced-
/// accuracy fix, not continuous updates.
///
/// Authorization is lazy: nothing is requested until `ensureAuthorization()`
/// is first called. This keeps the permission prompt out of app launch.
@MainActor
final class LocationProvider: NSObject {
    private let manager = CLLocationManager()
    private var pendingLocation: CheckedContinuation<CLLocation, Error>?
    private var pendingAuthorization: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var timeoutTask: Task<Void, Never>?
    // Gates the authorization delegate callback: without this, every
    // `locationManagerDidChangeAuthorization` fire (app launch, Settings
    // toggle) would try to resume a continuation we never set up.
    private var hasRequestedAuthorization = false

    enum LocationError: Error {
        case denied
        case unavailable
        case busy
        case timeout
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// Returns true if whenInUse (or finer) is granted. Prompts the user
    /// only on `.notDetermined`; returns false immediately on denied/restricted.
    /// Rejects overlapping calls rather than leaking continuations.
    func ensureAuthorization() async -> Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .notDetermined:
            if pendingAuthorization != nil { return false }
            hasRequestedAuthorization = true
            manager.requestWhenInUseAuthorization()
            let status = await withCheckedContinuation { cont in
                pendingAuthorization = cont
            }
            return status == .authorizedWhenInUse || status == .authorizedAlways
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// One-shot location fetch with a 15s timeout. Throws `.denied` if
    /// authorization is refused, `.busy` if another fetch is in flight,
    /// `.timeout` if the system never returns a fix.
    func requestCurrentLocation() async throws -> CLLocation {
        guard await ensureAuthorization() else { throw LocationError.denied }
        guard pendingLocation == nil else { throw LocationError.busy }

        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.failPendingLocationWithTimeout()
        }
        defer {
            timeoutTask?.cancel()
            timeoutTask = nil
        }

        return try await withCheckedThrowingContinuation { cont in
            pendingLocation = cont
            manager.requestLocation()
        }
    }

    private func failPendingLocationWithTimeout() {
        guard let cont = pendingLocation else { return }
        pendingLocation = nil
        cont.resume(throwing: LocationError.timeout)
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // Only resume when we actually issued a prompt. This callback
            // also fires on app launch and on Settings changes; resuming a
            // stale continuation from those would be a bug.
            guard hasRequestedAuthorization, let cont = pendingAuthorization else { return }
            pendingAuthorization = nil
            hasRequestedAuthorization = false
            cont.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in
            guard let cont = pendingLocation else { return }
            pendingLocation = nil
            if let last {
                cont.resume(returning: last)
            } else {
                cont.resume(throwing: LocationError.unavailable)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let cont = pendingLocation else { return }
            pendingLocation = nil
            cont.resume(throwing: error)
        }
    }
}
