import Foundation
import GRDB

// MARK: - Inference Result Repository

actor InferenceResultRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    // MARK: - CRUD Operations

    func create(_ result: InferenceResult) async throws {
        let record = InferenceResultRecord(from: result)
        try await db.write { db in
            try record.insert(db)
        }
    }

    func delete(id: String) async throws {
        try await db.write { db in
            _ = try InferenceResultRecord.deleteOne(db, key: id)
        }
    }

    func findById(_ id: String) async throws -> InferenceResult? {
        try await db.read { db in
            try InferenceResultRecord.fetchOne(db, key: id)?.toInferenceResult()
        }
    }

    func findAll(limit: Int = 100) async throws -> [InferenceResult] {
        try await db.read { db in
            try InferenceResultRecord
                .order(InferenceResultRecord.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(db)
                .compactMap { $0.toInferenceResult() }
        }
    }

    func findByModel(_ modelId: String, limit: Int = 100) async throws -> [InferenceResult] {
        try await db.read { db in
            try InferenceResultRecord
                .filter(InferenceResultRecord.Columns.modelId == modelId)
                .order(InferenceResultRecord.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(db)
                .compactMap { $0.toInferenceResult() }
        }
    }

    func count() async throws -> Int {
        try await db.read { db in
            try InferenceResultRecord.fetchCount(db)
        }
    }

    func countByModel(_ modelId: String) async throws -> Int {
        try await db.read { db in
            try InferenceResultRecord
                .filter(InferenceResultRecord.Columns.modelId == modelId)
                .fetchCount(db)
        }
    }

    // MARK: - Bulk Operations

    func deleteAll() async throws {
        try await db.write { db in
            _ = try InferenceResultRecord.deleteAll(db)
        }
    }

    func deleteOlderThan(_ date: Date) async throws {
        let timestamp = date.timeIntervalSince1970
        try await db.write { db in
            _ = try InferenceResultRecord
                .filter(InferenceResultRecord.Columns.timestamp < timestamp)
                .deleteAll(db)
        }
    }

    /// Keep only the most recent N results
    func pruneToLimit(_ limit: Int) async throws {
        try await db.write { db in
            // Get the timestamp of the Nth most recent result
            let cutoffTimestamp = try InferenceResultRecord
                .order(InferenceResultRecord.Columns.timestamp.desc)
                .limit(1, offset: limit)
                .fetchOne(db)?
                .timestamp

            if let cutoff = cutoffTimestamp {
                _ = try InferenceResultRecord
                    .filter(InferenceResultRecord.Columns.timestamp < cutoff)
                    .deleteAll(db)
            }
        }
    }

    // MARK: - Statistics

    func averageInferenceTime(forModel modelId: String? = nil) async throws -> Double {
        try await db.read { db in
            var request = InferenceResultRecord.all()
            if let modelId = modelId {
                request = request.filter(InferenceResultRecord.Columns.modelId == modelId)
            }
            let avg = try Double.fetchOne(db, request.select(average(Column("inferenceTimeMs"))))
            return avg ?? 0
        }
    }
}
