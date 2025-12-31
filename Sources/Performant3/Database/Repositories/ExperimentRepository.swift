import Foundation
import GRDB

// MARK: - Project Repository

actor ProjectRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    func create(_ project: ProjectRecord) async throws {
        try await db.write { db in
            try project.insert(db)
        }
    }

    func update(_ project: ProjectRecord) async throws {
        var updated = project
        updated.updatedAt = Date().timeIntervalSince1970
        try await db.write { db in
            try updated.update(db)
        }
    }

    func delete(id: String) async throws {
        try await db.write { db in
            _ = try ProjectRecord.deleteOne(db, key: id)
        }
    }

    func findById(_ id: String) async throws -> ProjectRecord? {
        try await db.read { db in
            try ProjectRecord.fetchOne(db, key: id)
        }
    }

    func findAll() async throws -> [ProjectRecord] {
        try await db.read { db in
            try ProjectRecord
                .order(ProjectRecord.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    func count() async throws -> Int {
        try await db.read { db in
            try ProjectRecord.fetchCount(db)
        }
    }
}

// MARK: - Experiment Repository

actor ExperimentRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    func create(_ experiment: ExperimentRecord) async throws {
        try await db.write { db in
            try experiment.insert(db)
        }
    }

    func update(_ experiment: ExperimentRecord) async throws {
        var updated = experiment
        updated.updatedAt = Date().timeIntervalSince1970
        try await db.write { db in
            try updated.update(db)
        }
    }

    func delete(id: String) async throws {
        try await db.write { db in
            _ = try ExperimentRecord.deleteOne(db, key: id)
        }
    }

    func findById(_ id: String) async throws -> ExperimentRecord? {
        try await db.read { db in
            try ExperimentRecord.fetchOne(db, key: id)
        }
    }

    func findByProject(_ projectId: String) async throws -> [ExperimentRecord] {
        try await db.read { db in
            try ExperimentRecord
                .filter(ExperimentRecord.Columns.projectId == projectId)
                .order(ExperimentRecord.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func findAll() async throws -> [ExperimentRecord] {
        try await db.read { db in
            try ExperimentRecord
                .order(ExperimentRecord.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func count() async throws -> Int {
        try await db.read { db in
            try ExperimentRecord.fetchCount(db)
        }
    }

    func countByProject(_ projectId: String) async throws -> Int {
        try await db.read { db in
            try ExperimentRecord
                .filter(ExperimentRecord.Columns.projectId == projectId)
                .fetchCount(db)
        }
    }

    // MARK: - Experiment with Runs

    func getExperimentWithRuns(_ experimentId: String) async throws -> (experiment: ExperimentRecord, runs: [TrainingRunRecord])? {
        try await db.read { db in
            guard let experiment = try ExperimentRecord.fetchOne(db, key: experimentId) else {
                return nil
            }

            let runs = try TrainingRunRecord
                .filter(TrainingRunRecord.Columns.experimentId == experimentId)
                .order(TrainingRunRecord.Columns.startedAt.desc)
                .fetchAll(db)

            return (experiment, runs)
        }
    }

    // MARK: - Statistics

    func getExperimentStats(_ experimentId: String) async throws -> ExperimentStats {
        try await db.read { db in
            let runs = try TrainingRunRecord
                .filter(TrainingRunRecord.Columns.experimentId == experimentId)
                .fetchAll(db)

            let completed = runs.filter { $0.status == RunStatus.completed.rawValue }
            let bestRun = completed.max { ($0.accuracy ?? 0) < ($1.accuracy ?? 0) }

            return ExperimentStats(
                totalRuns: runs.count,
                completedRuns: completed.count,
                bestAccuracy: bestRun?.accuracy,
                bestLoss: bestRun?.loss,
                bestRunId: bestRun?.id
            )
        }
    }
}

// MARK: - Experiment Stats

struct ExperimentStats {
    let totalRuns: Int
    let completedRuns: Int
    let bestAccuracy: Double?
    let bestLoss: Double?
    let bestRunId: String?
}
