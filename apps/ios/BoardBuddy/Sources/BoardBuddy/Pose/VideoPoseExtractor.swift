import AVFoundation
import UIKit

/// Maps a video track's `preferredTransform` rotation onto the orientation
/// ML Kit expects. iPhone footage is always recorded in landscape pixel
/// buffers with a rotation baked into the transform, so a portrait clip
/// decodes as sideways pixels — ML Kit has to be told, or it looks for an
/// upright person in a rotated frame and finds nothing.
private func imageOrientation(for transform: CGAffineTransform) -> UIImage.Orientation {
    // Rounded because the stored transform values are floating point.
    switch (Int(round(atan2(transform.b, transform.a) * 180 / .pi)) % 360 + 360) % 360 {
    case 90: return .right
    case 180: return .down
    case 270: return .left
    default: return .up
    }
}

enum VideoPoseExtractorError: LocalizedError {
    case noVideoTrack
    case readerSetupFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The selected file has no video track."
        case .readerSetupFailed(let reason):
            return "Could not start reading the video: \(reason)"
        }
    }
}

/// Everything extraction produced for one clip, before any label is attached.
struct ExtractionResult {
    let frames: [PoseFrame]
    let fps: Double
    let frameSize: CGSize
    let frameCount: Int
    let detectedFrameCount: Int
}

/// Decodes a video file frame-by-frame and runs ML Kit pose detection on
/// every frame, the offline equivalent of what ml/boardbuddy_ml/pose.py did
/// with MediaPipe: video in, one pose (or a gap) out per frame.
final class VideoPoseExtractor {
    private let poseService: PoseDetectorService

    init(poseService: PoseDetectorService = PoseDetectorService()) {
        self.poseService = poseService
    }

    /// - Parameter progress: called on an arbitrary background queue with a
    ///   0...1 fraction as frames are processed. Hop to the main actor
    ///   yourself if driving UI.
    func extract(from url: URL, progress: ((Double) -> Void)? = nil) throws -> ExtractionResult {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw VideoPoseExtractorError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        // Left at the default `true`: the sample buffer is handed straight to
        // ML Kit, so its backing memory must not be a scratch buffer the
        // reader may recycle underneath the detector.
        reader.add(output)

        let fps = Double(track.nominalFrameRate > 0 ? track.nominalFrameRate : 30)
        let frameSize = track.naturalSize
        let orientation = imageOrientation(for: track.preferredTransform)
        let estimatedTotalFrames = max(1, Int(CMTimeGetSeconds(asset.duration) * fps))

        guard reader.startReading() else {
            throw VideoPoseExtractorError.readerSetupFailed(
                reader.error?.localizedDescription ?? "unknown reader error"
            )
        }

        var frames: [PoseFrame] = []
        var detectedCount = 0
        var frameIndex = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            defer { frameIndex += 1 }

            // A minute of footage is ~2k frames of full-resolution pixel
            // data; without draining per iteration the autoreleased image
            // buffers pile up until the clip finishes and the app is killed
            // for memory.
            try autoreleasepool {
                let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

                let landmarks = try poseService.detectLandmarks(
                    in: sampleBuffer,
                    orientation: orientation
                )
                if !landmarks.isEmpty {
                    detectedCount += 1
                }
                frames.append(
                    PoseFrame(frameIndex: frameIndex, timestamp: seconds, landmarks: landmarks)
                )
            }

            progress?(min(1.0, Double(frameIndex + 1) / Double(estimatedTotalFrames)))
        }

        if reader.status == .failed {
            throw VideoPoseExtractorError.readerSetupFailed(
                reader.error?.localizedDescription ?? "reader failed mid-stream"
            )
        }

        return ExtractionResult(
            frames: frames,
            fps: fps,
            frameSize: frameSize,
            frameCount: frames.count,
            detectedFrameCount: detectedCount
        )
    }
}
