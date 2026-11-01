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
    /// Only used when the Keychain refuses to keep the account (the Keys tab says so).
    var accountFallback: Data?
    /// Set after a Magic ID card tap the NCOM verifier granted.
    var developer: DeveloperSession?
    /// The NCOM verifier for Magic ID card sign-in (empty = not set up; nothing is assumed).
    var verifierURL = ""
    /// NCOM Dev's and GlassVault's public keys (P-256, base64url) for checking the two halves of the magic QR.
    var ncomDevKey = ""
    var glassVaultKey = ""
    /// What this iPhone wrote onto the card last (step 4 of the handshake).
    var cardRecord: OuijaKeyRecord?
    /// Every "no" from a card tap, newest first.
    var securityReports: [SecurityReport] = []
    /// The last real device scan (Bluetooth LE / local network). Empty until a scan ran.
    var lastScan: [DiscoveredDevice] = []
    var lastScanAt: Date?

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
        accountFallback = try? c.decodeIfPresent(Data.self, forKey: .accountFallback)
        developer = try? c.decodeIfPresent(DeveloperSession.self, forKey: .developer)
        verifierURL = (try? c.decodeIfPresent(String.self, forKey: .verifierURL)) ?? ""
        lastScan = (try? c.decodeIfPresent([DiscoveredDevice].self, forKey: .lastScan)) ?? []
        lastScanAt = try? c.decodeIfPresent(Date.self, forKey: .lastScanAt)
        ncomDevKey = (try? c.decodeIfPresent(String.self, forKey: .ncomDevKey)) ?? ""
        glassVaultKey = (try? c.decodeIfPresent(String.self, forKey: .glassVaultKey)) ?? ""
        cardRecord = try? c.decodeIfPresent(OuijaKeyRecord.self, forKey: .cardRecord)
        securityReports = (try? c.decodeIfPresent([SecurityReport].self, forKey: .securityReports)) ?? []
    }
}

struct DeveloperSession: Codable, Equatable {
    var cardID: String
    var ownerName: String
    var grantedAt: Date
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
    @Published var urlTrace = "no link yet"   // UI tests read it when a sheet doesn't show
    @Published var ouijaStatus = ""
    @Published var profileImage: UIImage?
    @Published var lastCallbackResult = ""
    @Published var library: [ImportedIPA] = []
    /// The signed-in person. nil = nobody yet: Ouija shows the account page, never a stand-in name.
    @Published private(set) var account: OuijaAccount?
    /// Where the account is kept, in words for the Keys tab ("Keychain on this iPhone" or why not).
    @Published private(set) var accountStore = ""
    /// The phone Ouija runs on, as the system reports it.
    let thisDevice = OuijaModel.readDeviceIdentity()

