import Foundation

enum TrickQuality: String, Codable, CaseIterable, Identifiable {
    case good
    case bad

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .good: return "Good"
        case .bad: return "Bad"
        }
    }
}

/// The judgment a human attaches to a clip after reviewing the extracted pose.
/// Deliberately separate from `ClipMetadata` extraction fields: a clip can
/// exist unlabeled (just extracted), then get labeled later in its own pass.
struct TrickLabel: Codable, Equatable {
    var trickName: String
    var quality: TrickQuality
    var notes: String
    var labeledAt: Date
}
