import SwiftUI
import Combine
import CryptoKit
import UIKit
import Security
#if canImport(ActivityKit)
import ActivityKit
#endif
import DisciplineCore

enum OuijaTab: Hashable { case board, rings, keys }

enum OuijaSessionKind: String, Codable, CaseIterable, Identifiable {
    case userProfile, playgroundID
    var id: String { rawValue }
    var label: String { self == .userProfile ? OuijaContent.shared.sessionUser : OuijaContent.shared.sessionAlt }
}

/// A computer's public key that this phone trusts for the magic-ring sign-in (a "key sign").
struct EnrolledKey: Codable, Identifiable, Hashable {
    var id: String { keyText }
    var name: String
    var keyText: String
    var added: Date
    var bytes: [UInt8] { RingLogin.parseKey(keyText) ?? [] }
    var fingerprint: String { RingLogin.fingerprint(bytes) }
}

struct Approval: Codable, Identifiable, Hashable {
    var id: String { client + "|" + String(at.timeIntervalSince1970) }
    var client: String
    var at: Date
    var how: String   // "slide" or "island"
}

/// Everything Ouija keeps (one JSON file in Application Support; the device key is in the Keychain).
struct OuijaSettings: Codable {
    var attentionAccepted = false
    var agreedAt: Date?
    var ouijaSession: OuijaSessionKind = .userProfile
    var profileName = ""
    var enrolled: [EnrolledKey] = []
    var approvals: [Approval] = []

    /// The board's settings sheet sets this to false to show the Attention page again.
    var ouijaAgreed: Bool {
        get { agreedAt != nil }
        set { if !newValue { agreedAt = nil; attentionAccepted = false } }
    }

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        attentionAccepted = (try? c.decodeIfPresent(Bool.self, forKey: .attentionAccepted)) ?? false
        agreedAt = try? c.decodeIfPresent(Date.self, forKey: .agreedAt)
        ouijaSession = (try? c.decodeIfPresent(OuijaSessionKind.self, forKey: .ouijaSession)) ?? .userProfile
        profileName = (try? c.decodeIfPresent(String.self, forKey: .profileName)) ?? ""
        enrolled = (try? c.decodeIfPresent([EnrolledKey].self, forKey: .enrolled)) ?? []
        approvals = (try? c.decodeIfPresent([Approval].self, forKey: .approvals)) ?? []
    }
}

/// An incoming "Sign in with Ouija" request (ouija://authorize?client=…&nonce=…&callback=…).
struct AuthRequest: Identifiable, Equatable {
    let id: String
    let request: OuijaAssertion.Request
    var client: String { request.client }
}

struct ImportedIPA { let displayName: String; let version: String }

enum OuijaTest {
    static let args = ProcessInfo.processInfo.arguments
    static var active: Bool { args.contains("-uiTesting") }
    static func value(_ flag: String) -> String? {
        guard active, let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static func has(_ flag: String) -> Bool { active && args.contains(flag) }
}

@MainActor
final class OuijaModel: ObservableObject {
    @Published var settings: OuijaSettings { didSet { save() } }
    @Published var tab: OuijaTab = .board
    @Published var pendingRequest: AuthRequest?
    var testURL: URL?
    @Published var ouijaStatus = ""
    @Published var profileImage: UIImage?
    @Published var lastCallbackResult = ""
    @Published var library: [ImportedIPA] = []

    private let dir: URL
    private var stateURL: URL { dir.appendingPathComponent("ouija-state.json") }
    private var photoURL: URL { dir.appendingPathComponent("profile.jpg") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent(OuijaTest.active ? "ouija-uitest" : "ouija", isDirectory: true)
        if OuijaTest.has("-uiTestingResetState") { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: dir.appendingPathComponent("ouija-state.json")),
           let s = try? JSONDecoder().decode(OuijaSettings.self, from: d) {
            settings = s
        } else {
            settings = OuijaSettings()
        }
        profileImage = (try? Data(contentsOf: dir.appendingPathComponent("profile.jpg"))).flatMap(UIImage.init(data:))
        if OuijaTest.has("-uiTestingAgreed") {
            settings.attentionAccepted = true
            if settings.agreedAt == nil { settings.agreedAt = Date() }
        }
        if let name = OuijaTest.value("-uiTestingProfileName") { settings.profileName = name }
        if let tab = OuijaTest.value("-uiTestingTab") {
            self.tab = tab == "rings" ? .rings : (tab == "keys" ? .keys : .board)
        }
        // Handled once the window is up (OuijaApp's .task); a sheet asked for before that never shows.
        if let link = OuijaTest.value("-uiTestingOpenURL") { testURL = URL(string: link) }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(settings) { try? d.write(to: stateURL, options: .atomic) }
    }

    // MARK: Profile

    var displayName: String {
        let n = settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "NCOM Developer" : n
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return s.isEmpty ? "?" : s
    }

    func setProfilePhoto(_ data: Data?) {
        guard let data, let img = UIImage(data: data) else {
            profileImage = nil; try? FileManager.default.removeItem(at: photoURL); return
        }
        let side: CGFloat = 512
        let scaled = img.squareThumbnail(side: side)
        profileImage = scaled
        try? scaled.jpegData(compressionQuality: 0.85)?.write(to: photoURL, options: .atomic)
    }

