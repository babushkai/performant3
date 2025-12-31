import Foundation
import UniformTypeIdentifiers

// MARK: - Export/Import Service

/// Service for exporting and importing models, runs, and experiments
actor ExportImportService {
    static let shared = ExportImportService()

    private init() {}

    // MARK: - Export Bundle

    struct ExportBundle: Codable {
        let version: String
        let exportDate: Date
        let exportedBy: String
        var models: [MLModel]
        var runs: [TrainingRun]
        var experiments: [ExperimentExport]?
        var modelVersions: [ModelVersion]?
        var metadata: [String: String]

        init(
            models: [MLModel] = [],
            runs: [TrainingRun] = [],
            experiments: [ExperimentExport]? = nil,
            modelVersions: [ModelVersion]? = nil,
            metadata: [String: String] = [:]
        ) {
            self.version = "1.0"
            self.exportDate = Date()
            self.exportedBy = "Performant3"
            self.models = models
            self.runs = runs
            self.experiments = experiments
            self.modelVersions = modelVersions
            self.metadata = metadata
        }
    }

    struct ExperimentExport: Codable {
        let id: String
        let name: String
        let description: String?
        let hypothesis: String?
        let runIds: [String]
        let createdAt: Date
        let status: String
        let tags: [String]
    }

    // MARK: - Export Format

    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case archive = "Archive (.p3export)"
        case safetensors = "SafeTensors"

        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .archive: return "p3export"
            case .safetensors: return "safetensors"
            }
        }

        var contentType: UTType {
            switch self {
            case .json: return .json
            case .archive, .safetensors: return .data
            }
        }
    }

    // MARK: - Export Functions

    /// Export a single model
    func exportModel(
        _ model: MLModel,
        format: ExportFormat,
        includeCheckpoints: Bool,
        includeVersions: Bool,
        to url: URL
    ) async throws {
        switch format {
        case .json:
            try await exportModelAsJSON(model, to: url)

        case .archive:
            try await exportModelAsArchive(
                model,
                includeCheckpoints: includeCheckpoints,
                includeVersions: includeVersions,
                to: url
            )

        case .safetensors:
            try await exportModelAsSafetensors(model, to: url)
        }
    }

    private func exportModelAsJSON(_ model: MLModel, to url: URL) async throws {
        let bundle = ExportBundle(models: [model])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(bundle)
        try data.write(to: url)
    }

    private func exportModelAsArchive(
        _ model: MLModel,
        includeCheckpoints: Bool,
        includeVersions: Bool,
        to url: URL
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create manifest
        var bundle = ExportBundle(models: [model])
        bundle.metadata["includeCheckpoints"] = "\(includeCheckpoints)"
        bundle.metadata["includeVersions"] = "\(includeVersions)"

        // Add versions if requested
        if includeVersions {
            let versions = await ModelVersionManager.shared.getVersions(for: model.id)
            bundle.modelVersions = versions
        }

        // Write manifest
        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(bundle)
        try manifestData.write(to: manifestURL)

        // Copy model weights if available
        if let filePath = model.filePath, includeCheckpoints {
            let sourceURL = URL(fileURLWithPath: filePath)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let weightsDir = tempDir.appendingPathComponent("weights")
                try FileManager.default.createDirectory(at: weightsDir, withIntermediateDirectories: true)
                let destURL = weightsDir.appendingPathComponent(sourceURL.lastPathComponent)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        }

        // Create ZIP archive
        try createZipArchive(from: tempDir, to: url)
    }

    private func exportModelAsSafetensors(_ model: MLModel, to url: URL) async throws {
        guard let filePath = model.filePath else {
            throw ExportError.noWeightsFile
        }

        let sourceURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ExportError.noWeightsFile
        }

        try FileManager.default.copyItem(at: sourceURL, to: url)
    }

    /// Export multiple training runs
    func exportRuns(_ runs: [TrainingRun], to url: URL) async throws {
        let bundle = ExportBundle(runs: runs)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(bundle)
        try data.write(to: url)
    }

    /// Export an experiment with its runs
    func exportExperiment(
        experimentId: String,
        includeRuns: Bool,
        includeCheckpoints: Bool,
        to url: URL
    ) async throws {
        let repo = ExperimentRepository()
        guard let experiment = try await repo.findById(experimentId) else {
            throw ExportError.experimentNotFound
        }

        var runs: [TrainingRun] = []
        if includeRuns {
            let runRepo = TrainingRunRepository()
            runs = try await runRepo.findByExperiment(experimentId)
        }

        let experimentExport = ExperimentExport(
            id: experiment.id,
            name: experiment.name,
            description: experiment.description,
            hypothesis: nil,
            runIds: runs.map { $0.id },
            createdAt: Date(timeIntervalSince1970: experiment.createdAt),
            status: "active",
            tags: []
        )

        let bundle = ExportBundle(
            runs: runs,
            experiments: [experimentExport]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(bundle)
        try data.write(to: url)
    }

    /// Export all data
    func exportAll(
        models: [MLModel],
        runs: [TrainingRun],
        to url: URL
    ) async throws {
        var bundle = ExportBundle(models: models, runs: runs)

        // Add all model versions
        var allVersions: [ModelVersion] = []
        for model in models {
            let versions = await ModelVersionManager.shared.getVersions(for: model.id)
            allVersions.append(contentsOf: versions)
        }
        bundle.modelVersions = allVersions

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(bundle)
        try data.write(to: url)
    }

    // MARK: - Import Functions

    /// Import a bundle file
    func importBundle(from url: URL) async throws -> ExportBundle {
        let pathExtension = url.pathExtension.lowercased()

        switch pathExtension {
        case "p3export":
            return try await importArchive(from: url)
        case "json":
            return try await importJSON(from: url)
        default:
            throw ExportError.unsupportedFormat
        }
    }

    private func importJSON(from url: URL) async throws -> ExportBundle {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportBundle.self, from: data)
    }

    private func importArchive(from url: URL) async throws -> ExportBundle {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        try extractZipArchive(from: url, to: tempDir)

        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ExportError.invalidArchive
        }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var bundle = try decoder.decode(ExportBundle.self, from: data)

        // Copy weights to app support directory if present
        let weightsDir = tempDir.appendingPathComponent("weights")
        if FileManager.default.fileExists(atPath: weightsDir.path) {
            let modelsDir = await StorageManager.shared.modelsDirectory
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

            let contents = try FileManager.default.contentsOfDirectory(at: weightsDir, includingPropertiesForKeys: nil)
            for file in contents {
                let destURL = modelsDir.appendingPathComponent(file.lastPathComponent)
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: file, to: destURL)

                // Update model file path
                if let index = bundle.models.firstIndex(where: { $0.filePath?.contains(file.lastPathComponent) == true }) {
                    bundle.models[index].filePath = destURL.path
                }
            }
        }

        return bundle
    }

    /// Import a model from SafeTensors file
    func importSafetensors(from url: URL, name: String) async throws -> MLModel {
        let modelsDir = await StorageManager.shared.modelsDirectory
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let destURL = modelsDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: url, to: destURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
        let fileSize = attrs[FileAttributeKey.size] as? Int64 ?? 0

        return MLModel(
            name: name,
            framework: .mlx,
            status: .ready,
            accuracy: 0,
            fileSize: fileSize,
            filePath: destURL.path,
            metadata: ["importedFrom": url.path]
        )
    }

    // MARK: - Archive Helpers

    private func createZipArchive(from directory: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", destination.path, "."]
        process.currentDirectoryURL = directory

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExportError.archiveCreationFailed
        }
    }

    private func extractZipArchive(from archive: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", archive.path, "-d", destination.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExportError.archiveExtractionFailed
        }
    }

    // MARK: - Validation

    /// Validate an export bundle
    func validateBundle(_ bundle: ExportBundle) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Check version compatibility
        if bundle.version != "1.0" {
            issues.append(ValidationIssue(
                severity: .warning,
                message: "Bundle version \(bundle.version) may not be fully compatible"
            ))
        }

        // Check for missing model references
        let modelIds = Set(bundle.models.map { $0.id })
        for run in bundle.runs {
            if !modelIds.contains(run.modelId) {
                issues.append(ValidationIssue(
                    severity: .warning,
                    message: "Run '\(run.name)' references unknown model '\(run.modelId)'"
                ))
            }
        }

        // Check for missing files
        for model in bundle.models {
            if let path = model.filePath, !FileManager.default.fileExists(atPath: path) {
                issues.append(ValidationIssue(
                    severity: .info,
                    message: "Model '\(model.name)' weight file not found at \(path)"
                ))
            }
        }

        return issues
    }

    struct ValidationIssue {
        enum Severity {
            case error
            case warning
            case info
        }

        let severity: Severity
        let message: String
    }
}

