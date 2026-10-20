import SwiftData
import SwiftUI

enum VocabularySortMode: String {
    case wordAsc = "wordAsc"
    case wordDesc = "wordDesc"
}

struct VocabularyView: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @ObservedObject private var modeManager = ModeManager.shared
    @Query private var vocabularyWords: [VocabularyWord]
    @Environment(\.modelContext) private var modelContext
    @State private var newWord = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var sortMode: VocabularySortMode = .wordAsc

    init() {
        if let savedSort = UserDefaults.standard.string(forKey: "vocabularySortMode"),
            let mode = VocabularySortMode(rawValue: savedSort)
        {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedItems: [VocabularyWord] {
        switch sortMode {
        case .wordAsc:
            return vocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        case .wordDesc:
            return vocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedDescending }
        }
    }

    private func toggleSort() {
        sortMode = (sortMode == .wordAsc) ? .wordDesc : .wordAsc
        UserDefaults.standard.set(sortMode.rawValue, forKey: "vocabularySortMode")
    }

    private var shouldShowAddButton: Bool {
        !newWord.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enabled terms are sent to supported speech and text services you select. Models may limit the number of terms; see history for actual usage. VoiceInk Refine does not use vocabulary hints.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let mode = modeManager.currentEffectiveConfiguration,
               let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == mode.selectedTranscriptionModelName }) {
                let snapshot = VocabularySnapshot(terms: sortedItems.filter(\.isEnabled).map(\.word))
                let selection = VocabularyPolicy.recognition(snapshot, provider: model.provider, model: model.name,
                    streaming: TranscriptionRealtimeSupport.isEnabled(for: model, modeValue: mode.isRealtimeTranscriptionEnabled))
                Text(model.displayName + "：" + selection.status.label)
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("", text: $newWord, prompt: Text("Add word to vocabulary"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addWords() }
                    .labelsHidden()

                if shouldShowAddButton {
                    AddIconButton(
                        helpText: "Add word",
                        isDisabled: newWord.isEmpty,
                        action: addWords
                    )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: shouldShowAddButton)

            if !vocabularyWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: toggleSort) {
                        HStack(spacing: 4) {
                            Text(String(localized: "Vocabulary Words (\(vocabularyWords.count))"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            Image(systemName: sortMode == .wordAsc ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Sort alphabetically")

                    FlowLayout(spacing: 8) {
                        ForEach(sortedItems) { item in
                            VocabularyWordView(item: item, onToggle: { toggleWord(item) }, onDelete: { removeWord(item) })
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Vocabulary", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func addWords() {
        let input = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if let error = DictionaryService.addVocabularyWords(
            input, existing: Array(vocabularyWords), context: modelContext)
        {
            alertMessage = error
            showAlert = true
            return
        }
        newWord = ""
    }

    private func toggleWord(_ word: VocabularyWord) {
        word.isEnabled.toggle()
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            alertMessage = String(localized: "Failed to save vocabulary changes.")
            showAlert = true
        }
    }

    private func removeWord(_ word: VocabularyWord) {
        modelContext.delete(word)

        do {
            try modelContext.save()
        } catch {
            // Rollback the delete to restore UI consistency
            modelContext.rollback()
            alertMessage = String(format: String(localized: "Failed to remove word: %@"), error.localizedDescription)
            showAlert = true
        }
    }
}

struct VocabularyWordView: View {
    let item: VocabularyWord
    let onToggle: () -> Void
    let onDelete: () -> Void
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Toggle(isOn: Binding(get: { item.isEnabled }, set: { _ in onToggle() })) {
                Text(item.word)
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(Text(item.word))
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isDeleteHovered ? AppTheme.Status.error : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Remove word")
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDeleteHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.Surface.window.opacity(0.4))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppTheme.Border.subtle, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
}
