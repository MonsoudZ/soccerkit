import Foundation

/// Supplies Info.plist values.
///
/// `Bundle` conforms, so the app reads its own Info.plist. The seam exists for
/// the tests: `BackendConfig`'s rules used to be reachable only through
/// `Bundle.main`, which made them assertions about *how the running bundle was
/// built* rather than about the code. A developer who followed the README and
/// created `Config/Local.xcconfig` turned the suite red, while CI — which has no
/// such file — stayed green. Injecting the dictionary lets the rules be tested
/// for what they are.
protocol InfoDictionary {
    func infoValue(forKey key: String) -> Any?
}

extension Bundle: InfoDictionary {
    func infoValue(forKey key: String) -> Any? { object(forInfoDictionaryKey: key) }
}

/// Where the Go backend lives and how the app is entitled to it.
///
/// The base URL is read from the `BackendBaseURL` Info.plist key (set it per
/// build config, e.g. `http://localhost:8080` for local dev). When it's absent —
/// or empty, or only whitespace, which is what an unset `$(BACKEND_BASE_URL)`
/// expands to — the app has no backend configured and stays entirely on CloudKit
/// + local, so this whole layer is inert until you point it at a server.
enum BackendConfig {
    static let baseURLKey = "BackendBaseURL"

    /// Resolves the backend from a given info dictionary.
    static func baseURL(in info: InfoDictionary) -> URL? {
        guard let raw = info.infoValue(forKey: baseURLKey) as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }

    static func isConfigured(in info: InfoDictionary) -> Bool { baseURL(in: info) != nil }

    /// The running app's backend.
    static var baseURL: URL? { baseURL(in: Bundle.main) }

    static var isConfigured: Bool { baseURL != nil }
}

/// Stores the backend session tokens the app got from `/v1/auth/apple`: the
/// short-lived access JWT sent as the bearer on every call, and the long-lived
/// refresh token used to mint a new access token when it expires (so the coach
/// isn't forced to sign in with Apple again every time the JWT lapses).
///
/// Persisted in the Keychain (via `TokenStorage`) — these are bearer credentials,
/// not preferences.
final class TokenStore {
    private let storage: TokenStorage
    private let accessKey = "backendAuthToken"
    private let refreshKey = "backendRefreshToken"

    init(storage: TokenStorage = KeychainTokenStorage()) { self.storage = storage }

    var token: String? {
        get { storage.string(forKey: accessKey) }
        set { storage.set(newValue, forKey: accessKey) }
    }

    var refreshToken: String? {
        get { storage.string(forKey: refreshKey) }
        set { storage.set(newValue, forKey: refreshKey) }
    }

    /// Stores a freshly-issued session, reporting whether it is actually saved.
    ///
    /// Use this rather than assigning the two properties whenever the session
    /// has to survive: a silently-dropped write reads back as a missing token,
    /// and the coach then sees "Sign in again to sync" forever — signing in
    /// again can't help, because signing in is the step that isn't sticking.
    /// Both keys are written even if the first fails, so a partial save doesn't
    /// leave a stale refresh token paired with a new access token.
    @discardableResult
    func save(token newToken: String?, refreshToken newRefresh: String?) -> Bool {
        let storedToken = storage.set(newToken, forKey: accessKey)
        let storedRefresh = storage.set(newRefresh, forKey: refreshKey)
        return storedToken && storedRefresh
    }

    /// Drops both tokens — the session is over (sign-out, or a refresh that the
    /// server rejected, so there's nothing left to retry with).
    func clear() {
        save(token: nil, refreshToken: nil)
    }
}

enum APIError: Error {
    case notConfigured                 // no BackendBaseURL
    case unauthorized                  // 401 — token missing/expired
    case http(status: Int, body: Data) // non-2xx
    case transport(Error)              // URLSession failure
    case decoding(Error)               // bad response body

    /// A short, coach-facing message for the sync status line.
    var userMessage: String {
        switch self {
        case .notConfigured: return "No backend configured"
        case .unauthorized: return "Sign in again to sync"
        case .http(let status, _): return "Server error (\(status))"
        case .transport: return "Network unavailable"
        case .decoding: return "Unexpected server response"
        }
    }
}

// MARK: - Auth DTOs

