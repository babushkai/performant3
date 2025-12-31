import Foundation
import GRDB

// MARK: - Model Repository

actor ModelRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    // MARK: - CRUD Operations

    func create(_ model: MLModel) async throws {
        let record = ModelRecord(from: model)
        try await db.write { db in
            try record.insert(db)
        }
    }

    func update(_ model: MLModel) async throws {
        var record = ModelRecord(from: model)
        record.updatedAt = Date().timeIntervalSince1970
        try await db.write { db in
            try record.update(db)
        }
    }

    func delete(id: String) async throws {
        try await db.write { db in
            _ = try ModelRecord.deleteOne(db, key: id)
        }
    }

    func findById(_ id: String) async throws -> MLModel? {
        try await db.read { db in
            try ModelRecord.fetchOne(db, key: id)?.toModel()
        }
    }

    func findAll() async throws -> [MLModel] {
        try await db.read { db in
            try ModelRecord
                .order(ModelRecord.Columns.updatedAt.desc)
                .fetchAll(db)
                .map { $0.toModel() }
        }
    }

    func findByFramework(_ framework: MLFramework) async throws -> [MLModel] {
        try await db.read { db in
            try ModelRecord
                .filter(ModelRecord.Columns.framework == framework.rawValue)
                .order(ModelRecord.Columns.updatedAt.desc)
                .fetchAll(db)
                .map { $0.toModel() }
        }
    }

    func findByStatus(_ status: ModelStatus) async throws -> [MLModel] {
        try await db.read { db in
            try ModelRecord
                .filter(ModelRecord.Columns.status == status.rawValue)
                .order(ModelRecord.Columns.updatedAt.desc)
                .fetchAll(db)
                .map { $0.toModel() }
        }
    }

    func search(query: String) async throws -> [MLModel] {
        try await db.read { db in
            try ModelRecord
                .filter(ModelRecord.Columns.name.like("%\(query)%"))
                .order(ModelRecord.Columns.updatedAt.desc)
                .fetchAll(db)
                .map { $0.toModel() }
        }
    }

    func count() async throws -> Int {
        try await db.read { db in
            try ModelRecord.fetchCount(db)
        }
    }

    func updateStatus(id: String, status: ModelStatus) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE models SET status = ?, updated_at = ? WHERE id = ?",
                arguments: [status.rawValue, Date().timeIntervalSince1970, id]
            )
        }
    }

    func updateAccuracy(id: String, accuracy: Double) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE models SET accuracy = ?, updated_at = ? WHERE id = ?",
                arguments: [accuracy, Date().timeIntervalSince1970, id]
            )
        }
    }
}
