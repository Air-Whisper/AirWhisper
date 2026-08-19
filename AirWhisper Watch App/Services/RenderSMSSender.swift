import Foundation
@MainActor
struct RenderSMSSender
{
    static let shared = RenderSMSSender()

    private let session: URLSession
    private let endpointURL = URL(string: "https://awtwilio-endpoint.onrender.com/send-sms")!

    private init(session: URLSession = .shared)
    {
        self.session = session
    }

    func sendSMS(to: String, body: String, isRetry: Bool = false) async throws -> String {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let token = WatchConnectivityClient.shared.currentAccessToken
            ?? UserDefaults.standard.string(forKey: "watchJWTToken")
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(SendSMSRequest(to: to, body: body))
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RenderSMSSenderError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 401, !isRetry {
                WatchConnectivityClient.shared.clearAccessToken()
                WatchConnectivityClient.shared.requestTokenRefresh()
                guard await waitForNewToken(timeout: 10) != nil else {
                    throw RenderSMSSenderError.backendFailure("Session expired - open the iPhone app once to sync.")
                }
                return try await sendSMS(to: to, body: body, isRetry: true)
            }
            if let backendFailure = try? JSONDecoder().decode(SendSMSFailureResponse.self, from: data),
               let message = backendFailure.error, !message.isEmpty {
                throw RenderSMSSenderError.backendFailure(message)
            }
            throw RenderSMSSenderError.httpStatus(httpResponse.statusCode)
        }

        let successResponse = try JSONDecoder().decode(SendSMSSuccessResponse.self, from: data)
        guard successResponse.success else {
            throw RenderSMSSenderError.backendFailure("Message send failed")
        }
        return successResponse.sid ?? ""
    }

    private func waitForNewToken(timeout: TimeInterval) async -> String? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let token = WatchConnectivityClient.shared.currentAccessToken, !token.isEmpty {
                return token
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }
}

private struct SendSMSRequest: Codable {
    let to: String
    let body: String
}

private struct SendSMSSuccessResponse: Codable {
    let success: Bool
    let sid: String?
}

private struct SendSMSFailureResponse: Codable {
    let success: Bool?
    let error: String?
}

enum RenderSMSSenderError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case backendFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .httpStatus(let code):
            return "SMS service returned status \(code)."
        case .backendFailure(let message):
            return message
        }
    }
}
