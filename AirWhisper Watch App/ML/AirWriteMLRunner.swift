import Combine
import CoreML
import Foundation

@MainActor
final class MLModelState: ObservableObject {
    static let shared = MLModelState()
    @Published private(set) var isReady: Bool = false

    func markReady() {
        isReady = true
    }
}

struct AirWriteMLRunner {

    enum RunnerError: Error, LocalizedError {
        case invalidShape
        case modelUnavailable
        case modelLoadFailed(String)
        case outputMissing(String)
        case predictionFailed(String)
        case shapeMismatch(expected: [Int], actual: [NSNumber])

        var errorDescription: String? {
            switch self {
            case .invalidShape:
                return "Input must be [384][15]"
            case .modelUnavailable:
                return "Core ML model not loaded"
            case .modelLoadFailed(let message):
                return "Model load failed: \(message)"
            case .outputMissing(let message):
                return "Missing model output: \(message)"
            case .predictionFailed(let message):
                return message
            case .shapeMismatch(let expected, let actual):
                return "Shape mismatch: expected \(expected), got \(actual.map { $0.intValue })"
            }
        }
    }

    struct PredictionResult {
        let finalLabel: String
        let confidence: Double
        let mainLabel: String
        let mainConfidence: Double
        let dpProb: Double?
        let dpRefined: Bool
        let top3: [(label: String, prob: Double)]
        let rawMainProbs: [Double]
    }

    static let labels = [
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    ]

    static let dIndex = 3
    static let pIndex = 15

    private static var cachedModel: MLModel?
    private static var modelInputName: String?
    private static var modelOutputNames: [String] = []
    private static var modelLoadError: Error?

    private static let modelLock = NSLock()
    private static var cachedInput: MLMultiArray?
    private static let inferenceLock = NSLock()

    private static func loadModel() -> MLModel? {
        modelLock.lock()
        defer { modelLock.unlock() }

        if let model = cachedModel {
            return model
        }
        if modelLoadError != nil {
            return nil
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuOnly

            guard let modelURL = Bundle.main.url(forResource: "IMUClassifier", withExtension: "mlmodelc") else {
                modelLoadError = RunnerError.modelUnavailable
                Log.error(Log.ml, "IMUClassifier model file not found in bundle")
                return nil
            }

            let model = try MLModel(contentsOf: modelURL, configuration: config)
            cachedModel = model

            modelInputName = model.modelDescription.inputDescriptionsByName.keys.first
            modelOutputNames = Array(model.modelDescription.outputDescriptionsByName.keys).sorted()

            Log.info(
                Log.ml,
                "IMUClassifier loaded input=\(modelInputName ?? "unknown") outputs=\(modelOutputNames.joined(separator: ","))"
            )
            return model
        } catch {
            modelLoadError = RunnerError.modelLoadFailed(error.localizedDescription)
            Log.error(Log.ml, "Failed to load IMUClassifier: \(error.localizedDescription)")
            return nil
        }
    }

    private static func getOrCreateInputBuffer() throws -> MLMultiArray {
        if let existing = cachedInput {
            return existing
        }
        let created = try MLMultiArray(shape: [1, 384, 15], dataType: .float32)
        cachedInput = created
        return created
    }

    static func warmUp() {
        inferenceLock.lock()
        defer { inferenceLock.unlock() }

        let t0 = CFAbsoluteTimeGetCurrent()
        _ = loadModel()
        _ = try? getOrCreateInputBuffer()
        let t1 = CFAbsoluteTimeGetCurrent()
        Log.info(Log.ml, String(format: "IMUClassifier warmUp finished in %.3fs", t1 - t0))
    }

    static func predict(_ tensor: [[Float]]) throws -> String {
        try predictDetailed(tensor).finalLabel
    }

    static func predictWithConfidence(_ tensor: [[Float]]) throws -> (label: String, confidence: Double) {
        let result = try predictDetailed(tensor)
        return (result.finalLabel, result.confidence)
    }

