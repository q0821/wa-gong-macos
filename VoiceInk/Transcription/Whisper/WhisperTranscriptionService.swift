import AVFoundation
import Foundation
import os

class WhisperTranscriptionService: TranscriptionService {

    static let maximumPCMBytes = 230_400_044

    private var whisperContext: WhisperContext?
    private let logger = Logger(subsystem: "com.jackie-yeh.wagong", category: "WhisperTranscriptionService")
    private let modelsDirectory: URL
    private weak var modelProvider: (any WhisperModelProvider)?

    init(modelsDirectory: URL, modelProvider: (any WhisperModelProvider)? = nil) {
        self.modelsDirectory = modelsDirectory
        self.modelProvider = modelProvider
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws
        -> String
    {
        guard model.provider == .whisper else {
            throw WaGongEngineError.modelLoadFailed
        }

        logger.notice("Initiating local transcription for model: \(model.displayName, privacy: .public)")

        // Check if the required model is already loaded in the model provider
        if let provider = modelProvider,
            await provider.isModelLoaded,
            let loadedContext = await provider.whisperContext,
            await provider.loadedWhisperModel?.name == model.name
        {

            logger.notice("Using already loaded model: \(model.name, privacy: .public)")
            whisperContext = loadedContext
        } else {
            // Resolve the on-disk URL using the provider's availableModels (covers imports)
            let resolvedURL: URL? = await modelProvider?.availableModels.first(where: { $0.name == model.name })?.url
            guard let modelURL = resolvedURL, FileManager.default.fileExists(atPath: modelURL.path) else {
                logger.error("❌ Model file not found for: \(model.name, privacy: .public)")
                throw WaGongEngineError.modelLoadFailed
            }

            logger.notice("Loading model: \(model.name, privacy: .public)")
            do {
                if let artifact = WhisperModelArtifactCatalog.artifact(for: model.name) {
                    let isValid = await Task.detached(priority: .utility) {
                        artifact.modelFile.integrityIsValid(at: modelURL)
                    }.value
                    try Task.checkCancellation()
                    guard isValid else { throw WaGongEngineError.modelLoadFailed }
                }
                whisperContext = try await WhisperContext.createContext(path: modelURL.path)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.error("❌ Failed to load model: \(model.name, privacy: .public) - \(error, privacy: .public)")
                throw WaGongEngineError.modelLoadFailed
            }
        }

        guard let whisperContext = whisperContext else {
            logger.error("❌ Cannot transcribe: Model could not be loaded")
            throw WaGongEngineError.modelLoadFailed
        }

        // Read audio data
        let data = try readAudioSamples(audioURL)

        // Set prompt
        await whisperContext.setLanguage(
            context.language.map(LanguageDictionary.whisperLanguageCode)
        )
        await whisperContext.setPrompt(context.prompt ?? "")

        // Transcribe
        let success = await whisperContext.fullTranscribe(samples: data)

        guard success else {
            logger.error("❌ Core transcription engine failed (whisper_full).")
            throw WaGongEngineError.whisperCoreFailed
        }

        let text = await whisperContext.getTranscription()

        logger.notice("Whisper transcription completed successfully.")

        // Only release resources if we created a new context (not using the shared one)
        if await modelProvider?.whisperContext !== whisperContext {
            await whisperContext.releaseResources()
            self.whisperContext = nil
        }

        return text
    }

    private func readAudioSamples(_ url: URL) throws -> [Float] {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumPCMBytes else { throw CocoaError(.fileReadTooLarge) }
        return try Self.decodePCMSamples(Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func decodePCMSamples(_ data: Data) throws -> [Float] {
        guard data.count >= 44,
              data.count <= maximumPCMBytes,
              data.prefix(4) == Data("RIFF".utf8),
              data[8..<12] == Data("WAVE".utf8),
              (data.count - 44).isMultiple(of: 2) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var floats: [Float] = []
        floats.reserveCapacity((data.count - 44) / 2)
        var offset = 44
        while offset < data.count {
            let value = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            let sample = Int16(bitPattern: value)
            floats.append(max(-1.0, min(Float(sample) / 32767.0, 1.0)))
            offset += 2
        }
        return floats
    }
}
