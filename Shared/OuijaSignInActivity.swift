import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// The Live Activity Ouija shows while an app (for example Discipline) waits for a sign-in approval.
/// Shared by the Ouija app (starts and ends it) and the OuijaWidgets extension (draws it in the
/// Dynamic Island and on the Lock Screen).
struct OuijaSignInAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "waiting", "approved" or "declined"
        var status: String
    }
    var client: String
    var accountName: String
    var initials: String
    /// A tiny JPEG of the profile photo (ActivityKit caps the whole payload at 4 KB, so it stays under ~1.5 KB).
    var avatarJPEG: Data?
    var requestID: String
}
#endif