/// `POST /v1/auth/apple` — the client hands the Apple identity token to the
/// backend, which verifies it, upserts the user account, and returns a session.
struct AppleAuthRequest: Codable {
    var identityToken: String
    var authorizationCode: String?
    var fullName: String?
}

struct AuthResponse: Codable {
    var token: String
    /// The long-lived refresh token, used to rotate an expired access token
    /// without a fresh Sign in with Apple. The server started returning this; the
    /// client persists it (older builds silently dropped it).
    var refreshToken: String?
    /// The Person the account maps to, if the server has linked one.
    var personID: String?
}

/// `POST /v1/auth/refresh` — trade a valid refresh token for a new access token.
/// The endpoint rotates: it revokes the presented refresh token and returns a
/// fresh one, so the client must store the new `refreshToken` from the response.
struct RefreshRequest: Codable {
    var refreshToken: String
}

struct RefreshResponse: Codable {
    var accessToken: String
    var refreshToken: String
}

// MARK: - Client

/// Thin async HTTP client for the Go backend. Injectable `URLSession` so it can
/// be exercised with a stubbed protocol in tests. Adds the bearer token from
/// `tokenProvider` to every authenticated call.
struct APIClient {
    let baseURL: URL
    let session: URLSession
    /// Supplies the current bearer token (nil before sign-in).
    let tokenProvider: () -> String?

    private var jsonEncoder: JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e
    }

    /// Builds a client for the configured backend, or `nil` when there isn't one.
    /// `info` defaults to the app's own bundle; tests pass a stub dictionary.
    init?(info: InfoDictionary = Bundle.main, session: URLSession = .shared,
          tokenProvider: @escaping () -> String?) {
        guard let baseURL = BackendConfig.baseURL(in: info) else { return nil }
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // Explicit base URL — used by tests.
    init(baseURL: URL, session: URLSession = .shared, tokenProvider: @escaping () -> String?) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func authenticateApple(_ body: AppleAuthRequest) async throws -> AuthResponse {
        try await send(path: "/v1/auth/apple", method: "POST", body: body, authenticated: false)
    }

    /// Rotates the session: the refresh token is passed in the body (not the
    /// bearer header), so this call is unauthenticated by the access token.
    func refresh(_ refreshToken: String) async throws -> RefreshResponse {
        try await send(path: "/v1/auth/refresh", method: "POST",
                       body: RefreshRequest(refreshToken: refreshToken), authenticated: false)
    }

    func pull(since cursor: String?) async throws -> SyncPullResponse {
        let query = cursor.map { "?since=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0)" } ?? ""
        return try await send(path: "/v1/sync" + query, method: "GET", body: Optional<Int>.none)
    }

    func push(_ body: SyncPushRequest) async throws -> SyncPushResponse {
        try await send(path: "/v1/sync", method: "POST", body: body)
    }

    /// Permanently deletes the authenticated account and all its data server-side
    /// (`DELETE /v1/me`). Authenticated; the server identifies the account from
    /// the bearer token.
    func deleteAccount() async throws {
        try await sendNoContent(path: "/v1/me", method: "DELETE")
    }

    // MARK: - Core

    private func send<Body: Encodable, Response: Decodable>(
        path: String, method: String, body: Body?, authenticated: Bool = true
    ) async throws -> Response {
        // Build the URL by string join so an embedded query (?since=) survives.
        guard let url = URL(string: baseURL.absoluteString.trimmingTrailingSlash() + path) else {
            throw APIError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated, let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try jsonEncoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw status == 401 ? APIError.unauthorized : APIError.http(status: status, body: data)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// A request with no response body to decode (e.g. a `204` from a delete).
    /// Authenticated by default; throws on any non-2xx.
    private func sendNoContent(path: String, method: String, authenticated: Bool = true) async throws {
        guard let url = URL(string: baseURL.absoluteString.trimmingTrailingSlash() + path) else {
            throw APIError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated, let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw status == 401 ? APIError.unauthorized : APIError.http(status: status, body: data)
        }
    }
}

private extension String {
    func trimmingTrailingSlash() -> String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}

extension CharacterSet {
    /// Query-value-safe set (no `&`, `=`, `?`, `+`, `/`).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=?+/")
        return set
    }()
}
