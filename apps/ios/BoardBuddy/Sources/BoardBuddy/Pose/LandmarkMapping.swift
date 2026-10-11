import MLKitPoseDetectionCommon

/// Bridges ML Kit's SDK-specific `PoseLandmarkType` to our portable
/// `LandmarkName`. Isolated in its own file (rather than on LandmarkName
/// itself) so Models/ stays free of the MLKitPoseDetectionCommon import —
/// useful if this module is ever reused somewhere without ML Kit linked
/// (tests, a future non-iOS reader of the same JSON format).
extension LandmarkName {
    init?(mlKitType type: PoseLandmarkType) {
        switch type {
        case .nose: self = .nose
        case .leftEyeInner: self = .leftEyeInner
        case .leftEye: self = .leftEye
        case .leftEyeOuter: self = .leftEyeOuter
        case .rightEyeInner: self = .rightEyeInner
        case .rightEye: self = .rightEye
        case .rightEyeOuter: self = .rightEyeOuter
        case .leftEar: self = .leftEar
        case .rightEar: self = .rightEar
        case .mouthLeft: self = .mouthLeft
        case .mouthRight: self = .mouthRight
        case .leftShoulder: self = .leftShoulder
        case .rightShoulder: self = .rightShoulder
        case .leftElbow: self = .leftElbow
        case .rightElbow: self = .rightElbow
        case .leftWrist: self = .leftWrist
        case .rightWrist: self = .rightWrist
        case .leftPinkyFinger: self = .leftPinkyFinger
        case .rightPinkyFinger: self = .rightPinkyFinger
        case .leftIndexFinger: self = .leftIndexFinger
        case .rightIndexFinger: self = .rightIndexFinger
        case .leftThumb: self = .leftThumb
        case .rightThumb: self = .rightThumb
        case .leftHip: self = .leftHip
        case .rightHip: self = .rightHip
        case .leftKnee: self = .leftKnee
        case .rightKnee: self = .rightKnee
        case .leftAnkle: self = .leftAnkle
        case .rightAnkle: self = .rightAnkle
        case .leftHeel: self = .leftHeel
        case .rightHeel: self = .rightHeel
        case .leftToe: self = .leftToe
        case .rightToe: self = .rightToe
        default: return nil
        }
    }
}
