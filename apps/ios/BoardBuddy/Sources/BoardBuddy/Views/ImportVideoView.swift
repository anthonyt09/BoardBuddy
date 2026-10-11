import PhotosUI
import SwiftUI

/// Picks a video from the photo library, runs it through VideoPoseExtractor,
/// and saves the result as a new unlabeled clip. Labeling happens afterwards
/// on ClipListView -> LabelClipView, so a batch of imports can be extracted
/// first and labeled later in a separate pass.
struct ImportVideoView: View {
    @EnvironmentObject private var clipStore: ClipStore
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var progress: Double = 0
    @State private var isExtracting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isExtracting {
                    ProgressView(value: progress) {
                        Text("Extracting poses… \(Int(progress * 100))%")
                    }
                    .padding()
                } else {
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        Label("Choose a video", systemImage: "video.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .navigationTitle("Import clip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExtracting)
                }
            }
            .onChange(of: pickerItem) { newItem in
                guard let newItem else { return }
                Task { await extract(newItem) }
            }
        }
    }

    private func extract(_ item: PhotosPickerItem) async {
        errorMessage = nil
        isExtracting = true
        defer { isExtracting = false }

        do {
            guard let movie = try await item.loadTransferable(type: VideoFile.self) else {
                errorMessage = "Could not load that video."
                return
            }

            let extractor = VideoPoseExtractor()
            let result = try await Task.detached(priority: .userInitiated) {
                try extractor.extract(from: movie.url) { fraction in
                    Task { @MainActor in self.progress = fraction }
                }
            }.value

            try clipStore.saveClip(
                sourceFilename: movie.url.lastPathComponent,
                videoURL: movie.url,
                result: result
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// `PhotosPickerItem.loadTransferable` needs a `Transferable` destination;
/// this copies the picked video to a temp file so AVAssetReader has a
/// stable URL to read from.
private struct VideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { exported in
            SentTransferredFile(exported.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return VideoFile(url: destination)
        }
    }
}
