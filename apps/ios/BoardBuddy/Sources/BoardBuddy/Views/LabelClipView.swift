import SwiftUI

struct LabelClipView: View {
    @EnvironmentObject private var clipStore: ClipStore
    let clip: ClipMetadata

    @State private var trickName: String
    @State private var quality: TrickQuality
    @State private var notes: String
    @State private var saved = false

    init(clip: ClipMetadata) {
        self.clip = clip
        _trickName = State(initialValue: clip.label?.trickName ?? "")
        _quality = State(initialValue: clip.label?.quality ?? .good)
        _notes = State(initialValue: clip.label?.notes ?? "")
    }

    var body: some View {
        Form {
            Section("Clip") {
                LabeledContent("Source", value: clip.sourceFilename)
                LabeledContent("Frames", value: "\(clip.frameCount)")
                LabeledContent("Detection rate", value: "\(Int(clip.detectionRate * 100))%")
            }

            Section("Trick") {
                TextField("Trick name (e.g. ollie, kickflip)", text: $trickName)
                Picker("Quality", selection: $quality) {
                    ForEach(TrickQuality.allCases) { q in
                        Text(q.displayName).tag(q)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
            }

            Section {
                Button(saved ? "Saved" : "Save label") {
                    save()
                }
                .disabled(trickName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Label trick")
    }

    private func save() {
        try? clipStore.label(
            clipID: clip.id,
            trickName: trickName.trimmingCharacters(in: .whitespaces),
            quality: quality,
            notes: notes
        )
        saved = true
    }
}
