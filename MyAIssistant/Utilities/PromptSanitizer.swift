import Foundation

/// Strips characters that have grammar meaning in the AI action-tag dialect
/// (`[[CREATE_EVENT:Title|start|end|desc]]`, `[[DELETE_EVENT:id]]`,
/// `[[ACTIVITY:cat|desc]]`, `[[SET_ALARM:time|label]]`) from any string that
/// originated as user-controlled input. Calendar event titles, task titles,
/// habit titles, check-in notes, season-goal intentions, and external
/// metadata can all contain these tokens — verbatim, they let an attacker
/// fabricate an action tag that the model echoes and `parseResponseTags`
/// then executes against the user's real data.
///
/// Replacement uses Unicode look-alikes so the user-visible meaning of the
/// string is preserved if it ever surfaces back to the user, while the
/// regex `/\[\[CREATE_EVENT:([^\]]+?)\]\]/` and `|` field separator can no
/// longer match.
extension String {
    /// Returns a copy with `[[`, `]]`, and `|` replaced by safe look-alikes.
    /// Idempotent. Cheap.
    var sanitizedForPrompt: String {
        replacingOccurrences(of: "[[", with: "⟦")
            .replacingOccurrences(of: "]]", with: "⟧")
            .replacingOccurrences(of: "|", with: "∣")
    }
}
