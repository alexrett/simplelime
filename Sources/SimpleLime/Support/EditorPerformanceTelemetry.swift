import Foundation
import OSLog

struct EditorPerformanceInterval {
    fileprivate var state: OSSignpostIntervalState
    fileprivate var startedAtNanoseconds: UInt64
}

enum EditorPerformanceTelemetry {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.whitehappypony.SimpleLime"
    static let category = "EditorPerformance"
    static let logger = Logger(subsystem: subsystem, category: category)
    static let signposter = OSSignposter(subsystem: subsystem, category: category)

    static func begin(_ name: StaticString) -> EditorPerformanceInterval {
        EditorPerformanceInterval(
            state: signposter.beginInterval(name),
            startedAtNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
    }

    @discardableResult
    static func end(_ name: StaticString, _ interval: EditorPerformanceInterval) -> Double {
        signposter.endInterval(name, interval.state)
        let duration = durationMilliseconds(since: interval.startedAtNanoseconds)
        logger.info("metric=\(metricName(name), privacy: .public) duration_ms=\(duration, privacy: .public)")
        return duration
    }

    @discardableResult
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let interval = begin(name)
        defer { end(name, interval) }
        return try work()
    }

    static func metricName(_ name: StaticString) -> String {
        String(describing: name)
    }

    static func durationMilliseconds(since startedAtNanoseconds: UInt64) -> Double {
        let endedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
        guard endedAtNanoseconds >= startedAtNanoseconds else { return 0 }
        return Double(endedAtNanoseconds - startedAtNanoseconds) / 1_000_000
    }
}
