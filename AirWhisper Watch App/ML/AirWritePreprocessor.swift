import Foundation

struct AirWritePreprocessor {

    static let targetLength = 384
    static let featureCount = 15

    // Stage11 feature order expected by training/inference scripts.
    static let finalFeatureNames: [String] = [
        "rotationRateX",
        "rotationRateY",
        "rotationRateZ",
        "accelerationWorldX",
        "accelerationWorldY",
        "accelerationWorldZ",
        "gyroEnergy",
        "accEnergy",
        "energyProgress",
        "deltaRotationRateX",
        "deltaRotationRateY",
        "deltaRotationRateZ",
        "deltaAccelerationWorldX",
        "deltaAccelerationWorldY",
        "deltaAccelerationWorldZ",
    ]

    // Loaded from global_scaler_train_v3.npz (mean/std in FINAL_FEATURES order).
    private static let globalMean: [Double] = [
        -0.057674496323536016,
        -0.0017592483442072922,
        -0.10080473750879536,
        0.0023243412344813633,
        -0.0009667912228773782,
        0.0074106236312124416,
        0.984678933080471,
        0.24309965979532244,
        0.6021334837658948,
        5.770407472439159e-05,
        5.2614091099022085e-05,
        7.683106079113074e-05,
        -1.5812677351982014e-06,
        1.3035435224858221e-05,
        -1.3311928303427514e-05,
    ]

    private static let globalStd: [Double] = [
        0.8043804788616005,
        0.6778114677894295,
        0.789353070017606,
        0.15196347080630462,
        0.16024946190905606,
        0.24745099539735863,
        0.8794504227751145,
        0.2257622457857582,
        0.3462973930556429,
        0.1075281168932599,
        0.10632693998980683,
        0.08169301589619112,
        0.032160004843072014,
        0.033834447435281134,
        0.03551094813179019,
    ]

    // Derived from Stage4 trimmed mean dt over supplied training corpus.
    private static let globalRateHz = 100.10400618197019
    private static let dtGlobal = 1.0 / globalRateHz

    private static let gapFactor = 5.0
    private static let largeFactor = 50.0
    private static let trailingFraction = 0.20
    private static let flatlineEps = 1e-9
    private static let flatlineMinRun = 10

    private static let despikeWindowSec = 0.20
    private static let despikeZ = 7.5

    private static let endSmoothSec = 0.50
    private static let endTailSec = 1.50
    private static let endAutoLowQ = 0.10
    private static let endAutoHighQ = 0.90
    private static let endAutoMix = 0.20
    private static let endGyroWeight = 1.0

    struct Diagnostics {
        let rawCount: Int
        let afterStage2Count: Int
        let afterStage3Count: Int
        let afterStage6Count: Int
        let afterStage8Count: Int
        let stage11Shape: (rows: Int, cols: Int)
        let signature: TensorSignature
    }

    struct Output {
        let tensor: [[Float]]
        let diagnostics: Diagnostics
    }

    struct TensorSignature {
        let sum: Double
        let mean: Double
        let std: Double
        let min: Double
        let max: Double
        let l2: Double
        let firstRow: [Double]
        let lastRow: [Double]
    }

    private struct Stage6Sample {
        let time: Double
        let rotationRateX: Double
        let rotationRateY: Double
        let rotationRateZ: Double
        let accelerationX: Double
        let accelerationY: Double
        let accelerationZ: Double
        let quaternionW: Double
        let quaternionX: Double
        let quaternionY: Double
        let quaternionZ: Double
    }

    private struct Stage9Row {
        let values: [Double]
    }

    static func preprocess(_ samples: [MotionSample]) -> [[Float]] {
        preprocessWithDiagnostics(samples).tensor
    }

