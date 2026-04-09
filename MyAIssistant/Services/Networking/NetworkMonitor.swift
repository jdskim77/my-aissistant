import Foundation
import Network
import Observation
import SwiftUI

/// Single source of truth for connectivity state.
///
/// Wraps `NWPathMonitor` and exposes `isConnected` / `isExpensive` as observable
/// properties so views can react to network changes (offline banner, retry
/// buttons, pre-flight checks before doomed network calls).
///
/// Inject at the App root via `.environment(\.networkMonitor, ...)` and consume
/// in any view with `@Environment(\.networkMonitor)`. Pre-flight checks should
/// short-circuit BEFORE the network call so the user sees an instant offline
/// message instead of waiting 60s for `URLSessionConfiguration.waitsForConnectivity`
/// to give up.
@Observable @MainActor
final class NetworkMonitor {
    /// Snapshot of the connection at the moment the monitor reports a path
    /// update. `true` until the first update fires (NWPathMonitor reports
    /// asynchronously, and we'd rather optimistically assume connected than
    /// flash an offline banner on every cold launch).
    private(set) var isConnected: Bool = true

    /// True for cellular, hotspots, or any path the system marks as costly.
    /// Use this to gate large downloads or background sync, not chat.
    private(set) var isExpensive: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor", qos: .utility)

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // NWPathMonitor calls back on its own queue. Hop to MainActor so
            // observers running on the main actor (every SwiftUI view) see a
            // safe, consistent snapshot.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                self.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - Offline Banner Modifier

/// Pinned banner that appears at the top of any screen when the device has no
/// connectivity. Apply via `.offlineBanner()` on the root of any view that
/// presents in its own scene (sheet, fullScreenCover) — `safeAreaInset`
/// applied higher up the hierarchy does NOT propagate into a cover, so
/// network-heavy modal screens like ChatView need their own copy.
struct OfflineBannerModifier: ViewModifier {
    @Environment(\.networkMonitor) private var networkMonitor

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let monitor = networkMonitor, !monitor.isConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(AppFonts.bodyMedium(13))
                        Text("You're offline. Local data still works — chat and sync will resume when you're back online.")
                            .font(AppFonts.caption(12))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.coral.opacity(0.95))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Offline. Local data still works. Chat and sync will resume when you reconnect.")
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: networkMonitor?.isConnected ?? true)
    }
}

extension View {
    /// Pin a global "you're offline" banner to the top of this view. Apply on
    /// the root of any scene that needs ambient connectivity feedback —
    /// ContentView for the main app, plus any fullScreenCover or sheet that
    /// hosts a network-dependent flow (chat, sign-in, etc.).
    func offlineBanner() -> some View {
        modifier(OfflineBannerModifier())
    }
}
