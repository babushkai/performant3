import Foundation
import UniformTypeIdentifiers

/// Service for validating datasets before training
actor DatasetValidator {
    static let shared = DatasetValidator()

    struct ValidationResult {
        let isValid: Bool
        let errors: [ValidationError]
        let warnings: [ValidationWarning]
        let statistics: DatasetStatistics

        var hasWarnings: Bool { !warnings.isEmpty }
        var summary: String {
            if isValid && !hasWarnings {
                return "Dataset is valid and ready for training"
            } else if isValid && hasWarnings {
                return "Dataset is valid with \(warnings.count) warning(s)"
            } else {
                return "Dataset has \(errors.count) error(s)"
            }
        }
    }

    struct ValidationError: Identifiable {
        let id = UUID()
        let code: ErrorCode
        let message: String
        let path: String?

        enum ErrorCode: String {
            case missingPath = "MISSING_PATH"
            case invalidFormat = "INVALID_FORMAT"
            case noSamples = "NO_SAMPLES"
            case corruptedFile = "CORRUPTED_FILE"
            case missingLabels = "MISSING_LABELS"
            case invalidYAML = "INVALID_YAML"
        }
    }

    struct ValidationWarning: Identifiable {
        let id = UUID()
        let code: WarningCode
        let message: String

        enum WarningCode: String {
            case imbalancedClasses = "IMBALANCED_CLASSES"
            case lowSampleCount = "LOW_SAMPLE_COUNT"
            case mixedImageSizes = "MIXED_IMAGE_SIZES"
            case missingValidation = "MISSING_VALIDATION"
            case duplicateFiles = "DUPLICATE_FILES"
        }
    }

    struct DatasetStatistics {
        var totalSamples: Int = 0
        var trainSamples: Int = 0
        var validationSamples: Int = 0
        var testSamples: Int = 0
        var classCount: Int = 0
        var classCounts: [String: Int] = [:]
        var imageSizes: Set<String> = []
        var totalSizeBytes: Int64 = 0
        var fileFormats: [String: Int] = [:]

        var totalSizeMB: Double { Double(totalSizeBytes) / 1_048_576 }

        var isBalanced: Bool {
            guard !classCounts.isEmpty else { return true }
            let counts = Array(classCounts.values)
            let avg = counts.reduce(0, +) / counts.count
            return counts.allSatisfy { abs($0 - avg) < avg / 2 }
        }
    }

    // MARK: - Validation

    func validate(path: String, type: DatasetType) async -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        var statistics = DatasetStatistics()

        let fileManager = FileManager.default

        // Check path exists
        guard fileManager.fileExists(atPath: path) else {
            errors.append(ValidationError(
                code: .missingPath,
                message: "Dataset path does not exist",
                path: path
            ))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings, statistics: statistics)
        }

        // Validate based on type
        switch type {
        case .images:
            await validateImageFolder(path: path, errors: &errors, warnings: &warnings, statistics: &statistics)

        case .tabular:
            await validateCSV(path: path, errors: &errors, warnings: &warnings, statistics: &statistics)

        case .text, .audio, .video, .custom:
            // Basic file existence check only
            statistics.totalSamples = 1
        }

        // Check for low sample count
        if statistics.totalSamples > 0 && statistics.totalSamples < 100 {
            warnings.append(ValidationWarning(
                code: .lowSampleCount,
                message: "Dataset has only \(statistics.totalSamples) samples. Consider adding more data for better results."
            ))
        }

        // Check for class imbalance
        if !statistics.isBalanced && statistics.classCount > 1 {
            warnings.append(ValidationWarning(
                code: .imbalancedClasses,
                message: "Classes are imbalanced. Consider data augmentation or weighted sampling."
            ))
        }

        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            statistics: statistics
        )
    }

    // MARK: - Type-Specific Validation

    private func validateImageFolder(
        path: String,
        errors: inout [ValidationError],
        warnings: inout [ValidationWarning],
        statistics: inout DatasetStatistics
    ) async {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)

        // Get class directories
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else {
            errors.append(ValidationError(code: .invalidFormat, message: "Cannot read directory contents", path: path))
            return
        }

        let classDirs = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        if classDirs.isEmpty {
            errors.append(ValidationError(code: .invalidFormat, message: "No class subdirectories found", path: path))
            return
        }

        statistics.classCount = classDirs.count

        for classDir in classDirs {
            let className = classDir.lastPathComponent

            guard let files = try? fileManager.contentsOfDirectory(at: classDir, includingPropertiesForKeys: [.fileSizeKey]) else {
                continue
            }

            let imageFiles = files.filter { isImageFile($0) }
            statistics.classCounts[className] = imageFiles.count
            statistics.totalSamples += imageFiles.count

            for file in imageFiles {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    statistics.totalSizeBytes += Int64(size)
                }
                let ext = file.pathExtension.lowercased()
                statistics.fileFormats[ext, default: 0] += 1
            }
        }

        // Check for train/val split
        let hasTrainVal = classDirs.contains { $0.lastPathComponent.lowercased() == "train" } ||
                          contents.contains { $0.lastPathComponent.lowercased() == "train" }

        if !hasTrainVal {
            warnings.append(ValidationWarning(
                code: .missingValidation,
                message: "No train/val split detected. A random split will be used."
            ))
        }
    }

    private func validateYOLO(
        path: String,
        errors: inout [ValidationError],
        warnings: inout [ValidationWarning],
        statistics: inout DatasetStatistics
    ) async {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)

        // Look for data.yaml
        let yamlPath = url.appendingPathComponent("data.yaml")
        let dataYamlPath = url.appendingPathComponent("dataset.yaml")

        let configPath: URL
        if fileManager.fileExists(atPath: yamlPath.path) {
            configPath = yamlPath
        } else if fileManager.fileExists(atPath: dataYamlPath.path) {
            configPath = dataYamlPath
        } else {
            errors.append(ValidationError(
                code: .invalidYAML,
                message: "No data.yaml or dataset.yaml found",
                path: path
            ))
            return
        }

        // Parse YAML (basic parsing)
        guard let yamlContent = try? String(contentsOf: configPath, encoding: .utf8) else {
            errors.append(ValidationError(code: .invalidYAML, message: "Cannot read YAML file", path: configPath.path))
            return
        }

        // Extract class names
        if let namesMatch = yamlContent.range(of: "names:") {
            let afterNames = String(yamlContent[namesMatch.upperBound...])
            let classNames = afterNames.components(separatedBy: .newlines)
                .filter { $0.contains("-") || $0.contains(":") }
                .prefix(100)
            statistics.classCount = classNames.count
        }

        // Check for images directory
        let imagesDirs = ["images", "train/images", "images/train"]
        var foundImages = false

        for dir in imagesDirs {
            let imagesPath = url.appendingPathComponent(dir)
            if fileManager.fileExists(atPath: imagesPath.path) {
                if let files = try? fileManager.contentsOfDirectory(at: imagesPath, includingPropertiesForKeys: nil) {
                    statistics.trainSamples = files.filter { isImageFile($0) }.count
                    statistics.totalSamples += statistics.trainSamples
                    foundImages = true
                    break
                }
            }
        }

        if !foundImages {
            errors.append(ValidationError(code: .noSamples, message: "No images directory found", path: path))
        }

        // Check for labels
        let labelsDirs = ["labels", "train/labels", "labels/train"]
        var foundLabels = false

        for dir in labelsDirs {
            let labelsPath = url.appendingPathComponent(dir)
            if fileManager.fileExists(atPath: labelsPath.path) {
                foundLabels = true
                break
            }
        }

        if !foundLabels {
            errors.append(ValidationError(code: .missingLabels, message: "No labels directory found", path: path))
        }
    }

    private func validateCOCO(
        path: String,
        errors: inout [ValidationError],
        warnings: inout [ValidationWarning],
        statistics: inout DatasetStatistics
    ) async {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)

        // Look for annotations file
        let annotationsPath = url.appendingPathComponent("annotations")
        let instancesPath = annotationsPath.appendingPathComponent("instances_train2017.json")

        if !fileManager.fileExists(atPath: annotationsPath.path) {
            errors.append(ValidationError(code: .missingLabels, message: "No annotations directory found", path: path))
            return
        }

        // Check for train images
        let trainImagesPath = url.appendingPathComponent("train2017")
        if fileManager.fileExists(atPath: trainImagesPath.path) {
            if let files = try? fileManager.contentsOfDirectory(at: trainImagesPath, includingPropertiesForKeys: nil) {
                statistics.trainSamples = files.filter { isImageFile($0) }.count
                statistics.totalSamples += statistics.trainSamples
            }
        }

        // Check for val images
        let valImagesPath = url.appendingPathComponent("val2017")
        if fileManager.fileExists(atPath: valImagesPath.path) {
            if let files = try? fileManager.contentsOfDirectory(at: valImagesPath, includingPropertiesForKeys: nil) {
                statistics.validationSamples = files.filter { isImageFile($0) }.count
                statistics.totalSamples += statistics.validationSamples
            }
        }
    }

    private func validateCSV(
        path: String,
        errors: inout [ValidationError],
        warnings: inout [ValidationWarning],
        statistics: inout DatasetStatistics
    ) async {
        let url = URL(fileURLWithPath: path)

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            errors.append(ValidationError(code: .corruptedFile, message: "Cannot read CSV file", path: path))
            return
        }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        statistics.totalSamples = max(0, lines.count - 1) // Exclude header

        if statistics.totalSamples == 0 {
            errors.append(ValidationError(code: .noSamples, message: "CSV file has no data rows", path: path))
        }

        // Get file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            statistics.totalSizeBytes = attrs[.size] as? Int64 ?? 0
        }
    }

    // MARK: - Helpers

    private func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }
}

// MARK: - Dataset Type Extensions

extension DatasetType {
    var validationDescription: String {
        switch self {
        case .images:
            return "Expects subdirectories named by class, each containing images"
        case .tabular:
            return "Expects CSV/JSON file with features and labels"
        case .text:
            return "Expects text files or documents"
        case .audio:
            return "Expects audio files (wav, mp3, etc.)"
        case .video:
            return "Expects video files"
        case .custom:
            return "Custom dataset format"
        }
    }

    var requiredStructure: [String] {
        switch self {
        case .images:
            return ["class1/", "class2/", "..."]
        case .tabular:
            return ["data.csv or data.json"]
        case .text:
            return ["*.txt files"]
        case .audio:
            return ["*.wav, *.mp3 files"]
        case .video:
            return ["*.mp4, *.mov files"]
        case .custom:
            return []
        }
    }
}