    static func preprocessWithDiagnostics(_ samples: [MotionSample]) -> Output {
        let tStart = CFAbsoluteTimeGetCurrent()
        Log.info(Log.preprocess, "Stage11 preprocess start: rawSamples=\(samples.count)")

        func zeroOutput(rawCount: Int = 0, stage2: Int = 0, stage3: Int = 0, stage6: Int = 0, stage8: Int = 0) -> Output {
            let tensor = makeZeroTensor()
            return Output(
                tensor: tensor,
                diagnostics: Diagnostics(
                    rawCount: rawCount,
                    afterStage2Count: stage2,
                    afterStage3Count: stage3,
                    afterStage6Count: stage6,
                    afterStage8Count: stage8,
                    stage11Shape: (rows: targetLength, cols: featureCount),
                    signature: tensorSignature(tensor)
                )
            )
        }

        guard samples.count >= 3 else {
            Log.error(Log.preprocess, "Stage11 preprocess early-exit: insufficient samples")
            return zeroOutput(rawCount: samples.count)
        }

        let stage2 = sortAndDeduplicate(samples)
        guard stage2.count >= 3 else {
            Log.error(Log.preprocess, "Stage2 failed: too short after dedupe")
            return zeroOutput(rawCount: samples.count, stage2: stage2.count)
        }

        let stage3 = trimTrailingFlatlineTail(
            trimTrailingGapTail(stage2)
        )
        guard stage3.count >= 3 else {
            Log.error(Log.preprocess, "Stage3 failed: too short after trailing trim")
            return zeroOutput(rawCount: samples.count, stage2: stage2.count, stage3: stage3.count)
        }

        let stage6 = resampleToGlobalRate(stage3)
        guard stage6.count >= 3 else {
            Log.error(Log.preprocess, "Stage6 failed: resample too short")
            return zeroOutput(rawCount: samples.count, stage2: stage2.count, stage3: stage3.count, stage6: stage6.count)
        }

        let despikeWindow = computeWindowSamples(rateHz: globalRateHz, seconds: despikeWindowSec)
        let stage7 = despikeAndRepair(stage6, window: despikeWindow, zThresh: despikeZ)
        let stage8 = trimAfterEndOfWriting(stage7)

        guard stage8.count >= 1 else {
            Log.error(Log.preprocess, "Stage8 failed: no data after end-trim")
            return zeroOutput(
                rawCount: samples.count,
                stage2: stage2.count,
                stage3: stage3.count,
                stage6: stage6.count,
                stage8: stage8.count
            )
        }

        let stage9 = engineerFinalFeatures(stage8)
        guard !stage9.isEmpty else {
            Log.error(Log.preprocess, "Stage9 failed: feature engineering returned empty")
            return zeroOutput(
                rawCount: samples.count,
                stage2: stage2.count,
                stage3: stage3.count,
                stage6: stage6.count,
                stage8: stage8.count
            )
        }

        let stage10 = normalizeGlobal(stage9)
        let stage11 = warpToFixedLength(stage10, targetLength: targetLength)

        let tensor = stage11.map { row in row.map { Float($0) } }
        let signature = tensorSignature(tensor)
        let diagnostics = Diagnostics(
            rawCount: samples.count,
            afterStage2Count: stage2.count,
            afterStage3Count: stage3.count,
            afterStage6Count: stage6.count,
            afterStage8Count: stage8.count,
            stage11Shape: (rows: stage11.count, cols: stage11.first?.count ?? 0),
            signature: signature
        )

        let tEnd = CFAbsoluteTimeGetCurrent()
        Log.info(Log.preprocess, String(format: "Stage11 preprocess done: out=%dx%d in %.3fs", stage11.count, featureCount, tEnd - tStart))

        let first5 = (tensor.first ?? []).prefix(5).map { String(format: "%.4f", $0) }.joined(separator: ",")
        Log.debug(
            Log.preprocess,
            "tensorSig sum=\(String(format: "%.6f", signature.sum)) mean=\(String(format: "%.6f", signature.mean)) std=\(String(format: "%.6f", signature.std)) min=\(String(format: "%.6f", signature.min)) max=\(String(format: "%.6f", signature.max)) l2=\(String(format: "%.6f", signature.l2)) firstRow[0..4]=[\(first5)]"
        )

        return Output(tensor: tensor, diagnostics: diagnostics)
    }

