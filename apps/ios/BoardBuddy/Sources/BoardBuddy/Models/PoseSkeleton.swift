import Foundation

/// Which landmarks are joined by a bone when the pose is drawn.
///
/// ML Kit returns landmarks as an unordered bag of points; the connections
/// between them are a presentation concern, so they live here rather than
/// in the detector. Face points are deliberately left out — for skating,
/// the limbs and torso are what's being judged, and drawing eyes/ears/mouth
/// turns the head into an unreadable blob at clip scale.
enum PoseSkeleton {
    static let bones: [(LandmarkName, LandmarkName)] = [
        // Torso
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),

        // Arms
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),

        // Legs — the ones that matter most for pop, tuck and landing
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),

        // Feet — stance and board contact
        (.leftAnkle, .leftHeel),
        (.leftHeel, .leftToe),
        (.leftAnkle, .leftToe),
        (.rightAnkle, .rightHeel),
        (.rightHeel, .rightToe),
        (.rightAnkle, .rightToe),
    ]

    /// Landmarks worth drawing as dots. Mirrors `bones` so a joint never
    /// appears without the limbs that reach it.
    static let joints: [LandmarkName] = LandmarkName.keyLandmarks.filter { $0 != .nose }
}
