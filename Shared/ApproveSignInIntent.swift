import Foundation
import AppIntents
#if canImport(ActivityKit)
import ActivityKit
#endif

/// The Approve button in the Dynamic Island. Live Activities only take Button and Toggle controls
/// (no drag gestures), so the profile slide itself happens in Ouija's full sheet; this button is the
/// one-tap approval, and it brings Ouija forward so the signed answer can go back to the app.
struct ApproveSignInIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Approve sign-in"
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Request")
    var requestID: String

    init() {}
    init(requestID: String) { self.requestID = requestID }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(requestID, forKey: "ouija.approvedFromIsland")
        #if canImport(ActivityKit)
        for activity in Activity<OuijaSignInAttributes>.activities where activity.attributes.requestID == requestID {
            await activity.update(ActivityContent(state: .init(status: "approved"), staleDate: nil))
        }
        #endif
        return .result()
    }
}
