import Foundation
import GRDB

// MARK: - Dataset Repository

actor DatasetRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    // MARK: - CRUD Operations

    func create(_ dataset: Dataset) async throws {
        let record = DatasetRecord(from: dataset)
        try await db.write { db in
            try record.insert(db)
        }
    }

    func update(_ dataset: Dataset) async throws {
        let record = DatasetRecord(from: dataset)
        try await db.write { db in
            try record.update(db)
        }
    }

    func delete(id: String) async throws {
        try await db.write { db in
            _ = try DatasetRecord.deleteOne(db, key: id)
        }
    }

    func findById(_ id: String) async throws -> Dataset? {
        try await db.read { db in
            try DatasetRecord.fetchOne(db, key: id)?.toDataset()
        }
    }

    func findAll() async throws -> [Dataset] {
        try await db.read { db in
            try DatasetRecord
                .order(DatasetRecord.Columns.createdAt.desc)
                .fetchAll(db)
                .map { $0.toDataset() }
        }
    }

    func findByType(_ type: DatasetType) async throws -> [Dataset] {
        try await db.read { db in
            try DatasetRecord
                .filter(DatasetRecord.Columns.type == type.rawValue)
                .order(DatasetRecord.Columns.createdAt.desc)
                .fetchAll(db)
                .map { $0.toDataset() }
        }
    }

    func search(query: String) async throws -> [Dataset] {
        try await db.read { db in
            try DatasetRecord
                .filter(DatasetRecord.Columns.name.like("%\(query)%"))
                .order(DatasetRecord.Columns.createdAt.desc)
                .fetchAll(db)
                .map { $0.toDataset() }
        }
    }

    func count() async throws -> Int {
        try await db.read { db in
            try DatasetRecord.fetchCount(db)
        }
    }

    func totalSize() async throws -> Int64 {
        try await db.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(size), 0) FROM datasets") ?? 0
        }
    }
}
