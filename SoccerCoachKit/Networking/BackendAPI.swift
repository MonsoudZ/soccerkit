import Foundation

/// Where the Go backend lives and how the app is entitled to it.
///
/// The base URL is read from the `BackendBaseURL` Info.plist key (set it per
/// build config, e.g. `http://localhost:8080` for local dev). When it's absent
/// the app has no backend configured and stays entirely on CloudKit + local —
/// so this whole layer is inert until you point it at a server.
enum BackendConfig {
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }

    static var isConfigured: Bool { baseURL != nil }
}

/// Stores the backend session token (JWT) the app got from `/v1/auth/apple`.
///
/// Backed by `UserDefaults` to match the rest of the app's storage; a bearer
/// token really belongs in the Keychain, so swap this implementation before
/// shipping (the interface stays the same).
final class TokenStore {
    private let defaults: UserDefaults
    private let key = "backendAuthToken"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var token: String? {
        get { defaults.string(forKey: key) }
        set {
            if let newValue { defaults.set(newValue, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
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
    /// The Person the account maps to, if the server has linked one.
    var personID: String?
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

    init?(session: URLSession = .shared, tokenProvider: @escaping () -> String?) {
        guard let baseURL = BackendConfig.baseURL else { return nil }
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

    func pull(since cursor: String?) async throws -> SyncPullResponse {
        let query = cursor.map { "?since=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0)" } ?? ""
        return try await send(path: "/v1/sync" + query, method: "GET", body: Optional<Int>.none)
    }

    func push(_ body: SyncPushRequest) async throws -> SyncPushResponse {
        try await send(path: "/v1/sync", method: "POST", body: body)
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
