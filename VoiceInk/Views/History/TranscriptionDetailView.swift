import SwiftUI

struct TranscriptionDetailView: View {
    let transcription: Transcription
    var onInfoTap: (() -> Void)?
    @State private var correctionSource: VocabularyLearningService.Source?
    @State private var showCorrection = false

    private var hasAudioFile: Bool {
        if let urlString = transcription.audioFileURL,
            let url = URL(string: urlString),
            FileManager.default.fileExists(atPath: url.path)
        {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 16) {
                    if let raw = transcription.rawTranscript {
                        MessageBubble(label: "Raw recognition", text: raw, isEnhanced: false, isRaw: true)
                    } else {
                        Text("Raw recognition was not recorded for this entry.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let diagnostics = transcription.vocabularyDiagnostics {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Speech vocabulary: \(diagnostics.recognitionCount)")
                            Text(diagnostics.recognitionStatus.label)
                            Text(diagnostics.recognitionPath == "streaming" ? "Streaming recognition" : "File recognition")
                            Text("Text vocabulary: \(diagnostics.textCount)")
                            Text(diagnostics.textStatus.label)
                            if diagnostics.conflictingRules {
                                Text("Conflicting replacement rules were not applied.")
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    MessageBubble(
                        label: "After local processing",
                        text: transcription.text,
                        isEnhanced: false
                    )

                    if let enhancedText = transcription.enhancedText {
                        MessageBubble(
                            label: "Enhanced",
                            text: enhancedText,
                            isEnhanced: true
                        )
                    }
                    if transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
                        Button("Correct and Remember") {
                            correctionSource = .init(transcription)
                            showCorrection = true
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }

            if hasAudioFile, let urlString = transcription.audioFileURL,
                let url = URL(string: urlString)
            {
                VStack(spacing: 0) {
                    Divider()

                    AudioPlayerView(url: url, transcription: transcription, onInfoTap: onInfoTap)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .fill(AppTheme.Surface.materialCard)
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                        .strokeBorder(AppTheme.Border.card, lineWidth: 1)
                                }
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 12)
        .sheet(isPresented: $showCorrection, onDismiss: { correctionSource = nil }) {
            if let correctionSource {
                VocabularyCorrectionSheet(transcriptionID: correctionSource.id, source: correctionSource)
            }
        }
        .onChange(of: transcription.id) { _, _ in
            showCorrection = false
            correctionSource = nil
        }
    }
}

private struct MessageBubble: View {
    let label: LocalizedStringKey
    let text: String
    let isEnhanced: Bool
    var isRaw = false

    var body: some View {
        HStack(alignment: .bottom) {
            if isEnhanced { Spacer(minLength: 60) }

            VStack(alignment: isEnhanced ? .leading : .trailing, spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AppTheme.Text.muted)
                    .padding(.horizontal, 12)

                ScrollView {
                    if isRaw {
                        Text(text)
                            .font(.system(size: 14))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    } else {
                        MarkdownContentView(
                            text,
                            fontSize: 14,
                            foregroundColor: AppTheme.Text.primary,
                            alignment: isEnhanced ? .leading : .trailing
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
                .frame(maxHeight: 350)
                .background {
                    if isEnhanced {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .fill(AppTheme.Surface.subtle)
                            .overlay {
                                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                    .strokeBorder(AppTheme.Border.tint, lineWidth: 1)
                            }
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .fill(AppTheme.Surface.materialCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                    .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
                            )
                    }
                }
                .hoverCopyButton(textToCopy: text)
            }

            if !isEnhanced { Spacer(minLength: 60) }
        }
    }

}