    private let dir: URL
    private var stateURL: URL { dir.appendingPathComponent("ouija-state.json") }
    private var photoURL: URL { dir.appendingPathComponent("profile.jpg") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent(OuijaTest.active ? "ouija-uitest" : "ouija", isDirectory: true)
        if OuijaTest.has("-uiTestingResetState") {
            try? FileManager.default.removeItem(at: dir)
            AccountStore.delete()   // test-mode service only (AccountStore.service)
            Keychain.delete(service: Self.magicKeyService)
        }
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
        // The account: Keychain first, then the fallback file, then an older install's typed Keys-tab name.
        if let a = AccountStore.load() {
            account = a; accountStore = "Keychain on this iPhone"
        } else if let a = OuijaAccount.decode(settings.accountFallback) {
            account = a; accountStore = "Ouija's own file on this iPhone (the Keychain refused it)"
        } else if case .success(let n) = OuijaAccount.validName(settings.profileName) {
            _ = createAccount(name: n)
        }
        // Test-only: some tests start already signed in. The sign-in test itself types the name.
        if let name = OuijaTest.value("-uiTestingProfileName") { _ = createAccount(name: name) }
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

    /// The account's name, or "" when nobody has signed in (no made-up name, ever).
    var displayName: String { account?.name ?? "" }

    var initials: String {
        let s = OuijaAccount.initials(of: displayName)
        return s.isEmpty ? "?" : s
    }

    /// Creates (or replaces) the account from a typed name. Returns the problem in words, or nil when saved.
    @discardableResult
    func createAccount(name: String, kind: OuijaAccount.Kind = .local) -> String? {
        switch OuijaAccount.validName(name) {
        case .failure(.empty): return "Type your name to continue."
        case .failure(.tooLong): return "That name is longer than \(OuijaAccount.maxNameLength) characters."
        case .success(let n):
            var a = account ?? OuijaAccount(name: n, kind: kind)
            a.name = n; a.kind = kind
            store(a)
            return nil
        }
    }

    private func store(_ a: OuijaAccount) {
        let status = AccountStore.save(a)
        if status == errSecSuccess {
            settings.accountFallback = nil
            accountStore = "Keychain on this iPhone"
        } else {
            settings.accountFallback = a.encoded()
            accountStore = "Ouija's own file on this iPhone (the Keychain said \(status))"
        }
        settings.profileName = a.name
        account = a
    }

    /// Signs out: removes the account from this iPhone (Keychain and file). The agreement must be accepted again.
    func signOut() {
        AccountStore.delete()
        settings.accountFallback = nil
        settings.profileName = ""
        settings.developer = nil
        settings.agreedAt = nil
        account = nil
        accountStore = ""
    }

    /// A Magic ID card tap the verifier granted: the account becomes the name NCOM's verifier holds for the card.
    func grantDeveloper(ownerName: String, cardID: String) {
        _ = createAccount(name: ownerName, kind: .developerCard)
        settings.developer = DeveloperSession(cardID: cardID, ownerName: ownerName, grantedAt: Date())
    }

    static func readDeviceIdentity() -> DeviceIdentity {
        var u = utsname(); uname(&u)
        let machine = withUnsafeBytes(of: &u.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let d = UIDevice.current
        return DeviceIdentity(name: d.name, model: d.model, systemName: d.systemName, systemVersion: d.systemVersion,
                              utsMachine: machine, environment: ProcessInfo.processInfo.environment)
    }

    func recordScan(_ found: [DiscoveredDevice]) {
        settings.lastScan = DiscoveredDevice.sorted(found)
        settings.lastScanAt = Date()
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
        urlTrace = "link \(url.host ?? "-") agreed=\(settings.agreedAt != nil)"
        guard url.scheme == "ouija" else { return }
        switch url.host ?? "" {
        case "authorize":
            guard let r = OuijaAssertion.parseRequest(url) else {
                ouijaStatus = "That sign-in link isn't valid, so nothing was sent."
                return
            }
            let req = AuthRequest(id: UUID().uuidString, request: r)
            pendingRequest = req
            urlTrace += " request from \(r.client)"
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
        guard account != nil else {
            lastCallbackResult = "Sign in to Ouija first; nothing was sent."
            return
        }
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
        let content = ActivityContent(state: OuijaSignInAttributes.ContentState(status: "waiting"), staleDate: Date().addingTimeInterval(300))
        do {
            let a = try Activity.request(attributes: attrs, content: content)
            liveActivityState = "started id=\(a.id) state=\(a.activityState) count=\(Activity<OuijaSignInAttributes>.activities.count) frequentUpdates=\(ActivityAuthorizationInfo().frequentPushesEnabled)"
        } catch {
            // The request can be refused while the scene is still coming forward; try once more a moment later.
            liveActivityState = "Couldn't start: \(error) (\(error.localizedDescription)); retrying"
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self else { return }
                do {
                    let a = try Activity.request(attributes: attrs, content: content)
                    self.liveActivityState = "started on retry id=\(a.id) state=\(a.activityState) count=\(Activity<OuijaSignInAttributes>.activities.count)"
                } catch {
                    self.liveActivityState = "Couldn't start (twice): \(error) (\(error.localizedDescription))"
                }
            }
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

/// The account lives in the Keychain (kept across app reinstalls on the same iPhone, never synced).
enum AccountStore {
    static var service: String { OuijaTest.active ? "com.ncom.ouija.account.uitest" : "com.ncom.ouija.account" }
    static func load() -> OuijaAccount? { OuijaAccount.decode(Keychain.read(service: service)) }
    @discardableResult static func save(_ a: OuijaAccount) -> OSStatus { Keychain.writeStatus(a.encoded(), service: service) }
    static func delete() { Keychain.delete(service: service) }
}

enum Keychain {
    static func delete(service: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
    }
    static func read(service: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    static func write(_ data: Data, service: String) { _ = writeStatus(data, service: service) }

    @discardableResult
    static func writeStatus(_ data: Data, service: String) -> OSStatus {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil)
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
