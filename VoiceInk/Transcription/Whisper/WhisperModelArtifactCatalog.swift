import CryptoKit
import Foundation

struct WhisperRemoteArtifact: Sendable {
    let filename: String
    let size: Int64
    let sha256: String
    let repositoryRevision: String

    var downloadURL: URL {
        URL(
            string:
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/\(repositoryRevision)/\(filename)"
        )!
    }

    func integrityIsValid(at url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true,
            Int64(values?.fileSize ?? -1) == size,
            let handle = try? FileHandle(forReadingFrom: url)
        else {
            return false
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
            }
        } catch {
            return false
        }
        let actualSHA256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return actualSHA256 == sha256
    }
}

struct WhisperModelArtifact: Sendable {
    let name: String
    let repositoryRevision: String
    let modelFile: WhisperRemoteArtifact
    let coreMLArchive: WhisperRemoteArtifact?
}

enum WhisperModelArtifactCatalog {
    private static let revision = "5359861c739e955e79d9a303bcbc70fb988958b1"

    private static func file(_ filename: String, size: Int64, sha256: String) -> WhisperRemoteArtifact {
        WhisperRemoteArtifact(filename: filename, size: size, sha256: sha256, repositoryRevision: revision)
    }

    private static func model(
        _ name: String,
        modelSize: Int64,
        modelSHA256: String,
        coreMLSize: Int64? = nil,
        coreMLSHA256: String? = nil
    ) -> WhisperModelArtifact {
        let coreMLArchive: WhisperRemoteArtifact?
        if let coreMLSize, let coreMLSHA256 {
            coreMLArchive = file("\(name)-encoder.mlmodelc.zip", size: coreMLSize, sha256: coreMLSHA256)
        } else {
            coreMLArchive = nil
        }
        return WhisperModelArtifact(
            name: name,
            repositoryRevision: revision,
            modelFile: file("\(name).bin", size: modelSize, sha256: modelSHA256),
            coreMLArchive: coreMLArchive
        )
    }

    private static let artifacts: [String: WhisperModelArtifact] = {
        let values = [
            model(
                "ggml-tiny",
                modelSize: 77_691_713,
                modelSHA256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
                coreMLSize: 15_037_446,
                coreMLSHA256: "c88cbd2648e1f5415092bcf5256add463a0f19943e6938f46e8d4ffdebd47739"
            ),
            model(
                "ggml-tiny.en",
                modelSize: 77_704_715,
                modelSHA256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f",
                coreMLSize: 15_034_655,
                coreMLSHA256: "82b32eef73c94bb0c432a776a047b757d9525c26d84038a15d8798d7c8d1ee58"
            ),
            model(
                "ggml-base",
                modelSize: 147_951_465,
                modelSHA256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
                coreMLSize: 37_922_638,
                coreMLSHA256: "7e6ab77041942572f239b5b602f8aaa1c3ed29d73e3d8f20abea03a773541089"
            ),
            model(
                "ggml-base.en",
                modelSize: 147_964_211,
                modelSHA256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
                coreMLSize: 37_950_917,
                coreMLSHA256: "8cf860309e2449e2bdc8be834cf838ab2565747ecc8c0ef914ef5975115e192b"
            ),
            model(
                "ggml-large-v2",
                modelSize: 3_094_623_691,
                modelSHA256: "9a423fe4d40c82774b6af34115b8b935f34152246eb19e80e376071d3f999487",
                coreMLSize: 1_174_643_458,
                coreMLSHA256: "c65d28737f51d09dff3b9da9d26c2ab6f5d82857c9b049ce383d64c2502a5541"
            ),
            model(
                "ggml-large-v3",
                modelSize: 3_095_033_483,
                modelSHA256: "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2",
                coreMLSize: 1_175_711_232,
                coreMLSHA256: "47837be7594a29429ec08620043390c4d6d467f8bd362df09e9390ace76a55a4"
            ),
            model(
                "ggml-large-v3-turbo",
                modelSize: 1_624_555_275,
                modelSHA256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
                coreMLSize: 1_173_393_014,
                coreMLSHA256: "84bedfe895bd7b5de6e8e89a0803dfc5addf8c0c5bc4c937451716bf7cf7988a"
            ),
            model(
                "ggml-large-v3-turbo-q5_0",
                modelSize: 574_041_195,
                modelSHA256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
            ),
        ]
        return Dictionary(uniqueKeysWithValues: values.map { ($0.name, $0) })
    }()

    static func artifact(for modelName: String) -> WhisperModelArtifact? {
        artifacts[modelName]
    }
}
