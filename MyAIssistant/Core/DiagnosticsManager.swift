import Foundation
import MetricKit
import OSLog

/// Subscribes to MetricKit diagnostic payloads (hangs, crashes, disk writes)
/// delivered by iOS. Logs key metrics and stores payloads for upload.
@Observable @MainActor
final class DiagnosticsManager: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsManager()

    // Local loggers for nonisolated delegate methods (can't use AppLogger from nonisolated context)
    private nonisolated static let perfLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.thrivn",
        category: "Performance"
    )
    private nonisolated static let appLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.thrivn",
        category: "App"
    )

    func startCollecting() {
        MXMetricManager.shared.add(self)
        AppLogger.app.info("MetricKit subscriber registered")
    }

    // MARK: - MXMetricManagerSubscriber

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if payload.applicationLaunchMetrics != nil {
                Self.perfLog.info("MetricKit: launch metrics received")
            }
            if payload.applicationResponsivenessMetrics != nil {
                Self.perfLog.warning("MetricKit: responsiveness metrics received")
            }
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
                Self.appLog.fault("MetricKit: crash diagnostic(s) received")
            }
            if payload.hangDiagnostics != nil {
                Self.perfLog.error("MetricKit: hang diagnostic(s) received")
            }
            if payload.diskWriteExceptionDiagnostics != nil {
                Self.perfLog.warning("MetricKit: excessive disk write diagnostic(s) received")
            }
        }
    }
}
