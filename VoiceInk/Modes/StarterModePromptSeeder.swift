import Foundation

enum StarterModePromptSeeder {
    static func hasPrompts(
        for kinds: [StarterModeKind],
        in prompts: [CustomPrompt]
    ) -> Bool {
        requiredPromptIds(for: kinds).allSatisfy { promptId in
            prompts.contains { $0.id == promptId }
        }
    }

    static func ensurePrompts(
        for kinds: [StarterModeKind],
        in prompts: [CustomPrompt]
    ) -> (prompts: [CustomPrompt], didChange: Bool) {
        let requiredPromptIds = requiredPromptIds(for: kinds)
        guard !requiredPromptIds.isEmpty else {
            return (prompts, false)
        }

        var updatedPrompts = prompts.filter { prompt in
            !PromptTemplates.retiredBuiltInPrompts.contains(prompt)
        }
        var didChange = updatedPrompts.count != prompts.count

        if let legacyDefaultIndex = updatedPrompts.firstIndex(where: {
            $0.id == PromptTemplates.defaultPromptId && $0.title == "Default"
        }) {
            let legacyPrompt = updatedPrompts[legacyDefaultIndex]
            updatedPrompts[legacyDefaultIndex] = CustomPrompt(
                id: legacyPrompt.id,
                title: "智慧模式",
                promptText: legacyPrompt.promptText,
                useSystemInstructions: legacyPrompt.useSystemInstructions
            )
            didChange = true
        }

        for index in updatedPrompts.indices {
            if let migratedPrompt = PromptTemplates.migratedBuiltInPrompt(updatedPrompts[index]) {
                updatedPrompts[index] = migratedPrompt
                didChange = true
            }
        }

        for promptId in requiredPromptIds where !updatedPrompts.contains(where: { $0.id == promptId }) {
            guard let seedPrompt = PromptTemplates.seedPrompts.first(where: { $0.id == promptId }) else {
                continue
            }

            updatedPrompts.append(seedPrompt)
            didChange = true
        }

        return (updatedPrompts, didChange)
    }

    private static func requiredPromptIds(for kinds: [StarterModeKind]) -> [UUID] {
        var seenPromptIds = Set<UUID>()
        var promptIds = [
            PromptTemplates.defaultPromptId,
            PromptTemplates.chatPromptId,
        ]
        seenPromptIds.formUnion(promptIds)

        promptIds.append(contentsOf: kinds.compactMap { kind in
            guard let promptId = StarterModeCatalog.templates.first(where: { $0.kind == kind })?.promptId,
                !seenPromptIds.contains(promptId)
            else {
                return nil
            }

            seenPromptIds.insert(promptId)
            return promptId
        })

        return promptIds
    }
}
