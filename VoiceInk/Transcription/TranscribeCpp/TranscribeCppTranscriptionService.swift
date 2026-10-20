import Foundation

/// Routes transcribe.cpp-backed models to their model-specific service.
final class TranscribeCppTranscriptionService: TranscriptionService, @unchecked Sendable {
    private let cohereService = CohereTranscriptionService()
    private let teaService = TEATranscriptionService()

    func loadModel(for model: TranscribeCppModel) async throws {
        switch model.name {
        case TranscribeCppModelCatalog.tea.modelName:
            try await TEARuntimeManager.shared.prepare()
        case TranscribeCppModelCatalog.cohereTranscribe.modelName:
            try await cohereService.loadModel(for: model)
        default:
            throw unsupportedModelError(model.name)
        }
    }

    func transcribe(
        audioURL: URL,
        model: any TranscriptionModel,
        context: TranscriptionRequestContext
    ) async throws -> String {
        guard let transcribeCppModel = model as? TranscribeCppModel else {
            throw NSError(
                domain: "TranscribeCppTranscriptionService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported transcription model"]
            )
        }

        switch transcribeCppModel.name {
        case TranscribeCppModelCatalog.tea.modelName:
            return try await teaService.transcribe(audioURL: audioURL, model: model, context: context)
        case TranscribeCppModelCatalog.cohereTranscribe.modelName:
            return try await cohereService.transcribe(
                audioURL: audioURL,
                model: transcribeCppModel,
                context: context
            )
        default:
            throw unsupportedModelError(transcribeCppModel.name)
        }
    }

    func cleanup() {
        teaService.cleanup()
        cohereService.cleanup()
    }

    private func unsupportedModelError(_ modelName: String) -> NSError {
        NSError(
            domain: "TranscribeCppTranscriptionService",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "No transcribe.cpp service is registered for \(modelName)"]
        )
    }
}
