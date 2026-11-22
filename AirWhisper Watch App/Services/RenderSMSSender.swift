import Foundation

struct RenderSMSSender
{
    static let shared = RenderSMSSender()

    private let session: URLSession
    private let endpointURL = URL(string: "https://awtwilio-endpoint.onrender.com/send-sms")!

    private init(session: URLSession = .shared)
    {
        self.session = session
    }

    func sendSMS(to: String, body: String) async throws -> String {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Phase 5: attach JWT sent from the iPhone via WatchConnectivity
        if let token = UserDefaults.standard.string(forKey: "watchJWTToken"), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(SendSMSRequest(to: to, body: body))

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RenderSMSSenderError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if let backendFailure = try? JSONDecoder().decode(SendSMSFailureResponse.self, from: data),
               let message = backendFailure.error,
               !message.isEmpty {
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
