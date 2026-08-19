//  Services/AuthService.swift
//  AirWhisperCompanionApp
//
//  Phase 3  - Static async/throws network layer for all auth endpoints.
//  Phase 5  - Real baseURL, /auth/google endpoint, auto-refresh interceptor.
//  Every method is a fire-and-forget URLSession call; callers must be in
//  an async context (Task or async function).

import Foundation

enum AuthError: LocalizedError {
    case invalidURL
    case network(Error)
    case server(String)
    case unverified(String)
    case decoding(Error)
    case tokenMissing

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "Invalid server URL."
        case .network(let e):    return e.localizedDescription
        case .server(let msg):   return msg
        case .unverified(let m): return m
        case .decoding(let e):   return "Unexpected server response: \(e.localizedDescription)"
        case .tokenMissing:      return "Authentication token missing."
        }
    }
}


struct AuthTokenResponse: Decodable {
    let accessToken:  String
    let refreshToken: String
    let user:         AuthUserPayload
}

struct AuthUserPayload: Decodable {
    let id:    String
    let name:  String
    let email: String
}

struct RefreshTokenResponse: Decodable {
    let accessToken:  String
    let refreshToken: String
}

struct ResetTokenResponse: Decodable {
    let resetToken: String
}

private struct MessageOnlyResponse: Decodable {
    let message: String
}

private struct AuthErrorResponse: Decodable {
    let error: String?
    let unverified: Bool?
}


enum AuthService {

    // ── Base URL ─────────────────────────────────────────────────────────
    private static let baseURL = "https://awtwilio-endpoint.onrender.com"

    // ── Helpers ──────────────────────────────────────────────────────────

    private static func url(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else { throw AuthError.invalidURL }
        return url
    }