    static func makeZeroTensor() -> [[Float]] {
        Array(repeating: Array(repeating: 0, count: featureCount), count: targetLength)
    }

    static func tensorSignature(_ tensor: [[Float]]) -> TensorSignature {
        let flattened = tensor.flatMap { $0 }.map(Double.init)
        guard !flattened.isEmpty else {
            return TensorSignature(
                sum: 0,
                mean: 0,
                std: 0,
                min: 0,
                max: 0,
                l2: 0,
                firstRow: [],
                lastRow: []
            )
        }

        let n = Double(flattened.count)
        let sum = flattened.reduce(0, +)
        let mean = sum / n
        var varAcc = 0.0
        var minV = Double.greatestFiniteMagnitude
        var maxV = -Double.greatestFiniteMagnitude
        var l2Acc = 0.0

        for v in flattened {
            let d = v - mean
            varAcc += d * d
            l2Acc += v * v
            minV = min(minV, v)
            maxV = max(maxV, v)
        }

        let std = sqrt(varAcc / n)
        let first = tensor.first?.map(Double.init) ?? []
        let last = tensor.last?.map(Double.init) ?? []

        return TensorSignature(
            sum: sum,
            mean: mean,
            std: std,
            min: minV,
            max: maxV,
            l2: sqrt(l2Acc),
            firstRow: first,
            lastRow: last
        )
    }

    private static func sortAndDeduplicate(_ samples: [MotionSample]) -> [MotionSample] {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        var out: [MotionSample] = []
        out.reserveCapacity(sorted.count)

        var lastTime = -Double.greatestFiniteMagnitude
        for sample in sorted {
            if sample.timestamp > lastTime {
                out.append(sample)
                lastTime = sample.timestamp
            }
        }
        return out
    }

    private static func trimTrailingGapTail(_ samples: [MotionSample]) -> [MotionSample] {
        let n = samples.count
        guard n >= 2 else { return samples }

        var dts: [Double] = []
        dts.reserveCapacity(n - 1)
        for i in 1..<n {
            let dt = samples[i].timestamp - samples[i - 1].timestamp
            if dt > 0 {
                dts.append(dt)
            }
        }

        guard let medDt = median(dts), medDt > 0 else { return samples }

        let gapThreshold = gapFactor * medDt
        let largeThreshold = max(largeFactor * medDt, gapThreshold)
        let cutoff = Int((1.0 - clamp(trailingFraction, lo: 0, hi: 1)) * Double(n))

        var trimIndex: Int?
        for i in 1..<n {
            let dt = samples[i].timestamp - samples[i - 1].timestamp
            if dt > largeThreshold, i >= cutoff {
                trimIndex = (trimIndex == nil) ? i : min(trimIndex!, i)
            }
        }

        guard let idx = trimIndex, idx >= 2, idx < n else { return samples }
        return Array(samples.prefix(idx))
    }

    private static func trimTrailingFlatlineTail(_ samples: [MotionSample]) -> [MotionSample] {
        let n = samples.count
        guard n >= max(2, flatlineMinRun) else { return samples }

        var stableCount = 0
        for i in stride(from: n - 1, through: 1, by: -1) {
            let a = samples[i]
            let b = samples[i - 1]
            if isStableStep(a, b, eps: flatlineEps) {
                stableCount += 1
            } else {
                break
            }
        }

        guard stableCount >= flatlineMinRun else { return samples }
        let keepCount = max(1, n - stableCount)
        return Array(samples.prefix(keepCount))
    }

    private static func isStableStep(_ a: MotionSample, _ b: MotionSample, eps: Double) -> Bool {
        let deltas: [Double] = [
            abs(a.rotationRateX - b.rotationRateX),
            abs(a.rotationRateY - b.rotationRateY),
            abs(a.rotationRateZ - b.rotationRateZ),
            abs(a.gravityX - b.gravityX),
            abs(a.gravityY - b.gravityY),
            abs(a.gravityZ - b.gravityZ),
            abs(a.accelerationX - b.accelerationX),
            abs(a.accelerationY - b.accelerationY),
            abs(a.accelerationZ - b.accelerationZ),
            abs(a.quaternionW - b.quaternionW),
            abs(a.quaternionX - b.quaternionX),
            abs(a.quaternionY - b.quaternionY),
            abs(a.quaternionZ - b.quaternionZ),
        ]
        return deltas.allSatisfy { $0 <= eps }
    }

