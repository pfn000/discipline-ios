import SwiftUI
import UIKit
import Combine
import DisciplineCore

/// "Sign in with Ouija / NCOM": Discipline asks the Ouija app (a separate app) to approve, and checks the
/// Ed25519-signed answer that comes back on discipline://ouija-callback. Discipline can't pair without Ouija.
@MainActor
final class OuijaLink: ObservableObject {
    static let shared = OuijaLink()
    static let client = "Discipline"
    static let callback = "discipline://ouija-callback"

    @Published var ouijaInstalled = false
    @Published var accountName: String?
    @Published var pinnedKey: String?
    @Published var signedInAt: Date?
    @Published var lastResult = ""

    private let store: UserDefaults
    private var pendingNonce: String? {
        get { store.string(forKey: "pendingNonce") }
        set { store.set(newValue, forKey: "pendingNonce") }
    }

    private init() {
        store = UserDefaults(suiteName: "com.ncom.discipline.ouija-link") ?? .standard
        if ProcessInfo.processInfo.arguments.contains("-uiTestingResetOuijaLink") {
            for k in ["pendingNonce", "accountName", "pinnedKey", "signedInAt"] { store.removeObject(forKey: k) }
        }
        accountName = store.string(forKey: "accountName")
        pinnedKey = store.string(forKey: "pinnedKey")
        signedInAt = store.object(forKey: "signedInAt") as? Date
        refreshInstalled()
    }

    func refreshInstalled() {
        // Needs "ouija" in LSApplicationQueriesSchemes; true only when the Ouija app is installed.
        ouijaInstalled = UIApplication.shared.canOpenURL(URL(string: "ouija://authorize")!)
    }

    func signIn() {
        refreshInstalled()
        guard ouijaInstalled else { lastResult = "Install Ouija to pair."; return }
        let nonce = RingLogin.hex(RingLogin.newSession())
        pendingNonce = nonce
        let url = OuijaAssertion.authorizeURL(client: Self.client, nonce: nonce, callback: Self.callback)
        UIApplication.shared.open(url) { ok in
            Task { @MainActor in if !ok { OuijaLink.shared.lastResult = "Ouija didn't open." } }
        }
        lastResult = "Waiting for Ouija…"
    }

    /// Returns the line Discipline shows.
    @discardableResult
    func receive(_ url: URL) -> (String, Bool) {
        guard let text = DeepLinks.queryValue("assertion", in: url) else { return finish("Ouija's answer was empty.", ok: false) }
        guard let nonce = pendingNonce else { return finish("No sign-in was waiting, so the answer was ignored.", ok: false) }
        switch OuijaAssertion.verify(text, client: Self.client, nonce: nonce, pinnedKey: pinnedKey) {
        case .accepted(let a, let first):
            pendingNonce = nil
            accountName = a.name; pinnedKey = a.pk; signedInAt = Date()
            store.set(a.name, forKey: "accountName"); store.set(a.pk, forKey: "pinnedKey"); store.set(signedInAt, forKey: "signedInAt")
            return finish(first ? "Paired with Ouija. Signed in as \(a.name)." : "Signed in with Ouija as \(a.name).", ok: true)
        case .badSignature: return finish("Ouija's answer has a bad signature. Not signed in.", ok: false)
        case .wrongClient: return finish("That answer was for another app. Not signed in.", ok: false)
        case .wrongNonce: return finish("That answer was for an older request. Not signed in.", ok: false)
        case .expired: return finish("Ouija's answer expired. Try again.", ok: false)
        case .differentKey: return finish("That answer came from a different Ouija than the one paired. Not signed in.", ok: false)
        case .malformed: return finish("Ouija's answer couldn't be read.", ok: false)
        }
    }

    func signOut() {
        accountName = nil; pinnedKey = nil; signedInAt = nil
        for k in ["accountName", "pinnedKey", "signedInAt", "pendingNonce"] { store.removeObject(forKey: k) }
        lastResult = "Signed out. The pairing was forgotten."
    }

    private func finish(_ s: String, ok: Bool) -> (String, Bool) { lastResult = s; return (s, ok) }

    var keyFingerprint: String? {
        guard let pk = pinnedKey, let d = OuijaCode.base64URLDecode(pk) else { return nil }
        return RingLogin.fingerprint([UInt8](d))
    }
}

/// The "Sign in with Ouija / NCOM" card at the top of More.
struct SignInWithOuijaSection: View {
    @ObservedObject var link = OuijaLink.shared

    var body: some View {
        Section {
            if let name = link.accountName {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 30)).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.headline).accessibilityIdentifier("ouijaSignIn.account")
                        Text("Signed in with Ouija · key \(link.keyFingerprint ?? "?")")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button("Sign out", role: .destructive) { link.signOut() }
                    .accessibilityIdentifier("ouijaSignIn.signOut")
            } else if link.ouijaInstalled {
                Button { link.signIn() } label: {
                    Label("Sign in with Ouija / NCOM", systemImage: "person.badge.key.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("ouijaSignIn.button")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Install Ouija to pair", systemImage: "arrow.down.app")
                        .font(.headline)
                        .accessibilityIdentifier("ouijaSignIn.install")
                    Text("Sign in with Ouija / NCOM needs the Ouija app on this iPhone. Discipline can't pair without it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            if !link.lastResult.isEmpty {
                Text(link.lastResult).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("ouijaSignIn.result")
            }
        } header: { Text("Account") }
        .onAppear { link.refreshInstalled() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            link.refreshInstalled()
        }
    }
}

/// Where Discipline's hidden "Ouija Board" row goes now: the board lives in the Ouija app.
struct OuijaHandoffView: View {
    @ObservedObject var link = OuijaLink.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ouija is its own app now").font(.title3.bold()).accessibilityIdentifier("ouija.handoff")
                    Text("The Ouija Board, the Agreement, the magic-ring computer sign-in and your enrolled keys live in the Ouija app. Discipline signs in through it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                if link.ouijaInstalled {
                    Button("Open Ouija") { UIApplication.shared.open(URL(string: "ouija://open")!) }
                        .accessibilityIdentifier("ouija.openApp")
                }
            }
            SignInWithOuijaSection()
            Section("Free Apple account") {
                Text("Discipline + Ouija + SideStore are 3 apps, which is the free account's limit of 3 active sideloaded apps.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ouija")
        .onAppear { link.refreshInstalled() }
    }
}