// MARK: - Export Errors

enum ExportError: Error, LocalizedError {
    case noWeightsFile
    case experimentNotFound
    case archiveCreationFailed
    case archiveExtractionFailed
    case invalidArchive
    case unsupportedFormat
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWeightsFile:
            return "Model has no weight file to export"
        case .experimentNotFound:
            return "Experiment not found"
        case .archiveCreationFailed:
            return "Failed to create export archive"
        case .archiveExtractionFailed:
            return "Failed to extract import archive"
        case .invalidArchive:
            return "Invalid or corrupted archive file"
        case .unsupportedFormat:
            return "Unsupported file format"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        }
    }
}

// MARK: - Export Sheet View

import SwiftUI

struct ExportOptionsSheet: View {
    let model: MLModel?
    let runs: [TrainingRun]?
    let onExport: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportImportService.ExportFormat = .json
    @State private var includeCheckpoints = true
    @State private var includeVersions = true
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Options")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Options
            Form {
                Section("Format") {
                    Picker("Export Format", selection: $selectedFormat) {
                        ForEach(ExportImportService.ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                if selectedFormat == .archive {
                    Section("Options") {
                        Toggle("Include model checkpoints", isOn: $includeCheckpoints)
                        Toggle("Include version history", isOn: $includeVersions)
                    }
                }

                Section("Summary") {
                    if let model = model {
                        LabeledContent("Model", value: model.name)
                    }
                    if let runs = runs {
                        LabeledContent("Training Runs", value: "\(runs.count)")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Button("Export...") {
                    showExportPanel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
    }

    private func showExportPanel() {
        let panel = NSSavePanel()
        panel.title = "Export"
        panel.allowedContentTypes = [selectedFormat.contentType]

        var fileName = "export"
        if let model = model {
            fileName = model.name.replacingOccurrences(of: " ", with: "_")
        }
        panel.nameFieldStringValue = "\(fileName).\(selectedFormat.fileExtension)"

        if panel.runModal() == .OK, let url = panel.url {
            performExport(to: url)
        }
    }

    private func performExport(to url: URL) {
        isExporting = true

        Task {
            do {
                if let model = model {
                    try await ExportImportService.shared.exportModel(
                        model,
                        format: selectedFormat,
                        includeCheckpoints: includeCheckpoints,
                        includeVersions: includeVersions,
                        to: url
                    )
                } else if let runs = runs {
                    try await ExportImportService.shared.exportRuns(runs, to: url)
                }

                await MainActor.run {
                    onExport(url)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    // Show error
                }
            }
        }
    }
}