    private static func resampleToGlobalRate(_ samples: [MotionSample]) -> [Stage6Sample] {
        guard let first = samples.first, let last = samples.last else { return [] }

        let t0 = first.timestamp
        let t1 = last.timestamp
        guard t1 > t0, dtGlobal > 0 else { return [] }

        var grid: [Double] = []
        var t = t0
        while t <= t1 + (0.5 * dtGlobal) {
            if t >= t0, t <= t1 {
                grid.append(t)
            }
            t += dtGlobal
        }

        guard grid.count >= 3 else { return [] }

        let xs = samples.map { $0.timestamp }

        let rrX = interpolateSeries(times: xs, values: samples.map { $0.rotationRateX }, newTimes: grid)
        let rrY = interpolateSeries(times: xs, values: samples.map { $0.rotationRateY }, newTimes: grid)
        let rrZ = interpolateSeries(times: xs, values: samples.map { $0.rotationRateZ }, newTimes: grid)

        let ax = interpolateSeries(times: xs, values: samples.map { $0.accelerationX }, newTimes: grid)
        let ay = interpolateSeries(times: xs, values: samples.map { $0.accelerationY }, newTimes: grid)
        let az = interpolateSeries(times: xs, values: samples.map { $0.accelerationZ }, newTimes: grid)

        let qw = interpolateSeries(times: xs, values: samples.map { $0.quaternionW }, newTimes: grid)
        let qx = interpolateSeries(times: xs, values: samples.map { $0.quaternionX }, newTimes: grid)
        let qy = interpolateSeries(times: xs, values: samples.map { $0.quaternionY }, newTimes: grid)
        let qz = interpolateSeries(times: xs, values: samples.map { $0.quaternionZ }, newTimes: grid)

        var out: [Stage6Sample] = []
        out.reserveCapacity(grid.count)
        for i in 0..<grid.count {
            out.append(
                Stage6Sample(
                    time: grid[i],
                    rotationRateX: rrX[i],
                    rotationRateY: rrY[i],
                    rotationRateZ: rrZ[i],
                    accelerationX: ax[i],
                    accelerationY: ay[i],
                    accelerationZ: az[i],
                    quaternionW: qw[i],
                    quaternionX: qx[i],
                    quaternionY: qy[i],
                    quaternionZ: qz[i]
                )
            )
        }
        return out
    }

    private static func despikeAndRepair(_ samples: [Stage6Sample], window: Int, zThresh: Double) -> [Stage6Sample] {
        guard samples.count >= 3, window >= 3 else { return samples }

        var columns: [[Double]] = [
            samples.map { $0.rotationRateX },
            samples.map { $0.rotationRateY },
            samples.map { $0.rotationRateZ },
            samples.map { $0.accelerationX },
            samples.map { $0.accelerationY },
            samples.map { $0.accelerationZ },
            samples.map { $0.quaternionW },
            samples.map { $0.quaternionX },
            samples.map { $0.quaternionY },
            samples.map { $0.quaternionZ },
        ]

        for i in 0..<columns.count {
            columns[i] = despikeSeries(columns[i], window: window, zThresh: zThresh)
        }

        var out: [Stage6Sample] = []
        out.reserveCapacity(samples.count)
        for i in 0..<samples.count {
            out.append(
                Stage6Sample(
                    time: samples[i].time,
                    rotationRateX: columns[0][i],
                    rotationRateY: columns[1][i],
                    rotationRateZ: columns[2][i],
                    accelerationX: columns[3][i],
                    accelerationY: columns[4][i],
                    accelerationZ: columns[5][i],
                    quaternionW: columns[6][i],
                    quaternionX: columns[7][i],
                    quaternionY: columns[8][i],
                    quaternionZ: columns[9][i]
                )
            )
        }
        return out
    }

