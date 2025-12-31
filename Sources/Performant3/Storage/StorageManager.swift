import Foundation
import AppKit

actor StorageManager {
    static let shared = StorageManager()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var baseURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Performant3", isDirectory: true)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }

    private var modelsURL: URL { baseURL.appendingPathComponent("models.json") }
    private var runsURL: URL { baseURL.appendingPathComponent("runs.json") }
    private var datasetsURL: URL { baseURL.appendingPathComponent("datasets.json") }
    private var settingsURL: URL { baseURL.appendingPathComponent("settings.json") }
    private var inferenceHistoryURL: URL { baseURL.appendingPathComponent("inference_history.json") }

    var modelsDirectory: URL {
        let dir = baseURL.appendingPathComponent("Models", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var datasetsDirectory: URL {
        let dir = baseURL.appendingPathComponent("Datasets", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var logsDirectory: URL {
        let dir = baseURL.appendingPathComponent("Logs", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Models

    func loadModels() throws -> [MLModel] {
        guard fileManager.fileExists(atPath: modelsURL.path) else { return [] }
        let data = try Data(contentsOf: modelsURL)
        return try decoder.decode([MLModel].self, from: data)
    }

    func saveModels(_ models: [MLModel]) throws {
        let data = try encoder.encode(models)
        try data.write(to: modelsURL, options: .atomic)
    }

    func importModel(from sourceURL: URL, name: String, framework: MLFramework) throws -> MLModel {
        let fileName = "\(UUID().uuidString).\(sourceURL.pathExtension)"
        let destinationURL = modelsDirectory.appendingPathComponent(fileName)

        // Copy file to models directory
        if sourceURL.startAccessingSecurityScopedResource() {
            defer { sourceURL.stopAccessingSecurityScopedResource() }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        // Get file size
        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let size = attributes[.size] as? Int64 ?? 0

        return MLModel(
            name: name,
            framework: framework,
            status: .ready,
            fileSize: size,
            filePath: destinationURL.path
        )
    }

    func deleteModelFile(_ model: MLModel) throws {
        if let path = model.filePath {
            try? fileManager.removeItem(atPath: path)
        }
    }

    func exportModel(_ model: MLModel, to destinationURL: URL) throws {
        guard let sourcePath = model.filePath else {
            throw StorageError.fileNotFound
        }
        try fileManager.copyItem(atPath: sourcePath, toPath: destinationURL.path)
    }

    // MARK: - Runs

    func loadRuns() throws -> [TrainingRun] {
        guard fileManager.fileExists(atPath: runsURL.path) else { return [] }
        let data = try Data(contentsOf: runsURL)
        return try decoder.decode([TrainingRun].self, from: data)
    }

    func saveRuns(_ runs: [TrainingRun]) throws {
        let data = try encoder.encode(runs)
        try data.write(to: runsURL, options: .atomic)
    }

    // MARK: - Datasets

    func loadDatasets() throws -> [Dataset] {
        guard fileManager.fileExists(atPath: datasetsURL.path) else { return [] }
        let data = try Data(contentsOf: datasetsURL)
        return try decoder.decode([Dataset].self, from: data)
    }

    func saveDatasets(_ datasets: [Dataset]) throws {
        let data = try encoder.encode(datasets)
        try data.write(to: datasetsURL, options: .atomic)
    }

    func importDataset(from sourceURL: URL, name: String, type: DatasetType) throws -> Dataset {
        let isDirectory = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        let destinationName = "\(UUID().uuidString)_\(sourceURL.lastPathComponent)"
        let destinationURL = datasetsDirectory.appendingPathComponent(destinationName)

        // Copy to datasets directory
        if sourceURL.startAccessingSecurityScopedResource() {
            defer { sourceURL.stopAccessingSecurityScopedResource() }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        // Calculate size, sample count, and detect classes
        let stats = try analyzeDataset(at: destinationURL, isDirectory: isDirectory, type: type)

        return Dataset(
            name: name,
            type: type,
            path: destinationURL.path,
            sampleCount: stats.sampleCount,
            size: stats.size,
            classes: stats.classes
        )
    }

    private struct DatasetStats {
        let size: Int64
        let sampleCount: Int
        let classes: [String]
    }

    private func analyzeDataset(at url: URL, isDirectory: Bool, type: DatasetType) throws -> DatasetStats {
        var totalSize: Int64 = 0
        var fileCount = 0
        var classes: [String] = []

        if isDirectory {
            // Check for class subdirectories (common in image classification datasets)
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])
            var classDirectories: [String] = []

            for item in contents {
                let values = try item.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true {
                    let dirName = item.lastPathComponent
                    // Skip hidden directories
                    if !dirName.hasPrefix(".") {
                        classDirectories.append(dirName)
                    }
                }
            }

            // If we found subdirectories, treat them as classes
            if !classDirectories.isEmpty && (type == .images || type == .audio) {
                classes = classDirectories.sorted()
            }

            // Count all files recursively
            let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            while let fileURL = enumerator?.nextObject() as? URL {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values.isRegularFile == true {
                    let fileName = fileURL.lastPathComponent
                    // Skip hidden files
                    if !fileName.hasPrefix(".") {
                        totalSize += Int64(values.fileSize ?? 0)
                        fileCount += 1
                    }
                }
            }
        } else {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            totalSize = attributes[.size] as? Int64 ?? 0
            fileCount = 1

            // For CSV/tabular files, try to detect columns as potential classes
            if type == .tabular {
                classes = try detectCSVColumns(at: url)
            }
        }

        return DatasetStats(size: totalSize, sampleCount: fileCount, classes: classes)
    }

    private func detectCSVColumns(at url: URL) throws -> [String] {
        // Read first line to get column headers
        guard let data = fileManager.contents(atPath: url.path),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        let columns = firstLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        return columns.filter { !$0.isEmpty }
    }

    private func calculateDatasetStats(at url: URL, isDirectory: Bool) throws -> (Int64, Int) {
        var totalSize: Int64 = 0
        var fileCount = 0

        if isDirectory {
            let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            while let fileURL = enumerator?.nextObject() as? URL {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values.isRegularFile == true {
                    totalSize += Int64(values.fileSize ?? 0)
                    fileCount += 1
                }
            }
        } else {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            totalSize = attributes[.size] as? Int64 ?? 0
            fileCount = 1
        }

        return (totalSize, fileCount)
    }

    func deleteDataset(_ dataset: Dataset) throws {
        if let path = dataset.path {
            try? fileManager.removeItem(atPath: path)
        }
    }

    // MARK: - Settings

    func loadSettings() throws -> AppSettings {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return .default
        }
        let data = try Data(contentsOf: settingsURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    func saveSettings(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }

    // MARK: - Inference History

    func loadInferenceHistory() throws -> [InferenceResult] {
        guard fileManager.fileExists(atPath: inferenceHistoryURL.path) else { return [] }
        let data = try Data(contentsOf: inferenceHistoryURL)
        return try decoder.decode([InferenceResult].self, from: data)
    }

    func saveInferenceHistory(_ history: [InferenceResult]) throws {
        let data = try encoder.encode(history)
        try data.write(to: inferenceHistoryURL, options: .atomic)
    }

    // MARK: - Utilities

    func getStorageStats() throws -> StorageStats {
        var modelsSize: Int64 = 0
        var datasetsSize: Int64 = 0
        var cacheSize: Int64 = 0

        modelsSize = try directorySize(modelsDirectory)
        datasetsSize = try directorySize(datasetsDirectory)
        cacheSize = try directorySize(logsDirectory)

        let totalSize = modelsSize + datasetsSize + cacheSize

        return StorageStats(
            totalSize: totalSize,
            modelsSize: modelsSize,
            datasetsSize: datasetsSize,
            cacheSize: cacheSize
        )
    }

    private func directorySize(_ url: URL) throws -> Int64 {
        var size: Int64 = 0
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            size += Int64(values.fileSize ?? 0)
        }
        return size
    }

    func clearCache() throws {
        // Clear logs older than 30 days
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let enumerator = fileManager.enumerator(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.creationDateKey])
            if let creationDate = values.creationDate, creationDate < thirtyDaysAgo {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    func openInFinder() {
        NSWorkspace.shared.open(baseURL)
    }
}

struct StorageStats {
    let totalSize: Int64
    let modelsSize: Int64
    let datasetsSize: Int64
    let cacheSize: Int64
}

enum StorageError: Error, LocalizedError {
    case fileNotFound
    case importFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "File not found"
        case .importFailed: return "Failed to import file"
        case .exportFailed: return "Failed to export file"
        }
    }
}
