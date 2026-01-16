import Foundation

// MARK: - Model Version

/// Represents a specific version of a trained model
struct ModelVersion: Identifiable, Codable, Hashable {
    let id: String
    let modelId: String
    let version: String  // Semantic versioning: "1.0.0"
    let parentVersionId: String?  // For tracking lineage
    let checkpointPath: String
    let accuracy: Double?
    let loss: Double?
    let trainingRunId: String?
    let createdAt: Date
    let metadata: [String: String]
    let tags: [String]
    var isProduction: Bool  // Flag for "deployed" version
    var notes: String?

    init(
        id: String = UUID().uuidString,
        modelId: String,
        version: String,
        parentVersionId: String? = nil,
        checkpointPath: String,
        accuracy: Double? = nil,
        loss: Double? = nil,
        trainingRunId: String? = nil,
        metadata: [String: String] = [:],
        tags: [String] = [],
        isProduction: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.modelId = modelId
        self.version = version
        self.parentVersionId = parentVersionId
        self.checkpointPath = checkpointPath
        self.accuracy = accuracy
        self.loss = loss
        self.trainingRunId = trainingRunId
        self.createdAt = Date()
        self.metadata = metadata
        self.tags = tags
        self.isProduction = isProduction
        self.notes = notes
    }

    /// Parse version string into components
    var versionComponents: (major: Int, minor: Int, patch: Int) {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        return (
            parts.count > 0 ? parts[0] : 0,
            parts.count > 1 ? parts[1] : 0,
            parts.count > 2 ? parts[2] : 0
        )
    }
}

// MARK: - Version Manager Error

enum ModelVersionError: Error, LocalizedError {
    case noCheckpoint
    case versionNotFound
    case invalidVersion
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .noCheckpoint:
            return "No checkpoint found for this training run"
        case .versionNotFound:
            return "Version not found"
        case .invalidVersion:
            return "Invalid version string"
        case .modelNotFound:
            return "Model not found"
        }
    }
}

// MARK: - Version Manager