    private static func trimAfterEndOfWriting(_ samples: [Stage6Sample]) -> [Stage6Sample] {
        let n = samples.count
        guard n >= 3 else { return samples }

        var energy = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            let aMag = sqrt(
                samples[i].accelerationX * samples[i].accelerationX +
                    samples[i].accelerationY * samples[i].accelerationY +
                    samples[i].accelerationZ * samples[i].accelerationZ
            )
            let gMag = sqrt(
                samples[i].rotationRateX * samples[i].rotationRateX +
                    samples[i].rotationRateY * samples[i].rotationRateY +
                    samples[i].rotationRateZ * samples[i].rotationRateZ
            )
            energy[i] = aMag + endGyroWeight * gMag
        }

        let smoothWindow = computeWindowSamples(rateHz: globalRateHz, seconds: endSmoothSec)
        let tailWindow = computeWindowSamples(rateHz: globalRateHz, seconds: endTailSec)

        let smoothed = movingAverage(energy, window: smoothWindow)
        guard let threshold = inferThreshold(smoothed, lowQ: endAutoLowQ, highQ: endAutoHighQ, mix: endAutoMix) else {
            return samples
        }

        let below = smoothed.map { $0 <= threshold }
        let quietLen = trailingTrueRunLength(below)

        let endIndex: Int
        if quietLen >= tailWindow {
            let quietStart = n - quietLen
            endIndex = max(0, quietStart - 1)
        } else {
            endIndex = n - 1
        }

