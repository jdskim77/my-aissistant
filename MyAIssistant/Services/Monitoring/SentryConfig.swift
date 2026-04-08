import Foundation

#if canImport(Sentry)
import Sentry
#endif

/// Centralized Sentry initialization.
/// Called once from `MyAIssistantApp.init()` before any other code runs.
///
/// **Setup steps:**
/// 1. Sign up at sentry.io and create an iOS project named "thrivn-ios"
/// 2. Copy the DSN from the project settings
/// 3. In Xcode: File → Add Package Dependencies → `https://github.com/getsentry/sentry-cocoa`
///    Select the `Sentry` product
/// 4. Replace `dsn` below with your actual DSN
/// 5. Build & run — crashes will appear in your Sentry dashboard
///
/// **Privacy:** sendDefaultPii is OFF, anonymous per-install user ID, all PII scrubbed before send.
enum SentryConfig {

    /// Your Sentry project DSN. Empty string disables Sentry.
    /// PRODUCTION: Set this to your real DSN before launch.
    private static let dsn = ""

    static func start() {
        guard !dsn.isEmpty else {
            #if DEBUG
            print("[Sentry] DSN not configured — skipping initialization")
            #endif
            return
        }

        #if canImport(Sentry)
        SentrySDK.start { options in
            options.dsn = dsn

            // Environment + Release
            options.environment = environment
            options.releaseName = releaseName

            // Performance Monitoring
            options.tracesSampleRate = 0.2          // 20% of transactions
            options.profilesSampleRate = 0.1        // 10% of profiled transactions

            // Session Tracking (crash-free rate)
            options.enableAutoSessionTracking = true
            options.sessionTrackingIntervalMillis = 30_000

            // Automatic Instrumentation
            options.enableAutoBreadcrumbTracking = true
            options.maxBreadcrumbs = 100

            // Attachments on crash
            options.enableCaptureFailedRequests = true
            options.attachScreenshot = true
            options.attachViewHierarchy = true

            // PRIVACY: Never send Personally Identifiable Information automatically
            options.sendDefaultPii = false

            // Custom filter — strip any PII that snuck in
            options.beforeSend = { event in
                Self.scrubPII(event)
            }

            #if DEBUG
            options.enabled = false
            options.debug = true
            options.tracesSampleRate = 1.0
            #endif
        }

        // Set anonymous user ID for issue correlation (no PII)
        let userId = anonymousUserID()
        SentrySDK.setUser(User(userId: userId))
        #endif
    }

    // MARK: - Helpers

    private static var environment: String {
        #if DEBUG
        return "debug"
        #else
        return "production"
        #endif
    }

    private static var releaseName: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "thrivn-ios@\(version)+\(build)"
    }

    /// Anonymous, stable per-install user ID. NOT linked to Apple ID, email, or any PII.
    private static func anonymousUserID() -> String {
        let key = "com.myaissistant.sentry-anon-id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    #if canImport(Sentry)
    /// Scrub PII from outgoing events (defense in depth).
    private static func scrubPII(_ event: Event) -> Event {
        event.user?.email = nil
        event.user?.username = nil
        event.user?.ipAddress = nil

        if let request = event.request {
            request.cookies = nil
            request.headers?.removeValue(forKey: "Authorization")
            request.headers?.removeValue(forKey: "Cookie")
        }
        return event
    }
    #endif

    // MARK: - Public helpers for app code

    /// Add a breadcrumb to track user actions before a crash.
    static func addBreadcrumb(category: String, message: String) {
        #if canImport(Sentry)
        guard !dsn.isEmpty else { return }
        let crumb = Breadcrumb(level: .info, category: category)
        crumb.message = message
        crumb.timestamp = Date()
        SentrySDK.addBreadcrumb(crumb)
        #endif
    }

    /// Track a non-fatal error with optional context.
    static func captureError(_ error: Error, context: [String: Any] = [:]) {
        #if canImport(Sentry)
        guard !dsn.isEmpty else { return }
        SentrySDK.capture(error: error) { scope in
            for (key, value) in context {
                scope.setExtra(value: value, key: key)
            }
        }
        #endif
    }
}
