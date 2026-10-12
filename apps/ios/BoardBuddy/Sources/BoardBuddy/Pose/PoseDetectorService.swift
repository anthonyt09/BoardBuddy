import AVFoundation
import Foundation
import MLKitPoseDetectionAccurate
import MLKitPoseDetectionCommon
import MLKitVision
import UIKit

/// Thin wrapper around Google ML Kit's on-device pose detector, following
/// the "Detect poses with ML Kit" iOS guide. We always run `.singleImage`
/// mode: ML Kit's `.stream` mode is tuned for a live camera feed (it skips
/// person-detection on later frames and tracks the most prominent person),
/// but here we're decoding a finished video file frame-by-frame, so each
/// frame is detected independently.
///
/// Uses the Accurate model (`GoogleMLKit/PoseDetectionAccurate` in the
/// Podfile) rather than the Base model: extraction runs once per imported
/// clip, off the main thread, so the slower model's better landmark
/// quality is worth the extra latency.
final class PoseDetectorService {
    private let detector: PoseDetector

    init() {
        let options = AccuratePoseDetectorOptions()
        options.detectorMode = .singleImage
        self.detector = PoseDetector.poseDetector(options: options)
    }

    /// Runs detection on one decoded video frame.
    ///
    /// Takes the `CMSampleBuffer` straight from `AVAssetReader` and hands it
    /// to `VisionImage(buffer:)`, which is the path the ML Kit guide
    /// recommends for video frames — converting through
    /// CIImage/CGImage/UIImage first would cost a full image copy on every
    /// one of a clip's ~2k frames.
    ///
    /// - Parameter orientation: how the frame's pixels are rotated relative
    ///   to upright. Derived once per clip from the video track's
    ///   `preferredTransform`; without it, portrait phone footage (whose
    ///   pixel buffers are landscape) is fed to ML Kit sideways and
    ///   detection quality collapses.
    ///
    /// Returns an empty array if no person was found — treat that as
    /// missing data, not a zero pose.
    ///
    /// - Important: ML Kit raises an `NSException` if `results(in:)` is
    ///   called on the main thread. Callers must run this off-main.
    func detectLandmarks(
        in sampleBuffer: CMSampleBuffer,
        orientation: UIImage.Orientation
    ) throws -> [LandmarkSample] {
        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = orientation
        return try detect(visionImage)
    }

    func detectLandmarks(in image: UIImage) throws -> [LandmarkSample] {
        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation
        return try detect(visionImage)
    }

    private func detect(_ visionImage: VisionImage) throws -> [LandmarkSample] {
        let poses = try detector.results(in: visionImage)
        guard let pose = poses.first else { return [] }

        return pose.landmarks.compactMap { landmark -> LandmarkSample? in
            guard let name = LandmarkName(mlKitType: landmark.type) else { return nil }
            return LandmarkSample(
                name: name,
                x: Double(landmark.position.x),
                y: Double(landmark.position.y),
                z: Double(landmark.position.z),
                likelihood: Double(landmark.inFrameLikelihood)
            )
        }
    }
}
