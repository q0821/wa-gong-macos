import SwiftUI
import UniformTypeIdentifiers

struct TranscribeCppModelCardView: View {
    let model: TranscribeCppModel
    @ObservedObject private var modelManager = TranscribeCppModelManager.shared
    @State private var importingTEA = false
    @State private var confirmingTEADeletion = false
    @State private var importError: String?
    private var isTEA: Bool { model.name == TranscribeCppModelCatalog.tea.modelName }

    private var isDownloaded: Bool { modelManager.isModelDownloaded(model) }
    private var isDownloading: Bool { modelManager.isModelDownloading(model) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(.labelColor))

                    Text("Experimental")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(red: 0.96, green: 0.79, blue: 0.63)))

                    Spacer()
                }

                HStack(spacing: 12) {
                    Label(model.language, systemImage: "globe")
                    Label(model.size, systemImage: "internaldrive")
                    if let speed = model.speed { HStack(spacing: 3) {
                        Text("Speed")
                        progressDotsWithNumber(value: speed * 10)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    }
                    if let accuracy = model.accuracy { HStack(spacing: 3) {
                        Text("Accuracy")
                        progressDotsWithNumber(value: accuracy * 10)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)

                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundColor(Color(.secondaryLabelColor))
                    .lineLimit(isTEA ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                progressSection
                if isTEA {
                    #if !arch(arm64)
                    Text("TEA requires an Apple silicon Mac.").font(.caption).foregroundStyle(.secondary)
                    #endif
                    Text("TEA: on-device recognition, up to 30 seconds. Optional cloud cleanup sends transcript text to your selected provider.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("MIT (TEA adaptation); Apache-2.0 (Qwen base). GGUF conversion by mukiwu.")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let error = modelManager.teaInstallError ?? importError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionSection
                .disabled(isTEA && !Self.supportsTEA)
        }
        .padding(16)
        .background(AppMaterialCardBackground())
        .fileImporter(isPresented: $importingTEA, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): Task { await modelManager.installTEA(source: url) }
            case .failure:
                importError = String(localized: "Could not open the selected TEA model file.")
            }
        }
        .confirmationDialog("Delete TEA model?", isPresented: $confirmingTEADeletion) {
            Button("Delete Model", role: .destructive) { modelManager.deleteModel(model) }
        }
    }

    private static var supportsTEA: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    @ViewBuilder
    private var progressSection: some View {
        if let status = modelManager.downloadStatus(for: model) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(status.message)
                        .lineLimit(1)

                    if status.isIndeterminate {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    }

                    Spacer()

                    Text(status.fractionCompleted, format: .percent.precision(.fractionLength(0)))
                        .fontDesign(.monospaced)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(.secondaryLabelColor))

                ProgressView(value: status.fractionCompleted)
                    .progressViewStyle(.linear)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .animation(.smooth, value: status.fractionCompleted)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 8) {
            if isDownloaded && !isDownloading {
                modelStatusPill("Downloaded", systemImage: "checkmark.circle")

                Menu {
                    Button(role: .destructive) {
                        if isTEA { confirmingTEADeletion = true }
                        else { modelManager.deleteModel(model) }
                    } label: {
                        Label("Delete Model", systemImage: "trash")
                    }

                    Button {
                        modelManager.showModelInFinder(model)
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            } else {
                if isTEA, isDownloading {
                    Button("Cancel") { modelManager.cancelTEAInstallation() }
                }
                if isTEA, !isDownloading {
                    Button("Import TEA Model…") { importingTEA = true; importError = nil }
                        .accessibilityLabel("Import downloaded TEA GGUF model")
                }
                Button {
                    Task { await modelManager.downloadModel(model) }
                } label: {
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(isDownloading ? "Downloading..." : "Download"))
                        Image(systemName: "arrow.down.circle")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.Accent.primary))
                }
                .buttonStyle(.plain)
                .disabled(isDownloading)
            }
        }
    }
}