    /// Encodes `body` to JSON, sends a POST, and decodes the response as `T`.
    @discardableResult
    private static func post<B: Encodable, R: Decodable>(
        _ path: String,
        body: B,
        responseType: R.Type,
        accessToken: String? = nil,
        isRetry: Bool = false          // prevents infinite retry loop
    ) async throws -> R {
        let url = try url(path)
        var req = URLRequest(url: url)
        req.httpMethod     = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let err as NSError where !isRetry &&
            (err.code == NSURLErrorNetworkConnectionLost ||
            err.code == NSURLErrorTimedOut) {
            // Render free tier drops the connection while waking up  - wait and retry once
            try await Task.sleep(nanoseconds: 3_000_000_000)
            return try await post(path, body: body, responseType: responseType,
                                accessToken: accessToken, isRetry: true)
        } catch {
            throw AuthError.network(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status < 200 || status >= 300 {
            let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
            if status == 403, errorResponse?.unverified == true {
                throw AuthError.unverified(errorResponse?.error ?? "Account unverified.")
            }
            if let msg = errorResponse?.error {
                throw AuthError.server(msg)
            }
            throw AuthError.server("Request failed (HTTP \(status))")
        }

        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            throw AuthError.decoding(error)
        }
    }

    /// Sends a DELETE request with a JSON body and decodes the response as `R`.
    @discardableResult
    private static func deleteWithBody<B: Encodable, R: Decodable>(
        _ path: String,
        body: B,
        responseType: R.Type,
        accessToken: String? = nil,
        isRetry: Bool = false
    ) async throws -> R {
        let url = try url(path)
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let err as NSError where !isRetry &&
            (err.code == NSURLErrorNetworkConnectionLost ||
            err.code == NSURLErrorTimedOut) {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            return try await deleteWithBody(path, body: body, responseType: responseType,
                                            accessToken: accessToken, isRetry: true)
        } catch {
            throw AuthError.network(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status < 200 || status >= 300 {
            if let msg = (try? JSONDecoder().decode(AuthErrorResponse.self, from: data))?.error {
                throw AuthError.server(msg)
            }
            throw AuthError.server("Request failed (HTTP \(status))")
        }

        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            throw AuthError.decoding(error)
        }
    }

    /// Sends a DELETE request and decodes the response as `R`.
    private static func delete<R: Decodable>(
        _ path: String,
        responseType: R.Type,
        accessToken: String? = nil,
        isRetry: Bool = false
    ) async throws -> R {
        let url = try url(path)
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 30
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let err as NSError where !isRetry &&
            (err.code == NSURLErrorNetworkConnectionLost ||
            err.code == NSURLErrorTimedOut) {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            return try await delete(path, responseType: responseType,
                                    accessToken: accessToken, isRetry: true)
        } catch {
            throw AuthError.network(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status < 200 || status >= 300 {
            if let msg = (try? JSONDecoder().decode(AuthErrorResponse.self, from: data))?.error {
                throw AuthError.server(msg)
            }
            throw AuthError.server("Request failed (HTTP \(status))")
        }

        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            throw AuthError.decoding(error)
        }
    }

    private static func shouldRefreshSession(afterServerMessage message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("401")
            || lowered.contains("unauthorized")
            || lowered.contains("expired")
            || lowered.contains("invalid access token")
            || lowered.contains("invalid token")
    }

    /// Auto-refreshing POST for authenticated endpoints.
    /// 1. Reads stored access token and attempts the request.
    /// 2. On HTTP 401: silently refreshes the token pair and retries once.
    /// 3. On second 401: throws AuthError.server("Session expired  - please log in again").
    @discardableResult
    static func authenticatedPost<B: Encodable, R: Decodable>(
        _ path: String,
        body: B,
        responseType: R.Type
    ) async throws -> R {
        guard let accessToken = StorageManager.shared.loadAccessToken() else {
            throw AuthError.tokenMissing
        }

        do {
            return try await post(path, body: body, responseType: responseType, accessToken: accessToken)
        } catch AuthError.server(let msg) where shouldRefreshSession(afterServerMessage: msg) {
            // Fall through to refresh
        } catch {
            throw error
        }

        // Refresh the token pair
        let refreshed = try await refreshAccessToken()

        do {
            return try await post(path, body: body, responseType: responseType, accessToken: refreshed.accessToken)
        } catch AuthError.server {
            throw AuthError.server("Session expired  - please log in again")
        }
    }

    /// Auto-refreshing DELETE for authenticated endpoints.
    @discardableResult
    static func authenticatedDelete<R: Decodable>(
        _ path: String,
        responseType: R.Type
    ) async throws -> R {
        guard let accessToken = StorageManager.shared.loadAccessToken() else {
            throw AuthError.tokenMissing
        }

        do {
            return try await delete(path, responseType: responseType, accessToken: accessToken)
        } catch AuthError.server(let msg) where shouldRefreshSession(afterServerMessage: msg) {
            // Fall through to refresh
        } catch {
            throw error
        }

        let refreshed = try await refreshAccessToken()

        do {
            return try await delete(path, responseType: responseType, accessToken: refreshed.accessToken)
        } catch AuthError.server {
            throw AuthError.server("Session expired  - please log in again")
        }
    }

    // ── Public API ────────────────────────────────────────────────────────

    struct RegisterBody: Encodable {
        let name: String
        let email: String
        let password: String
    }

    /// Creates a new account. Throws on error; success means OTP was sent.
    static func register(name: String, email: String, password: String) async throws {
        try await post(
            "/auth/register",
            body: RegisterBody(name: name, email: email, password: password),
            responseType: MessageOnlyResponse.self
        )
    }

    // ─────────────────────────────────────────────────────────────────────

    struct ResendVerificationBody: Encodable {
        let email: String
    }

    /// Requests a new email-verification OTP.
    static func resendVerification(email: String) async throws {
        try await post(
            "/auth/resend-verification",
            body: ResendVerificationBody(email: email),
            responseType: MessageOnlyResponse.self
        )
    }

    // ─────────────────────────────────────────────────────────────────────

    struct VerifyEmailBody: Encodable {
        let email: String
        let code:  String
    }

    /// Submits email-verification OTP. Returns tokens + user on success.
    static func verifyEmail(email: String, code: String) async throws -> AuthTokenResponse {
        try await post(
            "/auth/verify-email",
            body: VerifyEmailBody(email: email, code: code),
            responseType: AuthTokenResponse.self
        )
    }

    // ─────────────────────────────────────────────────────────────────────

    struct LoginBody: Encodable {
        let email:    String
        let password: String
    }

    /// Authenticates with email + password. Returns tokens + user on success.
    static func login(email: String, password: String) async throws -> AuthTokenResponse {
        try await post(
            "/auth/login",
            body: LoginBody(email: email, password: password),
            responseType: AuthTokenResponse.self
        )
    }

    // ─────────────────────────────────────────────────────────────────────

    struct GoogleSignInBody: Encodable { let idToken: String }

    /// Authenticates with a Google ID token. Returns tokens + user on success.
    static func googleSignIn(idToken: String) async throws -> AuthTokenResponse {
        try await post(
            "/auth/google",
            body: GoogleSignInBody(idToken: idToken),
            responseType: AuthTokenResponse.self
        )
    }

    // ─────────────────────────────────────────────────────────────────────

    struct AppleSignInBody: Encodable {
        let identityToken: String
        let authorizationCode: String
        let fullName: String?
    }

    /// Authenticates with Apple Sign-In credentials. Returns tokens + user on success.
    static func appleSignIn(
        identityToken: String,
        authorizationCode: String,
        fullName: String?
    ) async throws -> AuthTokenResponse {
        try await post(
            "/auth/apple",
            body: AppleSignInBody(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: fullName
            ),
            responseType: AuthTokenResponse.self
        )
    }

    // ─────────────────────────────────────────────────────────────────────

    struct ForgotPasswordBody: Encodable {
        let email: String
    }

    /// Requests a password-reset OTP (always returns 200 to prevent enumeration).
    static func forgotPassword(email: String) async throws {
        try await post(
            "/auth/forgot-password",
            body: ForgotPasswordBody(email: email),
            responseType: MessageOnlyResponse.self
        )
    }

    // ─────────────────────────────────────────────────────────────────────

    struct VerifyResetBody: Encodable {
        let email: String
        let code:  String
    }

    /// Verifies the password-reset OTP. Returns a short-lived resetToken.
    static func verifyReset(email: String, code: String) async throws -> String {
        let result = try await post(
            "/auth/verify-reset",
            body: VerifyResetBody(email: email, code: code),
            responseType: ResetTokenResponse.self
        )
        return result.resetToken
    }

    // ─────────────────────────────────────────────────────────────────────

    struct ResetPasswordBody: Encodable {
        let resetToken:  String
        let newPassword: String
    }

    /// Sets a new password using the resetToken from verifyReset.
    static func resetPassword(resetToken: String, newPassword: String) async throws {
        try await post(
            "/auth/reset-password",
            body: ResetPasswordBody(resetToken: resetToken, newPassword: newPassword),
            responseType: MessageOnlyResponse.self
        )
    }

    // ─────────────────────────────────────────────────────────────────────

    struct RefreshBody: Encodable {
        let refreshToken: String
    }

    /// Exchanges a refresh token for a new access token pair.
    /// Persists the rotated tokens and pushes the new access token to Watch.
    @discardableResult
    static func refreshAccessToken() async throws -> RefreshTokenResponse {
        guard let token = StorageManager.shared.loadRefreshToken() else {
            throw AuthError.tokenMissing
        }
        let result = try await post(
            "/auth/refresh-token",
            body: RefreshBody(refreshToken: token),
            responseType: RefreshTokenResponse.self
        )
        // Persist the rotated tokens immediately
        StorageManager.shared.saveSession(
            accessToken:  result.accessToken,
            refreshToken: result.refreshToken
        )
        // Phase 5: push the fresh access token to Watch so SMS stays authorized
        DispatchQueue.main.async {
            WatchConnectivityManager.shared.sendJWTToken(result.accessToken)
        }
        return result
    }

    // ─────────────────────────────────────────────────────────────────────

    /// Invalidates the server-side refresh token and clears local session.
    static func logout() async {
        if let token = StorageManager.shared.loadRefreshToken() {
            struct LogoutBody: Encodable { let refreshToken: String }
            _ = try? await post(
                "/auth/logout",
                body: LogoutBody(refreshToken: token),
                responseType: MessageOnlyResponse.self
            )
        }
        StorageManager.shared.clearSession()
    }

    /// Requests a deletion OTP be sent to the user's registered email.
    /// The backend reads the email from the authenticated user's JWT.
    static func requestDeleteOTP() async throws {
        struct EmptyBody: Encodable {}
        try await authenticatedPost(
            "/auth/request-delete-otp",
            body: EmptyBody(),
            responseType: MessageOnlyResponse.self
        )
    }

    /// Deletes the authenticated backend account after OTP verification.
    /// Local data is cleared by the caller after success.
    static func deleteAccount(code: String) async throws {
        struct DeleteBody: Encodable { let code: String }
        guard let accessToken = StorageManager.shared.loadAccessToken() else {
            throw AuthError.tokenMissing
        }

        do {
            try await deleteWithBody("/auth/account", body: DeleteBody(code: code),
                                     responseType: MessageOnlyResponse.self, accessToken: accessToken)
            return
        } catch AuthError.server(let msg) where shouldRefreshSession(afterServerMessage: msg) {
            // Fall through to refresh
        } catch {
            throw error
        }

        let refreshed = try await refreshAccessToken()
        do {
            try await deleteWithBody("/auth/account", body: DeleteBody(code: code),
                                     responseType: MessageOnlyResponse.self, accessToken: refreshed.accessToken)
        } catch AuthError.server {
            throw AuthError.server("Session expired - please log in again")
        }
    }
}