    // MARK: Attention + Agreement

    func acceptAttention() { settings.attentionAccepted = true }

    func agree() {
        settings.agreedAt = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Device key (signs "Sign in with Ouija" answers)

    private static let keyService = "com.ncom.ouija.identity"

    lazy var deviceKey: Curve25519.Signing.PrivateKey = {
        if let raw = Keychain.read(service: Self.keyService), let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) { return k }
        let k = Curve25519.Signing.PrivateKey()
        Keychain.write(k.rawRepresentation, service: Self.keyService)
        return k
    }()

    var devicePublicKeyText: String { OuijaAssertion.b64url(deviceKey.publicKey.rawRepresentation) }
    var deviceFingerprint: String { RingLogin.fingerprint([UInt8](deviceKey.publicKey.rawRepresentation)) }

    // MARK: Sign in with Ouija

    func handle(_ url: URL) {
        guard url.scheme == "ouija" else { return }
        switch url.host ?? "" {
        case "authorize":
            guard let r = OuijaAssertion.parseRequest(url) else {
                ouijaStatus = "That sign-in link isn't valid, so nothing was sent."
                return
            }
            let req = AuthRequest(id: UUID().uuidString, request: r)
            pendingRequest = req
            startLiveActivity(for: req)
        case "review":
            break   // tapping the Live Activity opens Ouija; the pending sheet is already up
        default:
            break
        }
    }

    /// Called when the app comes forward: an Approve tap in the Dynamic Island finishes here.
    func checkIslandApproval() {
        guard let req = pendingRequest,
              UserDefaults.standard.string(forKey: "ouija.approvedFromIsland") == req.id else { return }
        UserDefaults.standard.removeObject(forKey: "ouija.approvedFromIsland")
        approve(req, how: "island")
    }

    func approve(_ req: AuthRequest, how: String) {
        let a = OuijaAssertion(client: req.client, nonce: req.request.nonce, name: displayName,
                               iat: Int(Date().timeIntervalSince1970), pk: devicePublicKeyText)
        guard let text = try? OuijaAssertion.sign(a, with: deviceKey) else {
            lastCallbackResult = "Couldn't sign the answer."
            return
        }
        settings.approvals.insert(Approval(client: req.client, at: Date(), how: how), at: 0)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        endLiveActivity(for: req, status: "approved")
        let url = OuijaAssertion.callbackURL(req.request.callback, assertion: text)
        pendingRequest = nil
        UIApplication.shared.open(url) { [weak self] ok in
            Task { @MainActor in
                self?.lastCallbackResult = ok ? "Signed answer sent to \(req.client)." : "\(req.client) isn't installed, so the answer had nowhere to go."
            }
        }
    }

    func decline(_ req: AuthRequest) {
        endLiveActivity(for: req, status: "declined")
        pendingRequest = nil
        lastCallbackResult = "Declined \(req.client)."
    }

    // MARK: Live Activity

    @Published var liveActivityState = "none"

    func startLiveActivity(for req: AuthRequest) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveActivityState = "Live Activities are turned off for Ouija."
            return
        }
        let thumb = profileImage.flatMap { $0.squareThumbnail(side: 40).jpegData(compressionQuality: 0.5) }
        let attrs = OuijaSignInAttributes(client: req.client, accountName: displayName, initials: initials,
                                          avatarJPEG: (thumb?.count ?? 0) < 1600 ? thumb : nil, requestID: req.id)
        do {
            _ = try Activity.request(attributes: attrs, content: ActivityContent(state: .init(status: "waiting"), staleDate: Date().addingTimeInterval(300)))
            liveActivityState = "started"
        } catch {
            liveActivityState = "Couldn't start: \(error.localizedDescription)"
        }
        #endif
    }

    func endLiveActivity(for req: AuthRequest, status: String) {
        #if canImport(ActivityKit)
        for a in Activity<OuijaSignInAttributes>.activities where a.attributes.requestID == req.id {
            Task { await a.end(ActivityContent(state: .init(status: status), staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(4))) }
        }
        #endif
    }

    // MARK: Keys

    @discardableResult
    func enroll(name: String, keyText: String) -> String? {
        guard RingLogin.parseKey(keyText) != nil else { return "That isn't an NCOMKEY1 key." }
        let t = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.enrolled.contains(where: { $0.keyText == t }) { return "That key is already enrolled." }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.enrolled.append(EnrolledKey(name: n.isEmpty ? "Computer" : n, keyText: t, added: Date()))
        return nil
    }

    func importIPA(from url: URL, origin: String) -> ImportedIPA? {
        let item = ImportedIPA(displayName: url.deletingPathExtension().lastPathComponent, version: "")
        library.append(item)
        return item
    }
}

enum Keychain {
    static func read(service: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    static func write(_ data: Data, service: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

extension UIImage {
    func squareThumbnail(side: CGFloat) -> UIImage {
        let s = min(size.width, size.height)
        let crop = CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let scale = side / s
            draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale, width: size.width * scale, height: size.height * scale))
        }
    }
}
