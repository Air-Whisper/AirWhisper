import Foundation

// ⚠️ WARNING: This service calls an unofficial/legacy Google handwriting endpoint.
// Verify the endpoint's current status against Google's documentation before App Store submission.
// Consider migrating to ML Kit on-device handwriting recognition to eliminate this network dependency.

final class GoogleHandwritingService {

    static let shared = GoogleHandwritingService()
    private init() {}

    private let apiURL = "https://inputtools.google.com/request?itc=en-t-i0-handwrit"
    private let sampleIntervalMs = 20    // 50Hz sampling
    private let strokeGapMs = 100        // Gap between strokes
    private let requestTimeout: TimeInterval = 10

    func recognizeLetter(
        strokes: [[CGPoint]],
        canvasSize: CGSize,
        completion: @escaping (String?) -> Void
    ) {
        let inkData = convertStrokesToInkData(strokes: strokes, canvasSize: canvasSize)

        guard !inkData.isEmpty else {
            Log.error(Log.ml, "GoogleHandwriting: No valid stroke data")
            completion(nil)
            return
        }

        let requestBody = buildRequestBody(inkData: inkData, canvasSize: canvasSize)

        sendRequest(body: requestBody, completion: completion)
    }

    private func convertStrokesToInkData(strokes: [[CGPoint]], canvasSize: CGSize) -> [[[Int]]] {
        var inkData: [[[Int]]] = []
        var currentTime = 0

        for stroke in strokes {
            guard stroke.count >= 2 else { continue }

            var xCoords: [Int] = []
            var yCoords: [Int] = []
            var timestamps: [Int] = []

            for point in stroke {
                let x = Int(point.x * canvasSize.width)
                let y = Int(point.y * canvasSize.height)

                xCoords.append(x)
                yCoords.append(y)
                timestamps.append(currentTime)
                currentTime += sampleIntervalMs
            }

            if !xCoords.isEmpty {
                inkData.append([xCoords, yCoords, timestamps])
            }
            currentTime += strokeGapMs
        }

        return inkData
    }

    private func buildRequestBody(inkData: [[[Int]]], canvasSize: CGSize) -> [String: Any] {
        [
            "input_type": 0,
            "requests": [
                [
                    "writing_guide": [
                        "writing_area_width": Int(canvasSize.width),
                        "writing_area_height": Int(canvasSize.height)
                    ],
                    "ink": inkData,
                    "language": "en"
                ]
            ]
        ]
    }

    private func sendRequest(body: [String: Any], completion: @escaping (String?) -> Void) {
        guard let url = URL(string: apiURL) else {
            Log.error(Log.ml, "GoogleHandwriting: Invalid URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            Log.error(Log.ml, "GoogleHandwriting: Failed to serialize request: \(error)")
            completion(nil)
            return
        }

        Log.info(Log.ml, "GoogleHandwriting: Sending request")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                Log.error(Log.ml, "GoogleHandwritingService: network request failed  - \(error.localizedDescription). OrientWrite result unavailable.")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard let data = data else {
                Log.error(Log.ml, "GoogleHandwritingService: no data received. OrientWrite result unavailable.")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            self.parseResponse(data: data, completion: completion)
        }.resume()
    }

    private func parseResponse(data: Data, completion: @escaping (String?) -> Void) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  json.count >= 2,
                  let status = json[0] as? String,
                  status == "SUCCESS",
                  let results = json[1] as? [[Any]],
                  let firstResult = results.first,
                  firstResult.count >= 2,
                  let candidates = firstResult[1] as? [String],
                  let topCandidate = candidates.first else {

                if let responseString = String(data: data, encoding: .utf8) {
                    Log.error(Log.ml, "GoogleHandwritingService: unrecognized response format: \(responseString). OrientWrite result unavailable.")
                }
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let letter = String(topCandidate.prefix(1)).uppercased()

            Log.info(Log.ml, "GoogleHandwriting: Recognized '\(letter)' (candidates: \(candidates.prefix(3).joined(separator: ", ")))")

            DispatchQueue.main.async {
                completion(letter)
            }

        } catch {
            Log.error(Log.ml, "GoogleHandwriting: Failed to parse response: \(error)")
            DispatchQueue.main.async { completion(nil) }
        }
    }
}
