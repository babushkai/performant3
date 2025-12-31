import SwiftUI

/// View for exporting trained models to various formats
struct ModelExportView: View {
    let modelPath: String
    let modelName: String
    let architecture: ArchitectureType

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ModelExportService.ExportFormat = .onnx
    @State private var outputDirectory: String = ""
    @State private var isExporting = false
    @State private var exportProgress: String = ""
    @State private var exportResult: ModelExportService.ExportResult?
    @State private var exportError: String?
    @State private var showFilePicker = false

    private let exportService = ModelExportService.shared

    var supportedFormats: [ModelExportService.ExportFormat] {
        ModelExportService.ExportFormat.allCases.filter { format in
            switch architecture {
            case .yolov8:
                return true
            case .mlp, .cnn, .resnet, .transformer:
                return [.onnx, .pytorch].contains(format)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Export Model")
                        .font(.headline)
                    Text(modelName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Content
            Form {
                Section("Source") {
                    LabeledContent("Model Path") {
                        Text(modelPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    LabeledContent("Architecture") {
                        Text(architecture.displayName)
                    }
                }

                Section("Export Format") {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(supportedFormats) { format in
                            VStack(alignment: .leading) {
                                Text(format.rawValue)
                                Text(format.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(format)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Output") {
                    HStack {
                        TextField("Output Directory", text: $outputDirectory)
                            .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            showFilePicker = true
                        }
                    }

                    if !outputDirectory.isEmpty {
                        let outputFile = "\(outputDirectory)/\(modelName).\(selectedFormat.fileExtension)"
                        LabeledContent("Output File") {
                            Text(outputFile)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if isExporting {
                    Section("Progress") {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView()
                            Text(exportProgress)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let result = exportResult {
                    Section("Export Complete") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Successfully exported!")
                            }

                            LabeledContent("Output") {
                                Text(result.outputPath)
                                    .font(.caption)
                            }

                            LabeledContent("Size") {
                                Text(formatBytes(result.fileSize))
                            }

                            LabeledContent("Time") {
                                Text(String(format: "%.1f seconds", result.exportTime))
                            }

                            HStack {
                                Button("Show in Finder") {
                                    NSWorkspace.shared.selectFile(result.outputPath, inFileViewerRootedAtPath: "")
                                }

                                Button("Done") {
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }

                if let error = exportError {
                    Section("Error") {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()

                if exportResult == nil {
                    Button("Export") {
                        performExport()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting || outputDirectory.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                outputDirectory = url.path
            }
        }
        .onAppear {
            // Default to same directory as model
            let modelURL = URL(fileURLWithPath: modelPath)
            outputDirectory = modelURL.deletingLastPathComponent().path
        }
    }

    private func performExport() {
        isExporting = true
        exportError = nil
        exportResult = nil

        Task {
            do {
                let result = try await exportService.exportYOLOv8(
                    modelPath: modelPath,
                    to: selectedFormat,
                    outputDir: outputDirectory
                ) { progress in
                    Task { @MainActor in
                        exportProgress = progress
                    }
                }

                await MainActor.run {
                    exportResult = result
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Quick Export Button

struct QuickExportButton: View {
    let modelPath: String
    let modelName: String
    let architecture: ArchitectureType

    @State private var showExportSheet = false

    var body: some View {
        Button {
            showExportSheet = true
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .sheet(isPresented: $showExportSheet) {
            ModelExportView(
                modelPath: modelPath,
                modelName: modelName,
                architecture: architecture
            )
        }
    }
}

// MARK: - Export Format Selector

struct ExportFormatSelector: View {
    @Binding var selectedFormat: ModelExportService.ExportFormat
    let supportedFormats: [ModelExportService.ExportFormat]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(supportedFormats) { format in
                Button {
                    selectedFormat = format
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: iconForFormat(format))
                            .font(.title2)
                        Text(format.rawValue)
                            .font(.caption)
                    }
                    .frame(width: 80, height: 60)
                    .background(selectedFormat == format ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedFormat == format ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func iconForFormat(_ format: ModelExportService.ExportFormat) -> String {
        switch format {
        case .coreml: return "apple.logo"
        case .onnx: return "cube"
        case .pytorch: return "flame"
        case .torchscript: return "doc.text"
        }
    }
}

#Preview {
    ModelExportView(
        modelPath: "/path/to/model.pt",
        modelName: "yolov8n-custom",
        architecture: .yolov8
    )
}
