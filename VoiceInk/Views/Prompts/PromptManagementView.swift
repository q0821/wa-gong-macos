import SwiftUI

struct PromptManagementView: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService

    @State private var searchText = ""
    @State private var editorMode: PromptEditorView.Mode?
    @State private var editorID = UUID()
    @State private var promptPendingDeletion: CustomPrompt?
    @State private var isShowingDeleteConfirmation = false

    private var filteredPrompts: [CustomPrompt] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return enhancementService.allPrompts }

        return enhancementService.allPrompts.filter { prompt in
            prompt.title.localizedCaseInsensitiveContains(query)
                || prompt.promptText.localizedCaseInsensitiveContains(query)
        }
    }

    private var builtInPrompts: [CustomPrompt] {
        filteredPrompts.filter { PromptTemplates.isBuiltInPrompt(id: $0.id) }
    }

    private var customPrompts: [CustomPrompt] {
        filteredPrompts.filter { !PromptTemplates.isBuiltInPrompt(id: $0.id) }
    }

    private var isEditorOpen: Bool {
        editorMode != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    searchField

                    if filteredPrompts.isEmpty {
                        emptyState
                    } else {
                        promptSection(title: "Built-in Prompts", prompts: builtInPrompts)
                        promptSection(title: "Custom Prompts", prompts: customPrompts)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .sidePanel(
            isPresented: .init(
                get: { isEditorOpen },
                set: { if !$0 { closeEditor() } }
            ),
            dismissOnExitCommand: false
        ) {
            if let editorMode {
                PromptEditorView(
                    mode: editorMode,
                    onDismiss: closeEditor,
                    onSave: { _ in closeEditor() },
                    onDelete: deleteFromEditor,
                    onRestore: restorePrompt
                )
                .environmentObject(enhancementService)
                .id(editorID)
            }
        }
        .confirmationDialog(
            "Delete Prompt?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible,
            presenting: promptPendingDeletion
        ) { prompt in
            Button("Delete", role: .destructive) {
                enhancementService.deletePrompt(prompt)
                promptPendingDeletion = nil
                closeEditor()
            }
            Button("Cancel", role: .cancel) {
                promptPendingDeletion = nil
            }
        } message: { prompt in
            Text(deleteConfirmationMessage(for: prompt))
        }
    }

    private var header: some View {
        AppScreenHeader(
            title: "Prompts",
            infoMessage: "Prompts control how AI enhancement cleans up, rewrites, or responds to your transcription."
        ) {
            AppIconButton(
                systemName: "plus.circle.fill",
                help: "Add prompt"
            ) {
                openEditor(.add)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search prompts", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(AppCardBackground(cornerRadius: 10))
    }

    @ViewBuilder
    private func promptSection(title: LocalizedStringKey, prompts: [CustomPrompt]) -> some View {
        if !prompts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                LazyVStack(spacing: 10) {
                    ForEach(prompts) { prompt in
                        PromptManagementCard(
                            prompt: prompt,
                            usageCount: enhancementService.modeUsageCount(for: prompt),
                            isBuiltIn: PromptTemplates.isBuiltInPrompt(id: prompt.id),
                            onEdit: { openEditor(.edit(prompt)) },
                            onDuplicate: {
                                let duplicate = enhancementService.duplicatePrompt(prompt)
                                openEditor(.edit(duplicate))
                            },
                            onRestore: { restorePrompt(prompt) },
                            onDelete: { requestDeletion(prompt) }
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)

            Text("No Matching Prompts")
                .font(.headline)

            Text("Try a different search term or create a new prompt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }

    private func openEditor(_ mode: PromptEditorView.Mode) {
        editorID = UUID()
        editorMode = mode
    }

    private func closeEditor() {
        editorMode = nil
    }

    private func restorePrompt(_ prompt: CustomPrompt) {
        guard let restoredPrompt = enhancementService.restoreBuiltInPrompt(prompt) else { return }
        openEditor(.edit(restoredPrompt))
    }

    private func requestDeletion(_ prompt: CustomPrompt) {
        guard !PromptTemplates.isBuiltInPrompt(id: prompt.id) else { return }
        promptPendingDeletion = prompt
        isShowingDeleteConfirmation = true
    }

    private func deleteFromEditor(_ prompt: CustomPrompt) {
        enhancementService.deletePrompt(prompt)
        closeEditor()
    }

    private func deleteConfirmationMessage(for prompt: CustomPrompt) -> String {
        let usageCount = enhancementService.modeUsageCount(for: prompt)
        if usageCount == 0 {
            return String(
                format: String(localized: "Are you sure you want to delete '%@'? This action cannot be undone."),
                prompt.title
            )
        }

        return String(
            format: String(
                localized:
                    "'%@' is used by %lld modes. Deleting it will switch those modes to another available prompt. This action cannot be undone."
            ),
            prompt.title,
            usageCount
        )
    }
}

private struct PromptManagementCard: View {
    let prompt: CustomPrompt
    let usageCount: Int
    let isBuiltIn: Bool
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var canRestore: Bool {
        guard let template = PromptTemplates.template(for: prompt.id) else { return false }
        return prompt.title != template.title
            || prompt.promptText != template.promptText
            || prompt.useSystemInstructions != template.useSystemInstructions
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isBuiltIn ? "text.badge.checkmark" : "text.bubble")
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isBuiltIn ? AppTheme.Sidebar.prompts : Color.secondary)
                .frame(width: 34, height: 34)
                .background(AppCardBackground(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(prompt.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    if isBuiltIn {
                        PromptMetadataBadge(title: "Built-in")
                    }
                    if prompt.useSystemInstructions {
                        PromptMetadataBadge(title: "System Template")
                    }
                }

                Text(prompt.promptText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .lineSpacing(2)

                Text("Used by \(usageCount) modes")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            Menu {
                Button("Edit", action: onEdit)
                Button("Duplicate", action: onDuplicate)

                if isBuiltIn {
                    Button("Restore Default", action: onRestore)
                        .disabled(!canRestore)
                } else {
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Prompt actions")
            .accessibilityLabel("Prompt actions")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppCardBackground(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Duplicate", action: onDuplicate)
            if isBuiltIn {
                Button("Restore Default", action: onRestore)
                    .disabled(!canRestore)
            } else {
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }
}

private struct PromptMetadataBadge: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(AppTheme.Surface.control)
            .clipShape(Capsule())
    }
}
