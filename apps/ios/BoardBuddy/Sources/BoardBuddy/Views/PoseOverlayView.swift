import AVFoundation
import SwiftUI

/// Scrub a clip frame by frame with the detected skeleton drawn on top.
///
/// This is the "is the detection actually any good?" screen: a detection
/// rate in the clip list tells you *how many* frames found a person, but
/// only seeing the joints land on the skater tells you whether they found
/// the *right* person, and whether the feet — the part that matters for
/// trick analysis — are tracking the board.
///
/// Frames are pulled with AVAssetImageGenerator rather than played back
/// with AVPlayer: scrubbing needs exact frame-to-landmark alignment, and
/// the generator can be asked for a precise time, where a player's current
/// frame and a timestamped PoseFrame drift apart.
struct PoseOverlayView: View {
    let clip: ClipMetadata

    @EnvironmentObject private var clipStore: ClipStore

    @State private var frames: [PoseFrame] = []
    @State private var index: Double = 0
    @State private var frameImage: UIImage?
    @State private var generator: AVAssetImageGenerator?
    @State private var loadError: String?
    @State private var renderTask: Task<Void, Never>?

    /// Landmarks below this are hidden — ML Kit reports every joint on
    /// every detected frame, including ones it is guessing at off-screen,
    /// and drawing those produces limbs flailing into empty space.
    private let minimumLikelihood = 0.5

    private var currentFrame: PoseFrame? {
        let i = Int(index.rounded())
        return frames.indices.contains(i) ? frames[i] : nil
    }

    var body: some View {
        VStack(spacing: 12) {
            if let loadError {
                ContentMessage(
                    title: "Can't show this clip",
                    message: loadError,
                    systemImage: "exclamationmark.triangle"
                )
            } else if frames.isEmpty {
                ProgressView("Loading pose data…")
                    .frame(maxHeight: .infinity)
            } else {
                frameViewer
                scrubber
                readout
            }
        }
        .padding(.bottom)
        .navigationTitle("Pose overlay")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .onDisappear { renderTask?.cancel() }
    }

    // MARK: - Pieces

    private var frameViewer: some View {
        GeometryReader { geo in
            let box = aspectFitRect(
                content: CGSize(width: clip.frameWidth, height: clip.frameHeight),
                in: geo.size
            )
            ZStack(alignment: .topLeading) {
                Color.black
                if let frameImage {
                    Image(uiImage: frameImage)
                        .resizable()
                        .frame(width: box.width, height: box.height)
                        .offset(x: box.minX, y: box.minY)
                }
                if let frame = currentFrame {
                    SkeletonShape(
                        frame: frame,
                        sourceSize: CGSize(width: clip.frameWidth, height: clip.frameHeight),
                        destination: box,
                        minimumLikelihood: minimumLikelihood
                    )
                }
            }
        }
        .aspectRatio(
            clip.frameHeight > 0 ? CGFloat(clip.frameWidth) / CGFloat(clip.frameHeight) : 16.0 / 9.0,
            contentMode: .fit
        )
        .clipped()
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(value: $index, in: 0...Double(max(frames.count - 1, 1)), step: 1)
                .onChange(of: index) { _ in renderCurrentFrame() }
            HStack {
                Button {
                    index = max(0, index - 1)
                    renderCurrentFrame()
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text("Frame \(Int(index) + 1) of \(frames.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    index = min(Double(frames.count - 1), index + 1)
                    renderCurrentFrame()
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var readout: some View {
        if let frame = currentFrame {
            let shown = frame.landmarks.filter { $0.likelihood >= minimumLikelihood }
            HStack {
                Circle()
                    .fill(frame.hasDetection ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(frame.hasDetection ? "\(shown.count) landmarks" : "no person detected")
                Spacer()
                Text(String(format: "%.2fs", frame.timestamp))
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
    }

    // MARK: - Loading

    private func load() {
        guard frames.isEmpty, loadError == nil else { return }
        do {
            frames = try clipStore.loadFrames(for: clip.id)
            guard !frames.isEmpty else {
                loadError = "This clip has no extracted frames."
                return
            }
            guard let videoURL = clipStore.videoURL(for: clip) else {
                // Clips imported before footage was retained still have
                // landmarks, so show the skeleton without the frame behind it.
                renderCurrentFrame()
                return
            }
            let gen = AVAssetImageGenerator(asset: AVAsset(url: videoURL))
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            generator = gen
            renderCurrentFrame()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func renderCurrentFrame() {
        guard let generator, let frame = currentFrame else { return }
        renderTask?.cancel()
        renderTask = Task {
            let time = CMTime(seconds: frame.timestamp, preferredTimescale: 600)
            let image: UIImage? = await Task.detached(priority: .userInitiated) {
                guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
                return UIImage(cgImage: cg)
            }.value
            if !Task.isCancelled, let image {
                frameImage = image
            }
        }
    }

    /// Letterbox the source frame into the available space, matching how
    /// the image is drawn so landmarks land on the right pixels.
    private func aspectFitRect(content: CGSize, in bounds: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// Draws bones and joints for one frame, mapped from the source video's
/// pixel space into the on-screen letterboxed rect.
private struct SkeletonShape: View {
    let frame: PoseFrame
    let sourceSize: CGSize
    let destination: CGRect
    let minimumLikelihood: Double

    var body: some View {
        Canvas { context, _ in
            for (a, b) in PoseSkeleton.bones {
                guard
                    let pa = point(for: a),
                    let pb = point(for: b)
                else { continue }
                var path = Path()
                path.move(to: pa)
                path.addLine(to: pb)
                context.stroke(path, with: .color(.green), lineWidth: 2)
            }

            for joint in PoseSkeleton.joints {
                guard let p = point(for: joint) else { continue }
                let dot = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: dot), with: .color(.yellow))
            }
        }
    }

    private func point(for name: LandmarkName) -> CGPoint? {
        guard
            sourceSize.width > 0, sourceSize.height > 0,
            let landmark = frame.landmark(name),
            landmark.likelihood >= minimumLikelihood
        else { return nil }

        return CGPoint(
            x: destination.minX + landmark.x / sourceSize.width * destination.width,
            y: destination.minY + landmark.y / sourceSize.height * destination.height
        )
    }
}

/// Small stand-in for ContentUnavailableView, which needs iOS 17.
private struct ContentMessage: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }
}
