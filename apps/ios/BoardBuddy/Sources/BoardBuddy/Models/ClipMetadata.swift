import Foundation

/// Lightweight, catalog-friendly record for one analyzed clip.
///
/// This is the on-disk equivalent of a row in ml/data/labels.jsonl, extended
/// with extraction stats and a quality judgment. Frame-level landmarks are
/// NOT stored here — they live in a separate per-clip file (see ClipStore) —
/// so the whole catalog can be scanned/exported for training without paying
/// the cost of loading every frame of every clip.
struct ClipMetadata: Codable, Identifiable, Equatable {
    let id: UUID
    var sourceFilename: String
    var createdAt: Date
    var fps: Double
    var frameWidth: Int
    var frameHeight: Int
    var frameCount: Int
    /// Frames where ML Kit found a person at all — a cheap data-quality signal
    /// before anyone spends time labeling the clip.
    var detectedFrameCount: Int
    var label: TrickLabel?

    var isLabeled: Bool { label != nil }

    var detectionRate: Double {
        frameCount > 0 ? Double(detectedFrameCount) / Double(frameCount) : 0
    }
}
