import Foundation

/// One detected landmark in a single frame, in the source frame's pixel space.
struct LandmarkSample: Codable, Hashable {
    let name: LandmarkName
    let x: Double
    let y: Double
    /// ML Kit's rough depth estimate, relative to the hips. Not metric.
    let z: Double
    /// 0...1 "in frame" confidence ML Kit assigns the landmark.
    let likelihood: Double
}

/// Pose detection result for one decoded video frame.
/// `landmarks` is empty when ML Kit found no person in that frame —
/// callers must treat that as missing data, not a zero pose, same
/// contract the Python pipeline used with NaN rows.
struct PoseFrame: Codable {
    let frameIndex: Int
    let timestamp: TimeInterval
    let landmarks: [LandmarkSample]

    func landmark(_ name: LandmarkName) -> LandmarkSample? {
        landmarks.first { $0.name == name }
    }

    var hasDetection: Bool { !landmarks.isEmpty }
}
