import SwiftUI
import SwiftData
import OSLog

struct VocabularyCorrectionSheet: View {
    let transcriptionID: UUID
    let source: VocabularyLearningService.Source
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var original = ""
    @State private var corrected = ""
    @State private var remember = true
    @State private var fixedReplacement = false
    @State private var errorMessage: String?
    @FocusState private var originalFocused: Bool

    private var preview: Result<VocabularyRewriteResult, Error> {
        Result { try VocabularyLearningService.preview(source.output, original: original, corrected: corrected) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Correct and Remember").font(.headline)
            Text("This edits this history result only. Raw recognition is preserved; nothing is pasted into another app.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(source.enhancedText == nil ? String(localized: "After local processing") : String(localized: "Enhanced"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(source.output).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LabeledContent("Current wording") {
                        TextField("", text: $original)
                            .accessibilityLabel(Text("Current wording"))
                            .focused($originalFocused)
                    }
                    LabeledContent("Correct vocabulary term") {
                        TextField("", text: $corrected)
                            .accessibilityLabel(Text("Correct vocabulary term"))
                    }
                    Toggle("Remember and enable the correct term", isOn: $remember)
                    Toggle("Always replace this wording in future", isOn: $fixedReplacement)
                    Text("Fixed replacements can change other sentences too. Leave this off unless the wording should always be replaced.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Enabled terms may be sent to the speech and text services you select. Adding a term does not guarantee recognition accuracy.")
                        .font(.caption).foregroundStyle(.secondary)
                    switch preview {
                    case .success(let value):
                        Text("Preview: \(value.matches.count) replacements")
                            .font(.subheadline)
                        Text(value.text).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .failure(let error):
                        if !original.isEmpty || !corrected.isEmpty {
                            Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(AppTheme.Status.error)
                            .accessibilityLabel(Text(errorMessage))
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Correction", action: save).keyboardShortcut(.defaultAction)
                    .disabled(isInvalid)
            }
        }
        .padding(20)
        .frame(width: 560, height: 560)
        .onAppear { originalFocused = true }
    }

    private var isInvalid: Bool {
        if case .success = preview { return false }
        return true
    }

    private func save() {
        do {
            try VocabularyLearningService.apply(to: transcriptionID, expected: source,
                original: original, corrected: corrected, remember: remember,
                fixedReplacement: fixedReplacement, context: modelContext)
            dismiss()
        } catch {
            if !(error is VocabularyLearningService.Failure) {
                Logger(subsystem: "com.jackie-yeh.wagong", category: "VocabularyLearning").error("Vocabulary correction could not read saved data")
            }
            // Service errors are fixed messages, never provider errors or user content.
            errorMessage = (error as? VocabularyLearningService.Failure)?.errorDescription
                ?? String(localized: "The correction could not be saved. Try again after reopening this entry.")
        }
    }
}