        let keepCount = max(1, min(n, endIndex + 1))
        return Array(samples.prefix(keepCount))
    }

    private static func engineerFinalFeatures(_ samples: [Stage6Sample]) -> [Stage9Row] {
        var worldAccX: [Double] = []
        var worldAccY: [Double] = []
        var worldAccZ: [Double] = []

        var worldGyroX: [Double] = []
        var worldGyroY: [Double] = []
        var worldGyroZ: [Double] = []

        worldAccX.reserveCapacity(samples.count)
        worldAccY.reserveCapacity(samples.count)
        worldAccZ.reserveCapacity(samples.count)

        worldGyroX.reserveCapacity(samples.count)
        worldGyroY.reserveCapacity(samples.count)
        worldGyroZ.reserveCapacity(samples.count)

        for s in samples {
            let q = normalizedQuaternion(w: s.quaternionW, x: s.quaternionX, y: s.quaternionY, z: s.quaternionZ)
            let accW = rotateByQuaternion(q: q, v: (s.accelerationX, s.accelerationY, s.accelerationZ))
            let gyroW = rotateByQuaternion(q: q, v: (s.rotationRateX, s.rotationRateY, s.rotationRateZ))

            worldAccX.append(accW.0)
            worldAccY.append(accW.1)
            worldAccZ.append(accW.2)

            worldGyroX.append(gyroW.0)
            worldGyroY.append(gyroW.1)
            worldGyroZ.append(gyroW.2)
        }

        let n = samples.count
        guard n > 0 else { return [] }

        var gyroEnergy = Array(repeating: 0.0, count: n)
        var accEnergy = Array(repeating: 0.0, count: n)
        var combined = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            let g = sqrt(worldGyroX[i] * worldGyroX[i] + worldGyroY[i] * worldGyroY[i] + worldGyroZ[i] * worldGyroZ[i])
            let a = sqrt(worldAccX[i] * worldAccX[i] + worldAccY[i] * worldAccY[i] + worldAccZ[i] * worldAccZ[i])
            gyroEnergy[i] = g
            accEnergy[i] = a
            combined[i] = g + a
        }

        let totalEnergy = combined.reduce(0, +)
        var energyProgress = Array(repeating: 0.0, count: n)
        if totalEnergy.isFinite, totalEnergy > 1e-12 {
            var c = 0.0
            for i in 0..<n {
                c += combined[i]
                energyProgress[i] = clamp(c / totalEnergy, lo: 0.0, hi: 1.0)
            }
        } else if n == 1 {
            energyProgress[0] = 1.0
        } else {
            for i in 0..<n {
                energyProgress[i] = Double(i) / Double(n - 1)
            }
        }

        let dRGX = diffWithPrepend(worldGyroX)
        let dRGY = diffWithPrepend(worldGyroY)
        let dRGZ = diffWithPrepend(worldGyroZ)

        let dAWX = diffWithPrepend(worldAccX)
        let dAWY = diffWithPrepend(worldAccY)
        let dAWZ = diffWithPrepend(worldAccZ)

        var out: [Stage9Row] = []
        out.reserveCapacity(n)

        for i in 0..<n {
            var row = [
                worldGyroX[i],
                worldGyroY[i],
                worldGyroZ[i],
                worldAccX[i],
                worldAccY[i],
                worldAccZ[i],
                gyroEnergy[i],
                accEnergy[i],
                energyProgress[i],
                dRGX[i],
                dRGY[i],
                dRGZ[i],
                dAWX[i],
                dAWY[i],
                dAWZ[i],
            ]

            for j in 0..<row.count {
                if !row[j].isFinite {
                    row[j] = 0.0
                }
            }
            out.append(Stage9Row(values: row))
        }

        return out
    }

    private static func normalizeGlobal(_ rows: [Stage9Row]) -> [[Double]] {
        var out: [[Double]] = []
        out.reserveCapacity(rows.count)

        for row in rows {
            var normalized = Array(repeating: 0.0, count: featureCount)
            for i in 0..<featureCount {
                let std = max(globalStd[i], 1e-6)
                var v = (row.values[i] - globalMean[i]) / std
                if !v.isFinite {
                    v = 0.0
                }
                normalized[i] = v
            }
            out.append(normalized)
        }

        return out
    }

    private static func warpToFixedLength(_ seq: [[Double]], targetLength: Int) -> [[Double]] {
        guard targetLength > 0 else { return [] }
        guard !seq.isEmpty else {
            return Array(repeating: Array(repeating: 0.0, count: featureCount), count: targetLength)
        }

        if seq.count == targetLength {
            return seq
        }

        if seq.count == 1 {
            return Array(repeating: seq[0], count: targetLength)
        }

        let srcCount = seq.count
        var out: [[Double]] = []
        out.reserveCapacity(targetLength)

        for i in 0..<targetLength {
            let pos = Double(i) * Double(srcCount - 1) / Double(targetLength - 1)
            let lo = Int(floor(pos))
            let hi = min(srcCount - 1, lo + 1)
            let alpha = pos - Double(lo)

            var row = Array(repeating: 0.0, count: featureCount)
            for f in 0..<featureCount {
                row[f] = seq[lo][f] + (seq[hi][f] - seq[lo][f]) * alpha
            }
            out.append(row)
        }

        return out
    }

    private static func clamp(_ x: Double, lo: Double, hi: Double) -> Double {
        max(lo, min(hi, x))
    }

    private static func median(_ xs: [Double]) -> Double? {
        let vals = xs.filter { $0.isFinite }.sorted()
        guard !vals.isEmpty else { return nil }
        let n = vals.count
        if n % 2 == 1 {
            return vals[n / 2]
        }
        return (vals[(n / 2) - 1] + vals[n / 2]) * 0.5
    }

    private static func quantile(_ xs: [Double], q: Double) -> Double? {
        let vals = xs.filter { $0.isFinite }.sorted()
        guard !vals.isEmpty else { return nil }
        if vals.count == 1 { return vals[0] }

        let qq = clamp(q, lo: 0.0, hi: 1.0)
        let pos = qq * Double(vals.count - 1)
        let lo = Int(floor(pos))
        let hi = min(vals.count - 1, lo + 1)
        let alpha = pos - Double(lo)
        return vals[lo] + (vals[hi] - vals[lo]) * alpha
    }

    private static func computeWindowSamples(rateHz: Double, seconds: Double) -> Int {
        guard rateHz > 0, seconds > 0 else { return 3 }
        var n = Int((rateHz * seconds).rounded())
        n = max(3, n)
        if n % 2 == 0 { n += 1 }
        return n
    }

    private static func movingAverage(_ xs: [Double], window: Int) -> [Double] {
        let n = xs.count
        guard n > 0, window >= 3 else { return xs }
        let half = window / 2
        let minPeriods = max(3, window / 2)

        var out = Array(repeating: Double.nan, count: n)
        for i in 0..<n {
            let lo = max(0, i - half)
            let hi = min(n - 1, i + half)
            var acc = 0.0
            var cnt = 0
            for j in lo...hi {
                let v = xs[j]
                if v.isFinite {
                    acc += v
                    cnt += 1
                }
            }
            if cnt >= minPeriods {
                out[i] = acc / Double(cnt)
            }
        }

        forwardFill(&out)
        backwardFill(&out)

        if out.allSatisfy({ !$0.isFinite }) {
            return xs
        }
        return out.map { $0.isFinite ? $0 : 0.0 }
    }

    private static func inferThreshold(_ xs: [Double], lowQ: Double, highQ: Double, mix: Double) -> Double? {
        var lo = clamp(lowQ, lo: 0.0, hi: 1.0)
        var hi = clamp(highQ, lo: 0.0, hi: 1.0)
        if hi < lo {
            swap(&lo, &hi)
        }
        guard let low = quantile(xs, q: lo), let high = quantile(xs, q: hi) else {
            return nil
        }
        let m = clamp(mix, lo: 0.0, hi: 1.0)
        let thr = low + m * (high - low)
        return thr.isFinite ? thr : nil
    }

    private static func trailingTrueRunLength(_ xs: [Bool]) -> Int {
        var count = 0
        for v in xs.reversed() {
            if v {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private static func interpolateSeries(times: [Double], values: [Double], newTimes: [Double]) -> [Double] {
        guard times.count == values.count, !times.isEmpty else {
            return Array(repeating: 0.0, count: newTimes.count)
        }

        var tx: [Double] = []
        var vy: [Double] = []
        tx.reserveCapacity(times.count)
        vy.reserveCapacity(values.count)

        var lastT = -Double.greatestFiniteMagnitude
        for i in 0..<times.count {
            let t = times[i]
            let v = values[i]
            if t.isFinite, v.isFinite, t > lastT {
                tx.append(t)
                vy.append(v)
                lastT = t
            }
        }

        guard tx.count >= 2 else {
            return Array(repeating: vy.first ?? 0.0, count: newTimes.count)
        }

        var out = Array(repeating: 0.0, count: newTimes.count)
        var j = 0
        for i in 0..<newTimes.count {
            let t = newTimes[i]
            while j + 1 < tx.count, tx[j + 1] < t {
                j += 1
            }

            let loT = tx[j]
            let hiIdx = min(j + 1, tx.count - 1)
            let hiT = tx[hiIdx]
            let loV = vy[j]
            let hiV = vy[hiIdx]

            if hiIdx == j || hiT <= loT {
                out[i] = loV
            } else {
                let alpha = clamp((t - loT) / (hiT - loT), lo: 0.0, hi: 1.0)
                out[i] = loV + (hiV - loV) * alpha
            }
        }
        return out
    }

    private static func despikeSeries(_ x: [Double], window: Int, zThresh: Double) -> [Double] {
        let n = x.count
        guard n >= 3, window >= 3 else { return x }

        let half = window / 2
        let minPeriods = max(3, window / 2)

        var spikes = Array(repeating: false, count: n)
        for i in 0..<n {
            let lo = max(0, i - half)
            let hi = min(n - 1, i + half)

            var vals: [Double] = []
            vals.reserveCapacity(hi - lo + 1)
            for j in lo...hi {
                let v = x[j]
                if v.isFinite {
                    vals.append(v)
                }
            }

            if vals.count < minPeriods {
                continue
            }

            let mean = vals.reduce(0, +) / Double(vals.count)
            var varAcc = 0.0
            for v in vals {
                let d = v - mean
                varAcc += d * d
            }
            let sigma = sqrt(varAcc / Double(vals.count))
            if sigma <= 0 {
                continue
            }

            let xi = x[i]
            if !xi.isFinite {
                spikes[i] = true
                continue
            }

            if abs(xi - mean) / sigma > zThresh {
                spikes[i] = true
            }
        }

        if !spikes.contains(true) {
            return x
        }

        var y = x
        for i in 0..<n where spikes[i] {
            y[i] = Double.nan
        }

        return interpolateNaNs(y)
    }

    private static func interpolateNaNs(_ x: [Double]) -> [Double] {
        let n = x.count
        guard n > 0 else { return x }

        var out = x

        var firstValid: Int?
        for i in 0..<n where out[i].isFinite {
            firstValid = i
            break
        }
        guard let fv = firstValid else {
            return Array(repeating: 0.0, count: n)
        }

        if fv > 0 {
            for i in 0..<fv {
                out[i] = out[fv]
            }
        }

        var prev = fv
        var i = fv + 1
        while i < n {
            if out[i].isFinite {
                prev = i
                i += 1
                continue
            }

            var end = i
            while end < n, !out[end].isFinite {
                end += 1
            }

            if end >= n {
                for k in i..<n {
                    out[k] = out[prev]
                }
                break
            }

            let a = out[prev]
            let b = out[end]
            let span = Double(end - prev)
            if span > 0 {
                for k in (prev + 1)..<end {
                    let alpha = Double(k - prev) / span
                    out[k] = a + (b - a) * alpha
                }
            }

            prev = end
            i = end + 1
        }

        for idx in 0..<n where !out[idx].isFinite {
            out[idx] = 0.0
        }

        return out
    }

    private static func forwardFill(_ x: inout [Double]) {
        var last: Double?
        for i in 0..<x.count {
            if x[i].isFinite {
                last = x[i]
            } else if let last {
                x[i] = last
            }
        }
    }

    private static func backwardFill(_ x: inout [Double]) {
        var next: Double?
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            if x[i].isFinite {
                next = x[i]
            } else if let next {
                x[i] = next
            }
        }
    }

    private static func normalizedQuaternion(w: Double, x: Double, y: Double, z: Double) -> (Double, Double, Double, Double) {
        var qw = w
        var qx = x
        var qy = y
        var qz = z

        let norm = sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
        let denom: Double
        if norm.isFinite, norm > 1e-12 {
            denom = norm
        } else {
            denom = 1.0
            qw = 1.0
            qx = 0.0
            qy = 0.0
            qz = 0.0
        }

        return (qw / denom, qx / denom, qy / denom, qz / denom)
    }

    private static func rotateByQuaternion(
        q: (Double, Double, Double, Double),
        v: (Double, Double, Double)
    ) -> (Double, Double, Double) {
        let qw = q.0
        let qx = q.1
        let qy = q.2
        let qz = q.3

        let r00 = 1.0 - 2.0 * (qy * qy + qz * qz)
        let r01 = 2.0 * (qx * qy - qz * qw)
        let r02 = 2.0 * (qx * qz + qy * qw)

        let r10 = 2.0 * (qx * qy + qz * qw)
        let r11 = 1.0 - 2.0 * (qx * qx + qz * qz)
        let r12 = 2.0 * (qy * qz - qx * qw)

        let r20 = 2.0 * (qx * qz - qy * qw)
        let r21 = 2.0 * (qy * qz + qx * qw)
        let r22 = 1.0 - 2.0 * (qx * qx + qy * qy)

        let x = r00 * v.0 + r01 * v.1 + r02 * v.2
        let y = r10 * v.0 + r11 * v.1 + r12 * v.2
        let z = r20 * v.0 + r21 * v.1 + r22 * v.2
        return (x, y, z)
    }

    private static func diffWithPrepend(_ x: [Double]) -> [Double] {
        guard !x.isEmpty else { return [] }
        var out = Array(repeating: 0.0, count: x.count)
        out[0] = 0.0
        if x.count > 1 {
            for i in 1..<x.count {
                out[i] = x[i] - x[i - 1]
            }
        }
        return out
    }
}
