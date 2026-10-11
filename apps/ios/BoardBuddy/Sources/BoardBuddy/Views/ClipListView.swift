import SwiftUI

struct ClipListView: View {
    @EnvironmentObject private var clipStore: ClipStore
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                if clipStore.catalog.isEmpty {
                    EmptyClipsView()
                }
                ForEach(clipStore.catalog) { clip in
                    NavigationLink(value: clip.id) {
                        ClipRow(clip: clip)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Clips")
            .navigationDestination(for: UUID.self) { clipID in
                if let clip = clipStore.catalog.first(where: { $0.id == clipID }) {
                    LabelClipView(clip: clip)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import video", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isImporting) {
                ImportVideoView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            try? clipStore.deleteClip(clipStore.catalog[index].id)
        }
    }
}

/// Hand-rolled instead of `ContentUnavailableView` (iOS 17+) since this
/// app's floor is iOS 16, set by `PhotosPicker`/`Transferable`.
private struct EmptyClipsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.skating")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No clips yet")
                .font(.headline)
            Text("Import a video to extract poses and label the trick.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowSeparator(.hidden)
    }
}

private struct ClipRow: View {
    let clip: ClipMetadata

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.sourceFilename)
                    .font(.headline)
                Text("\(clip.frameCount) frames · \(Int(clip.detectionRate * 100))% detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let label = clip.label {
                QualityBadge(trickName: label.trickName, quality: label.quality)
            } else {
                Text("Unlabeled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct QualityBadge: View {
    let trickName: String
    let quality: TrickQuality

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(trickName)
                .font(.caption.bold())
            Text(quality.displayName)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(quality == .good ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                .foregroundStyle(quality == .good ? .green : .red)
                .clipShape(Capsule())
        }
    }
}
