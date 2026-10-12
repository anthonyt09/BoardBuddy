import Foundation

/// Mirrors ML Kit's `PoseLandmarkType` constants (the same 33-point BlazePose
/// topology MediaPipe used in the Python pipeline). Kept as a plain string enum,
/// independent of the MLKitPoseDetection module, so persisted clip files stay
/// readable by any future tool (Swift, Python, JS) without linking ML Kit.
enum LandmarkName: String, Codable, CaseIterable {
    case nose
    case leftEyeInner, leftEye, leftEyeOuter
    case rightEyeInner, rightEye, rightEyeOuter
    case leftEar, rightEar
    case mouthLeft, mouthRight
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftPinkyFinger, rightPinkyFinger
    case leftIndexFinger, rightIndexFinger
    case leftThumb, rightThumb
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
    case leftHeel, rightHeel
    /// ML Kit's name for this point is "toe", not MediaPipe's "foot index" —
    /// same joint, different vendor naming. Kept as ML Kit calls it since
    /// this enum now mirrors ML Kit's PoseLandmarkType, not MediaPipe's.
    case leftToe, rightToe

    /// Landmarks that matter most for trick analysis (stance, pop, rotation).
    /// Kept in one place the way `KEY_LANDMARKS` was in ml/boardbuddy_ml/pose.py.
    static let keyLandmarks: [LandmarkName] = [
        .nose,
        .leftShoulder, .rightShoulder,
        .leftHip, .rightHip,
        .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle,
        .leftHeel, .rightHeel,
        .leftToe, .rightToe,
    ]
}