    static func predictDetailed(_ tensor: [[Float]]) throws -> PredictionResult {
        guard tensor.count == 384, tensor.allSatisfy({ $0.count == 15 }) else {
            throw RunnerError.invalidShape
        }

        guard let model = loadModel() else {
            throw RunnerError.modelUnavailable
        }

        let t0 = CFAbsoluteTimeGetCurrent()

        inferenceLock.lock()
        defer { inferenceLock.unlock() }

        let inputBuffer = try getOrCreateInputBuffer()

        let expectedInputShape: [NSNumber] = [NSNumber(value: 1), NSNumber(value: 384), NSNumber(value: 15)]
        guard inputBuffer.shape == expectedInputShape else {
            throw RunnerError.shapeMismatch(expected: [1, 384, 15], actual: inputBuffer.shape)
        }

        let ptr = inputBuffer.dataPointer.bindMemory(to: Float32.self, capacity: 384 * 15)
        for t in 0..<384 {
            let base = t * 15
            for f in 0..<15 {
                ptr[base + f] = tensor[t][f]
            }
        }

        let inputName = modelInputName ?? model.modelDescription.inputDescriptionsByName.keys.first ?? "sensor_input"
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: inputBuffer])
        let output = try model.prediction(from: provider)

        let unpacked = try unpackOutputs(output)
        let mainProbs = unpacked.mainProbs
        let dpProb = unpacked.dpProb

        let mainPred = argmax(mainProbs)
        let mainLabel = labels[mainPred]
        let mainConf = mainProbs[mainPred]

        let isDPCandidate = (mainPred == dIndex || mainPred == pIndex)
        var finalPred = mainPred
        var confidence = mainConf

        if let dpProb, isDPCandidate {
            finalPred = dpProb > 0.5 ? pIndex : dIndex
            confidence = (finalPred == pIndex) ? dpProb : (1.0 - dpProb)
        }

        let finalLabel = labels[finalPred]
        let top3 = topK(mainProbs, k: 3).map { (label: labels[$0.index], prob: $0.prob) }

        let t1 = CFAbsoluteTimeGetCurrent()
        Log.info(
            Log.ml,
            String(
                format: "Predict final=%@ conf=%.4f main=%@ mainConf=%.4f dpProb=%@ dpRefined=%@ t=%.3fs",
                finalLabel,
                confidence,
                mainLabel,
                mainConf,
                dpProb != nil ? String(format: "%.4f", dpProb!) : "nil",
                isDPCandidate ? "1" : "0",
                t1 - t0
            )
        )

        let top3Debug = top3
            .map { "\($0.label):\(String(format: "%.4f", $0.prob))" }
            .joined(separator: ",")
        Log.debug(Log.ml, "top3=\(top3Debug) outputs=\(modelOutputNames.joined(separator: ","))")

        return PredictionResult(
            finalLabel: finalLabel,
            confidence: confidence,
            mainLabel: mainLabel,
            mainConfidence: mainConf,
            dpProb: dpProb,
            dpRefined: isDPCandidate,
            top3: top3,
            rawMainProbs: mainProbs
        )
    }

    static func processAndPredict(_ samples: [MotionSample]) throws -> (label: String, confidence: Double) {
        let processed = AirWritePreprocessor.preprocess(samples)
        return try predictWithConfidence(processed)
    }

    private static func unpackOutputs(_ provider: MLFeatureProvider) throws -> (mainProbs: [Double], dpProb: Double?) {
        let outputNames = modelOutputNames.isEmpty
            ? Array(provider.featureNames).sorted()
            : modelOutputNames

        var mainArray: MLMultiArray?
        var dpArray: MLMultiArray?

        for name in outputNames {
            guard let value = provider.featureValue(for: name), let arr = value.multiArrayValue else {
                continue
            }
            let count = arr.count
            if count == 26 {
                mainArray = arr
            } else if count == 1 {
                dpArray = arr
            }
        }

        if mainArray == nil {
            for name in provider.featureNames {
                guard let value = provider.featureValue(for: name), let arr = value.multiArrayValue else {
                    continue
                }
                if arr.count == 26 {
                    mainArray = arr
                } else if arr.count == 1 {
                    dpArray = arr
                }
            }
        }

        guard let mainArray else {
            throw RunnerError.outputMissing("26-way main output not found")
        }

        // Accept shape [26] or [1, 26] (batch dimension)
        let mainShape = mainArray.shape.map { $0.intValue }
        guard mainShape == [26] || mainShape == [1, 26] else {
            throw RunnerError.shapeMismatch(expected: [26], actual: mainArray.shape)
        }

        var mainProbs = Array(repeating: 0.0, count: 26)
        let mainPtr = mainArray.dataPointer.bindMemory(to: Float32.self, capacity: 26)
        for i in 0..<26 {
            mainProbs[i] = Double(mainPtr[i])
        }

        var dpProb: Double?
        if let dpArray {
            // Accept shape [1] or [1, 1] (batch dimension)
            let dpShape = dpArray.shape.map { $0.intValue }
            guard dpShape == [1] || dpShape == [1, 1] else {
                throw RunnerError.shapeMismatch(expected: [1], actual: dpArray.shape)
            }
            let dpPtr = dpArray.dataPointer.bindMemory(to: Float32.self, capacity: 1)
            dpProb = Double(dpPtr[0])
        }

        return (mainProbs, dpProb)
    }

    private static func argmax(_ values: [Double]) -> Int {
        var bestIdx = 0
        var bestVal = -Double.greatestFiniteMagnitude
        for i in 0..<values.count {
            if values[i] > bestVal {
                bestVal = values[i]
                bestIdx = i
            }
        }
        return bestIdx
    }

    private static func topK(_ values: [Double], k: Int) -> [(index: Int, prob: Double)] {
        let indexed = values.enumerated().map { (index: $0.offset, prob: $0.element) }
        return Array(indexed.sorted { $0.prob > $1.prob }.prefix(max(0, k)))
    }
}
