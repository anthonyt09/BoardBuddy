import Foundation

enum ClipStoreError: LocalizedError {
    case clipNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .clipNotFound(let id): return "No clip with id \(id)."
        }
    }
}

/// Persists clips as:
///   BoardBuddyClips/clips.jsonl        — one ClipMetadata JSON object per line
///   BoardBuddyClips/frames/<uuid>.json — that clip's [PoseFrame] array
///
/// The split mirrors ml/data/labels.jsonl + ml/data/processed/ in the Python
/// pipeline on purpose: `clips.jsonl` alone is enough to browse, filter, and
/// export labels for training, without paying the cost of loading every
/// frame of every clip. Each clip's frames are a separate file so re-running
/// extraction or deleting a clip never requires rewriting unrelated data.
@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var catalog: [ClipMetadata] = []

    private let catalogURL: URL
    private let framesDirectory: URL

    init(rootDirectory: URL? = nil) {
        let base = rootDirectory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BoardBuddyClips", isDirectory: true)

        catalogURL = base.appendingPathComponent("clips.jsonl")
        framesDirectory = base.appendingPathComponent("frames", isDirectory: true)

        try? FileManager.default.createDirectory(at: framesDirectory, withIntermediateDirectories: true)
        loadCatalog()
    }

    func loadCatalog() {
        guard let text = try? String(contentsOf: catalogURL, encoding: .utf8) else {
            catalog = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        catalog = text
            .split(separator: "\n")
            .compactMap { line -> ClipMetadata? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(ClipMetadata.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func rewriteCatalog() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let lines = try catalog.map { metadata -> String in
            let data = try encoder.encode(metadata)
            return String(decoding: data, as: UTF8.self)
        }
        let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try text.write(to: catalogURL, atomically: true, encoding: .utf8)
    }

    private func framesURL(for id: UUID) -> URL {
        framesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Saves a freshly-extracted, unlabeled clip. Call `label(clipID:...)`
    /// afterwards once a human has reviewed it.
    @discardableResult
    func saveClip(sourceFilename: String, result: ExtractionResult) throws -> ClipMetadata {
        let metadata = ClipMetadata(
            id: UUID(),
            sourceFilename: sourceFilename,
            createdAt: Date(),
            fps: result.fps,
            frameWidth: Int(result.frameSize.width),
            frameHeight: Int(result.frameSize.height),
            frameCount: result.frameCount,
            detectedFrameCount: result.detectedFrameCount,
            label: nil
        )

        try JSONEncoder().encode(result.frames).write(to: framesURL(for: metadata.id))

        catalog.insert(metadata, at: 0)
        try rewriteCatalog()
        return metadata
    }

    /// Attaches or replaces the trick label on an existing clip.
    func label(clipID: UUID, trickName: String, quality: TrickQuality, notes: String) throws {
        guard let index = catalog.firstIndex(where: { $0.id == clipID }) else {
            throw ClipStoreError.clipNotFound(clipID)
        }
        catalog[index].label = TrickLabel(
            trickName: trickName,
            quality: quality,
            notes: notes,
            labeledAt: Date()
        )
        try rewriteCatalog()
    }

    func loadFrames(for clipID: UUID) throws -> [PoseFrame] {
        try JSONDecoder().decode([PoseFrame].self, from: Data(contentsOf: framesURL(for: clipID)))
    }

    func deleteClip(_ clipID: UUID) throws {
        catalog.removeAll { $0.id == clipID }
        try rewriteCatalog()
        try? FileManager.default.removeItem(at: framesURL(for: clipID))
    }
}
