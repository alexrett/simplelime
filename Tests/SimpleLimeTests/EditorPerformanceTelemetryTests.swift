import XCTest
@testable import SimpleLime

final class EditorPerformanceTelemetryTests: XCTestCase {
    func testTelemetryUsesStableEditorPerformanceCategory() {
        XCTAssertEqual(EditorPerformanceTelemetry.category, "EditorPerformance")
        XCTAssertFalse(EditorPerformanceTelemetry.subsystem.isEmpty)
    }

    func testTelemetryMetricNameIsStableForLogParsing() {
        XCTAssertEqual(EditorPerformanceTelemetry.metricName("EditorKeyDown"), "EditorKeyDown")
    }

    func testTelemetryMeasuresSynchronousWork() {
        let value = EditorPerformanceTelemetry.measure("EditorTelemetryTest") {
            42
        }

        XCTAssertEqual(value, 42)
    }

    func testTelemetryIntervalReturnsNonNegativeDuration() {
        let interval = EditorPerformanceTelemetry.begin("EditorTelemetryTest")
        let duration = EditorPerformanceTelemetry.end("EditorTelemetryTest", interval)

        XCTAssertGreaterThanOrEqual(duration, 0)
    }
}
