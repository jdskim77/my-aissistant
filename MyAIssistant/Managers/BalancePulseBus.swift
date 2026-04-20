import Foundation
import Observation

/// Shared in-memory channel that broadcasts task-completion pulses to any
/// UI that wants to react. Home's Balance Pulse card is the primary
/// consumer — animating the matching dimension bar and flashing a
/// "+N <dim>" label when a pulse arrives.
///
/// Decoupling the publisher (TaskManager) from the subscriber (Home view)
/// means every completion path — Home list, Focus timer auto-complete,
/// Schedule row swipe, Watch sync, recurring auto-generation — contributes
/// to the same visible feedback loop. If the user isn't looking at Home
/// when a pulse is published, the stale-window check in `BalancePulse`
/// prevents the pulse from replaying on return.
@Observable @MainActor
final class BalancePulseBus {
    private(set) var latest: BalancePulse?

    func publish(_ pulse: BalancePulse) {
        latest = pulse
    }
}
