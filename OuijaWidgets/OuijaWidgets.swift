import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

@main
struct OuijaWidgetsBundle: WidgetBundle {
    var body: some Widget { OuijaSignInLiveActivity() }
}

/// "Discipline wants to sign in to your account", with the profile picture and account name.
/// Live Activities only allow Button and Toggle (App Intents) as controls, so there's no drag here:
/// Approve is one tap, and tapping anywhere else opens Ouija's full sheet where the profile slide happens.
struct OuijaSignInLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OuijaSignInAttributes.self) { context in
            LockScreenSignIn(context: context)
                .padding(16)
                .activityBackgroundTint(Color(red: 0.07, green: 0.06, blue: 0.14).opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "ouija://review?id=\(context.attributes.requestID)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandAvatar(attributes: context.attributes, size: 44).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.purple)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("\(context.attributes.client) wants to sign in").font(.headline).lineLimit(1)
                        Text(context.attributes.accountName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.status == "waiting" {
                        HStack(spacing: 10) {
                            Link(destination: URL(string: "ouija://review?id=\(context.attributes.requestID)")!) {
                                Text("Slide in Ouija").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            Button(intent: ApproveSignInIntent(requestID: context.attributes.requestID)) {
                                Text("Approve").bold().frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                    } else {
                        Text(context.state.status == "approved" ? "Approved" : "Declined").font(.headline)
                    }
                }
            } compactLeading: {
                IslandAvatar(attributes: context.attributes, size: 22)
            } compactTrailing: {
                Text(context.attributes.client).font(.caption2.weight(.semibold)).lineLimit(1).frame(maxWidth: 64)
            } minimal: {
                IslandAvatar(attributes: context.attributes, size: 22)
            }
            .widgetURL(URL(string: "ouija://review?id=\(context.attributes.requestID)"))
            .keylineTint(.purple)
        }
    }
}

struct IslandAvatar: View {
    let attributes: OuijaSignInAttributes
    let size: CGFloat
    var body: some View {
        Group {
            if let d = attributes.avatarJPEG, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.purple)
                    Text(attributes.initials).font(.system(size: size * 0.4, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct LockScreenSignIn: View {
    let context: ActivityViewContext<OuijaSignInAttributes>
    var body: some View {
        HStack(spacing: 14) {
            IslandAvatar(attributes: context.attributes, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(context.attributes.client) wants to sign in to your account").font(.headline).foregroundStyle(.white)
                Text(context.attributes.accountName).font(.subheadline).foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 6)
            if context.state.status == "waiting" {
                Button(intent: ApproveSignInIntent(requestID: context.attributes.requestID)) { Text("Approve").bold() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            } else {
                Image(systemName: context.state.status == "approved" ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title).foregroundStyle(context.state.status == "approved" ? Color.green : Color.red)
            }
        }
    }
}
