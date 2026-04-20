import CoreLocation
import Foundation
import WeatherKit
import os.log

/// Snapshot of the data the Home chip and Today's Context sheet need.
/// Keeps WeatherKit types out of the view layer so the feature can be
/// tested or swapped later without touching UI code.
struct WeatherSnapshot {
    let temperature: Measurement<UnitTemperature>
    let conditionSymbolName: String
    let conditionDescription: String
    let dailyHigh: Measurement<UnitTemperature>?
    let dailyLow: Measurement<UnitTemperature>?
    let sunrise: Date?
    let sunset: Date?
    let fetchedAt: Date
}

/// Fetches current conditions via WeatherKit and caches for 30 min so we
/// don't hammer the API on every Home re-render. Permission is driven by
/// `LocationProvider` — this manager stays out of the CLLocationManager path.
@MainActor
@Observable
final class WeatherManager {
    private let service = WeatherService.shared
    private let locationProvider: LocationProvider

    private(set) var latest: WeatherSnapshot?
    private(set) var isLoading = false
    private(set) var lastErrorMessage: String?

    private let cacheLifetime: TimeInterval = 30 * 60

    init(locationProvider: LocationProvider) {
        self.locationProvider = locationProvider
    }

    var isAuthorized: Bool { locationProvider.isAuthorized }

    /// Auto-refresh path used on Home appear — only fetches if authorized
    /// and the cache is stale. Never prompts for permission.
    func refreshIfAuthorizedAndStale() async {
        guard locationProvider.isAuthorized else { return }
        if let latest, Date().timeIntervalSince(latest.fetchedAt) < cacheLifetime {
            return
        }
        await refresh()
    }

    /// User-initiated refresh. Prompts for location if not yet determined.
    /// Re-entrancy guarded — spamming pull-to-refresh won't issue parallel
    /// WeatherKit calls.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let location = try await locationProvider.requestCurrentLocation()
            let weather = try await service.weather(for: location)
            let today = weather.dailyForecast.first
            latest = WeatherSnapshot(
                temperature: weather.currentWeather.temperature,
                conditionSymbolName: weather.currentWeather.symbolName,
                conditionDescription: Self.humanReadable(weather.currentWeather.condition),
                dailyHigh: today?.highTemperature,
                dailyLow: today?.lowTemperature,
                sunrise: today?.sun.sunrise,
                sunset: today?.sun.sunset,
                fetchedAt: Date()
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = Self.friendlyMessage(for: error)
            AppLogger.app.error("Weather fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Maps underlying errors to user-facing copy. Raw NSError strings are
    /// technical ("The operation couldn't be completed…") — users see this
    /// in the Today's Context sheet, so it needs plain language.
    private static func friendlyMessage(for error: Error) -> String {
        if let locErr = error as? LocationProvider.LocationError {
            switch locErr {
            case .denied: return "Location access is off. Enable it in Settings to see local weather."
            case .timeout: return "Couldn't get your location. Try again in a moment."
            case .busy: return "Still loading…"
            case .unavailable: return "Location unavailable right now."
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Weather unavailable — check your connection."
        }
        // WeatherKit entitlement / rate-limit errors surface as opaque
        // NSCocoaErrorDomain codes; show a generic message instead of raw text.
        return "Weather unavailable right now."
    }

    /// WeatherKit's `WeatherCondition.description` returns the enum case
    /// name (e.g. "partlyCloudy") — not safe to show to users. This maps
    /// every case to a spaced, capitalized phrase.
    private static func humanReadable(_ condition: WeatherCondition) -> String {
        switch condition {
        case .blizzard: return "Blizzard"
        case .blowingDust: return "Blowing dust"
        case .blowingSnow: return "Blowing snow"
        case .breezy: return "Breezy"
        case .clear: return "Clear"
        case .cloudy: return "Cloudy"
        case .drizzle: return "Drizzle"
        case .flurries: return "Flurries"
        case .foggy: return "Foggy"
        case .freezingDrizzle: return "Freezing drizzle"
        case .freezingRain: return "Freezing rain"
        case .frigid: return "Frigid"
        case .hail: return "Hail"
        case .haze: return "Haze"
        case .heavyRain: return "Heavy rain"
        case .heavySnow: return "Heavy snow"
        case .hot: return "Hot"
        case .hurricane: return "Hurricane"
        case .isolatedThunderstorms: return "Isolated thunderstorms"
        case .mostlyClear: return "Mostly clear"
        case .mostlyCloudy: return "Mostly cloudy"
        case .partlyCloudy: return "Partly cloudy"
        case .rain: return "Rain"
        case .scatteredThunderstorms: return "Scattered thunderstorms"
        case .sleet: return "Sleet"
        case .smoky: return "Smoky"
        case .snow: return "Snow"
        case .strongStorms: return "Strong storms"
        case .sunFlurries: return "Sun and flurries"
        case .sunShowers: return "Sun and showers"
        case .thunderstorms: return "Thunderstorms"
        case .tropicalStorm: return "Tropical storm"
        case .windy: return "Windy"
        case .wintryMix: return "Wintry mix"
        @unknown default: return "Current conditions"
        }
    }
}
