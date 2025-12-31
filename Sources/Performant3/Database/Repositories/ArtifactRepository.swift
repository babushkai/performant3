import Foundation
import GRDB
import Crypto

// MARK: - Artifact Repository

actor ArtifactRepository {
    private let db: DatabaseManager
    private let fileManager = FileManager.default

    private var artifactsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Performant3/artifacts", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    // MARK: - Store Artifact

    /// Store data and return SHA256 hash
    func store(data: Data, type: ArtifactRecord.ArtifactType, name: String, runId: String? = nil) async throws -> String {
        // Calculate SHA256 hash
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        // Create content-addressed path
        let subdir1 = String(hashString.prefix(2))
        let subdir2 = String(hashString.dropFirst(2).prefix(2))
        let directory = artifactsDirectory
            .appendingPathComponent(subdir1, isDirectory: true)
            .appendingPathComponent(subdir2, isDirectory: true)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let filePath = directory.appendingPathComponent(hashString)

        // Write data if not already exists
        if !fileManager.fileExists(atPath: filePath.path) {
            try data.write(to: filePath)
        }

        // Create database record
        let record = ArtifactRecord(
            sha256: hashString,
            runId: runId,
            type: type.rawValue,
            name: name,
            size: Int64(data.count),
            createdAt: Date().timeIntervalSince1970,
            localPath: filePath.path
        )

        try await db.write { db in
            try record.insert(db, onConflict: .ignore)
        }

        return hashString
    }

    /// Store file and return SHA256 hash
    func storeFile(at url: URL, type: ArtifactRecord.ArtifactType, name: String, runId: String? = nil) async throws -> String {
        let data = try Data(contentsOf: url)
        return try await store(data: data, type: type, name: name, runId: runId)
    }

    // MARK: - Retrieve Artifact

    func retrieve(hash: String) async throws -> Data {
        guard let record = try await findByHash(hash),
              let path = record.localPath else {
            throw ArtifactError.notFound(hash)
        }

        guard fileManager.fileExists(atPath: path) else {
            throw ArtifactError.fileNotFound(path)
        }

        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func getPath(hash: String) async throws -> URL? {
        guard let record = try await findByHash(hash),
              let path = record.localPath else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Query

    func findByHash(_ hash: String) async throws -> ArtifactRecord? {
        try await db.read { db in
            try ArtifactRecord.fetchOne(db, key: hash)
        }
    }

    func findByRun(_ runId: String) async throws -> [ArtifactRecord] {
        try await db.read { db in
            try ArtifactRecord
                .filter(ArtifactRecord.Columns.runId == runId)
                .fetchAll(db)
        }
    }

    func findByType(_ type: ArtifactRecord.ArtifactType) async throws -> [ArtifactRecord] {
        try await db.read { db in
            try ArtifactRecord
                .filter(ArtifactRecord.Columns.type == type.rawValue)
                .fetchAll(db)
        }
    }

    // MARK: - Delete

    func delete(hash: String) async throws {
        // Get record first
        guard let record = try await findByHash(hash) else {
            return
        }

        // Delete file
        if let path = record.localPath {
            try? fileManager.removeItem(atPath: path)
        }

        // Delete database record
        try await db.write { db in
            _ = try ArtifactRecord.deleteOne(db, key: hash)
        }
    }

    func deleteByRun(_ runId: String) async throws {
        let artifacts = try await findByRun(runId)
        for artifact in artifacts {
            if let path = artifact.localPath {
                try? fileManager.removeItem(atPath: path)
            }
        }

        try await db.write { db in
            try ArtifactRecord
                .filter(ArtifactRecord.Columns.runId == runId)
                .deleteAll(db)
        }
    }

    // MARK: - Statistics

    func totalSize() async throws -> Int64 {
        try await db.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(size), 0) FROM artifacts") ?? 0
        }
    }

    func count() async throws -> Int {
        try await db.read { db in
            try ArtifactRecord.fetchCount(db)
        }
    }

    // MARK: - Garbage Collection

    /// Remove orphaned artifacts (no associated run and older than specified days)
    func garbageCollect(olderThanDays: Int = 30) async throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(olderThanDays * 24 * 60 * 60)).timeIntervalSince1970

        let orphaned = try await db.read { db -> [ArtifactRecord] in
            try ArtifactRecord
                .filter(ArtifactRecord.Columns.runId == nil)
                .filter(Column("created_at") < cutoff)
                .fetchAll(db)
        }

        var deletedCount = 0
        for artifact in orphaned {
            try await delete(hash: artifact.sha256)
            deletedCount += 1
        }

        return deletedCount
    }
}

// MARK: - Artifact Errors

enum ArtifactError: Error, LocalizedError {
    case notFound(String)
    case fileNotFound(String)
    case hashMismatch

    var errorDescription: String? {
        switch self {
        case .notFound(let hash):
            return "Artifact not found: \(hash)"
        case .fileNotFound(let path):
            return "Artifact file not found: \(path)"
        case .hashMismatch:
            return "Artifact hash mismatch"
        }
    }
}
