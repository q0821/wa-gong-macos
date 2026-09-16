import AppKit
import Foundation
import SwiftData

class WaGongCSVExportService {

    func exportTranscriptionsToCSV(transcriptions: [Transcription]) {
        let csvString = generateCSV(for: transcriptions)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "Wa-Gong-transcription.csv"

        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                do {
                    try csvString.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Error writing CSV file: \(error)")
                }
            }
        }
    }

    private func generateCSV(for transcriptions: [Transcription]) -> String {
        var csvString =
            "Original Transcript,Enhanced Transcript,Enhancement Model,Prompt Name,Transcription Model,Mode,Enhancement Time,Transcription Time,Timestamp,Duration\n"

        for transcription in transcriptions {
            let originalText = Self.escapeCSVString(transcription.text)
            let enhancedText = Self.escapeCSVString(transcription.enhancedText ?? "")
            let enhancementModel = Self.escapeCSVString(transcription.aiEnhancementModelName ?? "")
            let promptName = Self.escapeCSVString(transcription.promptName ?? "")
            let transcriptionModel = Self.escapeCSVString(transcription.transcriptionModelName ?? "")
            let mode = Self.escapeCSVString(transcription.modeName ?? "")
            let enhancementTime = transcription.enhancementDuration ?? 0
            let transcriptionTime = transcription.transcriptionDuration ?? 0
            let timestamp = transcription.timestamp.ISO8601Format()
            let duration = transcription.duration

            let row =
                "\(originalText),\(enhancedText),\(enhancementModel),\(promptName),\(transcriptionModel),\(mode),\(enhancementTime),\(transcriptionTime),\(timestamp),\(duration)\n"
            csvString.append(row)
        }

        return csvString
    }

    static func escapeCSVString(_ string: String) -> String {
        let formulaNeutralized = neutralizeSpreadsheetFormula(in: string)
        let escapedString = formulaNeutralized.replacingOccurrences(of: "\"", with: "\"\"")
        if escapedString.contains(",") || escapedString.contains("\n") {
            return "\"\(escapedString)\""
        }
        return escapedString
    }

    private static func neutralizeSpreadsheetFormula(in string: String) -> String {
        let ignored = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
        guard let first = string.unicodeScalars.first(where: { !ignored.contains($0) }),
            "=+-@".unicodeScalars.contains(first)
        else {
            return string
        }
        return "'\(string)"
    }

}
