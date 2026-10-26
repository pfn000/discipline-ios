import Foundation
import DisciplineCore

/// Public GitHub REST API client for "GitHub to iOS".
struct GitHubService {
    let session: URLSession

    static func make() -> GitHubService {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        if TestHooks.mockGitHub { config.protocolClasses = [MockGitHubProtocol.self] }
        return GitHubService(session: URLSession(configuration: config))
    }

    enum ServiceError: LocalizedError {
        case http(Int, String)
        case rateLimited(Date?)
        var errorDescription: String? {
            switch self {
            case .http(let code, let msg): return "GitHub answered \(code): \(msg)"
            case .rateLimited(let reset):
                if let reset { return "GitHub's hourly limit is used up. It resets at \(reset.formatted(date: .omitted, time: .shortened)). Add a token in More → Settings to raise it." }
                return "GitHub's hourly limit is used up. Add a token in More → Settings to raise it."
            }
        }
    }

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("Discipline-iOS", forHTTPHeaderField: "User-Agent")
        if let token = Keychain.load(), !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return r
    }

    func releases(_ ref: GitHubRepoRef) async throws -> [GitHubRelease] {
        let (data, resp) = try await session.data(for: request(ref.releasesAPI))
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
            let rl = RateLimit(headers: headers)
            if (http.statusCode == 403 || http.statusCode == 429), rl.remaining == 0 { throw ServiceError.rateLimited(rl.reset) }
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? ""
            throw ServiceError.http(http.statusCode, msg.isEmpty ? "no message" : msg)
        }
        var list = try GitHubRelease.decodeList(data)
        if let tag = ref.tag { list = list.filter { $0.tagName == tag } }
        return list
    }

    /// Downloads an asset to a temporary file and returns its URL.
    func download(_ asset: GitHubRelease.Asset) async throws -> URL {
        guard let url = URL(string: asset.browserDownloadURL) else { throw URLError(.badURL) }
        var r = URLRequest(url: url)
        r.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (tmp, resp) = try await session.download(for: r)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw ServiceError.http(http.statusCode, "download failed") }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + asset.name)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}

/// Test-only: answers GitHub API calls with the bundled releases.json and any .ipa download with
/// the bundled Sample.ipa. Installed only when the app is launched with -uiTestingMockGitHub.
final class MockGitHubProtocol: URLProtocol {
    nonisolated(unsafe) static var calls: [String: Int] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host == "api.github.com" || host == "github.com" || host.hasSuffix("githubusercontent.com")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        var status = 200
        var body = Data()
        var type = "application/json"
        if url.host == "api.github.com" {
            if url.path.contains("/repos/ratelimited/") {
                status = 403
                body = Data(#"{"message":"API rate limit exceeded"}"#.utf8)
            } else if url.path.contains("/repos/missing/") {
                status = 404
                body = Data(#"{"message":"Not Found"}"#.utf8)
            } else if url.path.contains("/repos/pfn000/discipline-ios/") {
                // Discipline's own releases: a newer 0.3.1 with release notes (self-update).
                if let f = Bundle.main.url(forResource: "self-releases", withExtension: "json"), let d = try? Data(contentsOf: f) { body = d }
            } else {
                // First call for a repo answers releases.json; later calls answer releases-next.json,
                // which adds a newer stable release, so the update badge can be tested.
                let key = url.path
                let n = MockGitHubProtocol.calls[key, default: 0]
                MockGitHubProtocol.calls[key] = n + 1
                let name = n == 0 ? "releases" : "releases-next"
                if let f = Bundle.main.url(forResource: name, withExtension: "json"), let d = try? Data(contentsOf: f) { body = d }
            }
        } else if url.path.lowercased().hasSuffix(".ipa"), let f = TestHooks.sampleIPAURL, let d = try? Data(contentsOf: f) {
            body = d; type = "application/octet-stream"
        } else {
            status = 404
        }
        var headers = ["Content-Type": type, "Content-Length": "\(body.count)"]
        if status == 403 { headers["X-RateLimit-Remaining"] = "0"; headers["X-RateLimit-Reset"] = "\(Int(Date().timeIntervalSince1970) + 1800)" }
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