/// Manages model versions with persistence
actor ModelVersionManager {
    static let shared = ModelVersionManager()

    private let storage = StorageManager.shared
    private var versions: [String: [ModelVersion]] = [:]  // modelId -> versions
    private var isLoaded = false

    private init() {}

    // MARK: - Loading

    func loadVersions() async {
        guard !isLoaded else { return }

        do {
            let allVersions = try await storage.loadModelVersions()
            // Group by model ID
            versions = Dictionary(grouping: allVersions, by: { $0.modelId })
            isLoaded = true
        } catch {
            print("Failed to load model versions: \(error)")
            versions = [:]
            isLoaded = true
        }
    }

    private func saveVersions() async {
        let allVersions = versions.values.flatMap { $0 }
        do {
            try await storage.saveModelVersions(Array(allVersions))
        } catch {
            print("Failed to save model versions: \(error)")
        }
    }

    // MARK: - Version Operations

    /// Create a new version from a completed training run
    func createVersion(
        for modelId: String,
        from runId: String,
        notes: String? = nil,
        tags: [String] = []
    ) async throws -> ModelVersion {
        await loadVersions()

        guard let checkpoint = try await CheckpointManager.shared.getLatestCheckpoint(runId: runId) else {
            throw ModelVersionError.noCheckpoint
        }

        let existingVersions = versions[modelId] ?? []
        let nextVersion = calculateNextVersion(from: existingVersions)

        let version = ModelVersion(
            modelId: modelId,
            version: nextVersion,
            parentVersionId: existingVersions.last?.id,
            checkpointPath: checkpoint.path,
            accuracy: checkpoint.accuracy,
            loss: checkpoint.loss,
            trainingRunId: runId,
            metadata: [
                "architectureType": checkpoint.architectureType ?? "unknown",
                "epoch": "\(checkpoint.epoch)"
            ],
            tags: tags,
            notes: notes
        )

        var modelVersions = versions[modelId] ?? []
        modelVersions.append(version)
        versions[modelId] = modelVersions

        await saveVersions()

        return version
    }

    /// Create a version manually (for imported models)
    func createManualVersion(
        for modelId: String,
        checkpointPath: String,
        accuracy: Double? = nil,
        loss: Double? = nil,
        notes: String? = nil,
        tags: [String] = []
    ) async throws -> ModelVersion {
        await loadVersions()

        let existingVersions = versions[modelId] ?? []
        let nextVersion = calculateNextVersion(from: existingVersions)

        let version = ModelVersion(
            modelId: modelId,
            version: nextVersion,
            parentVersionId: existingVersions.last?.id,
            checkpointPath: checkpointPath,
            accuracy: accuracy,
            loss: loss,
            metadata: [:],
            tags: tags,
            notes: notes
        )

        var modelVersions = versions[modelId] ?? []
        modelVersions.append(version)
        versions[modelId] = modelVersions

        await saveVersions()

        return version
    }

    /// Get all versions for a model
    func getVersions(for modelId: String) async -> [ModelVersion] {
        await loadVersions()
        return versions[modelId] ?? []
    }

    /// Get a specific version
    func getVersion(id: String) async -> ModelVersion? {
        await loadVersions()
        return versions.values.flatMap { $0 }.first { $0.id == id }
    }

    /// Get the production version for a model
    func getProductionVersion(for modelId: String) async -> ModelVersion? {
        await loadVersions()
        return versions[modelId]?.first { $0.isProduction }
    }

    /// Get the latest version for a model
    func getLatestVersion(for modelId: String) async -> ModelVersion? {
        await loadVersions()
        return versions[modelId]?.last
    }

    /// Set a version as production
    func setProduction(versionId: String, modelId: String) async throws {
        await loadVersions()

        guard var modelVersions = versions[modelId] else {
            throw ModelVersionError.modelNotFound
        }

        guard modelVersions.contains(where: { $0.id == versionId }) else {
            throw ModelVersionError.versionNotFound
        }

        // Unset previous production version, set new one
        for i in modelVersions.indices {
            modelVersions[i].isProduction = (modelVersions[i].id == versionId)
        }

        versions[modelId] = modelVersions
        await saveVersions()
    }

    /// Update version notes
    func updateNotes(versionId: String, notes: String) async throws {
        await loadVersions()

        for modelId in versions.keys {
            if let index = versions[modelId]?.firstIndex(where: { $0.id == versionId }) {
                versions[modelId]?[index].notes = notes
                await saveVersions()
                return
            }
        }

        throw ModelVersionError.versionNotFound
    }

    /// Add tags to a version
    func addTags(versionId: String, tags: [String]) async throws {
        await loadVersions()

        for modelId in versions.keys {
            if let index = versions[modelId]?.firstIndex(where: { $0.id == versionId }) {
                var existingTags = versions[modelId]?[index].tags ?? []
                existingTags.append(contentsOf: tags.filter { !existingTags.contains($0) })
                versions[modelId]?[index] = ModelVersion(
                    id: versions[modelId]![index].id,
                    modelId: versions[modelId]![index].modelId,
                    version: versions[modelId]![index].version,
                    parentVersionId: versions[modelId]![index].parentVersionId,
                    checkpointPath: versions[modelId]![index].checkpointPath,
                    accuracy: versions[modelId]![index].accuracy,
                    loss: versions[modelId]![index].loss,
                    trainingRunId: versions[modelId]![index].trainingRunId,
                    metadata: versions[modelId]![index].metadata,
                    tags: existingTags,
                    isProduction: versions[modelId]![index].isProduction,
                    notes: versions[modelId]![index].notes
                )
                await saveVersions()
                return
            }
        }

        throw ModelVersionError.versionNotFound
    }

    /// Delete a version
    func deleteVersion(id: String) async throws {
        await loadVersions()

        for modelId in versions.keys {
            if let index = versions[modelId]?.firstIndex(where: { $0.id == id }) {
                versions[modelId]?.remove(at: index)
                await saveVersions()
                return
            }
        }

        throw ModelVersionError.versionNotFound
    }

    /// Delete all versions for a model
    func deleteAllVersions(for modelId: String) async {
        await loadVersions()
        versions.removeValue(forKey: modelId)
        await saveVersions()
    }

    // MARK: - Version Calculation

    private func calculateNextVersion(from existing: [ModelVersion]) -> String {
        guard let last = existing.last else { return "1.0.0" }

        let components = last.version.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3 else { return "1.0.0" }

        // Increment patch version
        return "\(components[0]).\(components[1]).\(components[2] + 1)"
    }

    /// Bump version number
    func bumpVersion(_ current: String, type: VersionBumpType) -> String {
        let components = current.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3 else { return "1.0.0" }

        switch type {
        case .major:
            return "\(components[0] + 1).0.0"
        case .minor:
            return "\(components[0]).\(components[1] + 1).0"
        case .patch:
            return "\(components[0]).\(components[1]).\(components[2] + 1)"
        }
    }

    enum VersionBumpType {
        case major
        case minor
        case patch
    }

    // MARK: - Comparison

    /// Compare two versions
    func compareVersions(_ v1: String, _ v2: String) -> Int {
        let c1 = v1.split(separator: ".").compactMap { Int($0) }
        let c2 = v2.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(c1.count, c2.count) {
            let n1 = i < c1.count ? c1[i] : 0
            let n2 = i < c2.count ? c2[i] : 0

            if n1 < n2 { return -1 }
            if n1 > n2 { return 1 }
        }

        return 0
    }
}

// MARK: - Storage Extension

extension StorageManager {
    private var versionsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Performant3", isDirectory: true)
        return appDir.appendingPathComponent("model_versions.json")
    }

    func loadModelVersions() async throws -> [ModelVersion] {
        let url = versionsURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ModelVersion].self, from: data)
    }

    func saveModelVersions(_ versions: [ModelVersion]) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(versions)
        try data.write(to: versionsURL, options: .atomic)
    }
}
