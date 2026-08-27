import SwiftUI

struct PromptEditorView: View {
    enum Mode {
        case add
        case edit(CustomPrompt)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.add, .add):
                return true
            case (.edit(let prompt1), .edit(let prompt2)):
                return prompt1.id == prompt2.id
            default:
                return false
            }
        }
    }

    let mode: Mode
    @EnvironmentObject private var enhancementService: AIEnhancementService
    let onDismiss: () -> Void
    let onSave: (CustomPrompt) -> Void
    let onDelete: ((CustomPrompt) -> Void)?
    let onRestore: ((CustomPrompt) -> Void)?
    @State private var title: String
    @State private var promptText: String
    @State private var useSystemInstructions: Bool
    @State private var showDeleteConfirmation = false

    private var saveButtonTitle: LocalizedStringKey {
        mode == .add ? "Create & Select" : "Save & Select"
    }

    private var editingPrompt: CustomPrompt? {
        if case .edit(let prompt) = mode {
            return prompt
        }
        return nil
    }

    private var canDeletePrompt: Bool {
        guard let editingPrompt else { return false }
        return onDelete != nil && !PromptTemplates.isBuiltInPrompt(id: editingPrompt.id)
    }

    private var canRestorePrompt: Bool {
        guard let editingPrompt,
            let template = PromptTemplates.template(for: editingPrompt.id),
            onRestore != nil
        else { return false }

        return editingPrompt.title != template.title
            || editingPrompt.promptText != template.promptText
            || editingPrompt.useSystemInstructions != template.useSystemInstructions
    }

    private var isSaveDisabled: Bool {
        return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        mode: Mode,
        onDismiss: @escaping () -> Void,
        onSave: @escaping (CustomPrompt) -> Void,
        onDelete: ((CustomPrompt) -> Void)? = nil,
        onRestore: ((CustomPrompt) -> Void)? = nil
    ) {
        self.mode = mode
        self.onDismiss = onDismiss
        self.onSave = onSave
        self.onDelete = onDelete
        self.onRestore = onRestore
        switch mode {
        case .add:
            _title = State(initialValue: "")
            _promptText = State(initialValue: "")
            _useSystemInstructions = State(initialValue: true)
        case .edit(let prompt):
            _title = State(initialValue: prompt.title)
            _promptText = State(initialValue: prompt.promptText)
            _useSystemInstructions = State(initialValue: prompt.useSystemInstructions)
        }
    }

    private func dismissPanel() {
        onDismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if case .add = mode {
                        templateMenu
                    }

                    instructionsEditor
                    systemTemplateToggle
                }
                .padding(20)
            }

            footer
        }
        .confirmationDialog(
            "Delete Prompt?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deletePrompt()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismissPanel()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.Surface.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Back")

            TextField("Prompt name", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private var systemTemplateToggle: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $useSystemInstructions) {
                HStack(spacing: 4) {
                    Text("Use System Template")
                    InfoTip(
                        "If enabled, your instructions are combined with a general-purpose template to improve transcription quality.\n\nDisable for full control over the AI's system prompt (for advanced users)."
                    )
                }
            }
            .toggleStyle(.switch)
            .accessibilityLabel("Use System Template")

            Spacer(minLength: 12)
        }
    }

    private var templateMenu: some View {
        Menu {
            ForEach(PromptTemplates.all) { template in
                Button {
                    title = template.title
                    promptText = template.promptText
                    useSystemInstructions = template.useSystemInstructions
                } label: {
                    Text(template.title)
                }
            }
        } label: {
            Label("Template", systemImage: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("Start with a template")
    }

    private var instructionsEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $promptText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 440)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(AppCardBackground(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if promptText.isEmpty {
                Text("Write prompt instructions")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .allowsHitTesting(false)
            }
        }
    }

    private var footer: some View {
        HStack {
            if canDeletePrompt {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Status.error)
            } else if canRestorePrompt, let editingPrompt {
                Button("Restore Default") {
                    onRestore?(editingPrompt)
                }
                .buttonStyle(.bordered)
            } else {
                Button("Cancel") {
                    dismissPanel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                if let savedPrompt = save() {
                    onSave(savedPrompt)
                }
                dismissPanel()
            } label: {
                Text(saveButtonTitle)
                    .frame(minWidth: 108)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaveDisabled)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Save this prompt and select it.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(Divider().opacity(0.5), alignment: .top)
    }

    private func deletePrompt() {
        guard let prompt = editingPrompt, canDeletePrompt else { return }
        onDelete?(prompt)
        dismissPanel()
    }

    private var deleteConfirmationMessage: String {
        guard let editingPrompt else { return "" }
        let usageCount = enhancementService.modeUsageCount(for: editingPrompt)
        if usageCount == 0 {
            return String(
                format: String(localized: "Are you sure you want to delete '%@'? This action cannot be undone."),
                editingPrompt.title
            )
        }

        return String(
            format: String(
                localized:
                    "'%@' is used by %lld modes. Deleting it will switch those modes to another available prompt. This action cannot be undone."
            ),
            editingPrompt.title,
            usageCount
        )
    }

    private func save() -> CustomPrompt? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPromptText = promptText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .add:
            return enhancementService.addPrompt(
                title: trimmedTitle,
                promptText: trimmedPromptText,
                useSystemInstructions: useSystemInstructions
            )
        case .edit(let prompt):
            let updatedPrompt = CustomPrompt(
                id: prompt.id,
                title: trimmedTitle,
                promptText: trimmedPromptText,
                useSystemInstructions: useSystemInstructions
            )
            enhancementService.updatePrompt(updatedPrompt)
            return updatedPrompt
        }
    }
}
