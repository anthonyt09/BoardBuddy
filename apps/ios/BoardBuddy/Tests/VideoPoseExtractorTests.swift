import XCTest

@testable import BoardBuddy

/// End-to-end check that ML Kit actually returns landmarks for real skate
/// footage — not just that the code compiles against the SDK.
///
/// This exists because the import path in the app goes through
/// `PHPickerViewController`, which renders out-of-process and therefore
/// can't be driven by synthetic taps in the simulator. Testing the
/// extractor directly is both automatable and a better regression target:
/// it's the pose pipeline we care about, not the system picker.
final class VideoPoseExtractorTests: XCTestCase {

    /// A 4-second, 640x348 cut of `ml/skate_video.mp4` — a skater rolling
    /// through frame. Short on purpose: the Accurate model runs per frame,
    /// and the full 56s clip is ~1900 frames.
    private func fixtureURL() throws -> URL {
        try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "skate_short", withExtension: "mp4"),
            "skate_short.mp4 missing from the test bundle"
        )
    }

    func testExtractsPoseLandmarksFromSkateFootage() throws {
        let url = try fixtureURL()

        // ML Kit raises an NSException if `results(in:)` runs on the main
        // thread, and XCTest bodies are main-thread by default — so the
        // extraction has to be hopped onto a background queue.
        let finished = expectation(description: "extraction finished")
        var result: ExtractionResult?
        var failure: Error?

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                result = try VideoPoseExtractor().extract(from: url)
            } catch {
                failure = error
            }
            finished.fulfill()
        }

        // Generous: the Accurate model under x86_64 translation on a
        // simulator is far slower than on device.
        wait(for: [finished], timeout: 600)

        if let failure { throw failure }
        let extraction = try XCTUnwrap(result)

        XCTAssertGreaterThan(extraction.frameCount, 0, "no frames were decoded")
        XCTAssertGreaterThan(
            extraction.detectedFrameCount, 0,
            "decoded \(extraction.frameCount) frames but ML Kit found a person in none of them"
        )

        let rate = Double(extraction.detectedFrameCount) / Double(extraction.frameCount)
        print(
            """
            POSE EXTRACTION RESULT
              frames decoded:  \(extraction.frameCount)
              frames detected: \(extraction.detectedFrameCount)
              detection rate:  \(Int(rate * 100))%
              fps:             \(extraction.fps)
              frame size:      \(extraction.frameSize)
            """
        )

        // A landmark-bearing frame should carry the full 33-point topology,
        // with usable coordinates — guards against a silently empty or
        // all-zero pose being counted as a detection.
        let detected = try XCTUnwrap(
            extraction.frames.first(where: { $0.hasDetection }),
            "expected at least one frame with landmarks"
        )
        XCTAssertEqual(detected.landmarks.count, LandmarkName.allCases.count)

        let hip = try XCTUnwrap(detected.landmark(.leftHip), "missing left hip landmark")
        XCTAssertTrue(hip.x.isFinite && hip.y.isFinite)
        XCTAssertFalse(hip.x == 0 && hip.y == 0, "hip landmark looks like an unset placeholder")
        XCTAssertTrue((0...1).contains(hip.likelihood))

        print("  sample left hip: x=\(hip.x) y=\(hip.y) likelihood=\(hip.likelihood)")
    }
}
