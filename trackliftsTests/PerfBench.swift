import Foundation

/// Times `body` `iterations` times with a monotonic clock; prints avg + min in
/// milliseconds and returns the average ms. Used by the *PerformanceTests to emit
/// CLI-visible numbers (the `measure {}` blocks store their results in the
/// .xcresult, which xcodebuild doesn't echo to stdout).
@discardableResult
func benchMillis(_ label: String, iterations: Int = 10, _ body: () -> Void) -> Double {
    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        let d = ContinuousClock().measure { body() }
        let ms = Double(d.components.seconds) * 1_000
               + Double(d.components.attoseconds) / 1_000_000_000_000_000
        samples.append(ms)
    }
    let avg = samples.reduce(0, +) / Double(samples.count)
    print(String(format: "[BENCH] %@ — avg %.3f ms, min %.3f ms (x%d)",
                 label, avg, samples.min() ?? 0, iterations))
    return avg
}
