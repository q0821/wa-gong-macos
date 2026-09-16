import Foundation
import Testing
@testable import VoiceInk

@Suite("File boundary security")
struct FileBoundarySecurityTests {
    @Test("Bounded file reads reject symbolic links and oversized files")
    func boundedFileReadRejectsUnsafeInputs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.json")
        let link = directory.appendingPathComponent("link.json")
        try Data("12345".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: Error.self) {
            try BoundedRegularFileReader.load(link, maximumBytes: 10)
        }
        #expect(throws: Error.self) {
            try BoundedRegularFileReader.load(target, maximumBytes: 4)
        }
        #expect(try BoundedRegularFileReader.load(target, maximumBytes: 5) == Data("12345".utf8))
    }

    @Test("Whisper model imports reject symbolic links")
    func modelImportRejectsSymbolicLinks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.bin")
        let link = directory.appendingPathComponent("link.bin")
        try Data([0x01]).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: Error.self) {
            try WhisperModelImportPolicy.validate(link)
        }
    }

    @Test("Whisper model imports require a pinned catalog artifact")
    func modelImportRequiresPinnedCatalogArtifact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = directory.appendingPathComponent("invalid.bin")
        let forgedHeader = directory.appendingPathComponent("untrusted-custom.bin")
        try Data([0x00, 0x00, 0x00, 0x00]).write(to: invalid)
        try Data([0x6c, 0x6d, 0x67, 0x67]).write(to: forgedHeader)

        #expect(throws: Error.self) {
            try WhisperModelImportPolicy.validate(invalid)
        }
        #expect(throws: Error.self) {
            try WhisperModelImportPolicy.validateTrustedArtifact(named: "untrusted-custom", at: forgedHeader)
        }
    }

    @Test("Whisper PCM decoding rejects truncated headers and odd payloads")
    func pcmStructureValidation() throws {
        #expect(throws: Error.self) {
            try WhisperTranscriptionService.decodePCMSamples(Data(repeating: 0, count: 43))
        }

        var odd = Data("RIFF".utf8)
        odd.append(Data(repeating: 0, count: 4))
        odd.append(Data("WAVE".utf8))
        odd.append(Data(repeating: 0, count: 33))
        #expect(throws: Error.self) {
            try WhisperTranscriptionService.decodePCMSamples(odd)
        }
    }
}
