import Foundation
import GRDB

// MARK: - Training Run Repository

actor TrainingRunRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    // MARK: - CRUD Operations

    func create(_ run: TrainingRun, experimentId: String? = nil) async throws {
        let record = TrainingRunRecord(from: run, experimentId: experimentId)
        try await db.write { db in
            try record.insert(db)
        }
    }

    func update(_ run: TrainingRun) async throws {
        try await db.write { db in
            // Get existing record to preserve experimentId
            guard var record = try TrainingRunRecord.fetchOne(db, key: run.id) else {
                throw DatabaseError.recordNotFound("TrainingRun")
            }

            record.status = run.status.rawValue
            record.progress = run.progress
            record.currentEpoch = run.currentEpoch
            record.loss = run.loss
            record.accuracy = run.accuracy
            record.finishedAt = run.finishedAt?.timeIntervalSince1970

            try record.update(db)
        }
    }

    func delete(id: String) async throws {
        try await db.write { db in
            _ = try TrainingRunRecord.deleteOne(db, key: id)
        }
    }

    func findById(_ id: String) async throws -> TrainingRun? {
        try await db.read { db in
            guard let record = try TrainingRunRecord.fetchOne(db, key: id) else {
                return nil
            }

            // Get model name
            let model = try ModelRecord.fetchOne(db, key: record.modelId)
            return record.toRun(modelName: model?.name ?? "Unknown")
        }
    }

    func findAll() async throws -> [TrainingRun] {
        try await db.read { db in
            let records = try TrainingRunRecord
                .order(TrainingRunRecord.Columns.startedAt.desc)
                .fetchAll(db)

            return try records.map { record in
                let model = try ModelRecord.fetchOne(db, key: record.modelId)
                return record.toRun(modelName: model?.name ?? "Unknown")
            }
        }
    }

    func findByModel(_ modelId: String) async throws -> [TrainingRun] {
        try await db.read { db in
            let records = try TrainingRunRecord
                .filter(TrainingRunRecord.Columns.modelId == modelId)
                .order(TrainingRunRecord.Columns.startedAt.desc)
                .fetchAll(db)

            let model = try ModelRecord.fetchOne(db, key: modelId)

            return records.map { record in
                record.toRun(modelName: model?.name ?? "Unknown")
            }
        }
    }

    func findByExperiment(_ experimentId: String) async throws -> [TrainingRun] {
        try await db.read { db in
            let records = try TrainingRunRecord
                .filter(TrainingRunRecord.Columns.experimentId == experimentId)
                .order(TrainingRunRecord.Columns.startedAt.desc)
                .fetchAll(db)

            return try records.map { record in
                let model = try ModelRecord.fetchOne(db, key: record.modelId)
                return record.toRun(modelName: model?.name ?? "Unknown")
            }
        }
    }

    func findByStatus(_ status: RunStatus) async throws -> [TrainingRun] {
        try await db.read { db in
            let records = try TrainingRunRecord
                .filter(TrainingRunRecord.Columns.status == status.rawValue)
                .order(TrainingRunRecord.Columns.startedAt.desc)
                .fetchAll(db)

            return try records.map { record in
                let model = try ModelRecord.fetchOne(db, key: record.modelId)
                return record.toRun(modelName: model?.name ?? "Unknown")
            }
        }
    }

    func findActive() async throws -> [TrainingRun] {
        try await db.read { db in
            let activeStatuses = [RunStatus.running.rawValue, RunStatus.queued.rawValue, RunStatus.paused.rawValue]
            let records = try TrainingRunRecord
                .filter(activeStatuses.contains(TrainingRunRecord.Columns.status))
                .order(TrainingRunRecord.Columns.startedAt.desc)
                .fetchAll(db)

            return try records.map { record in
                let model = try ModelRecord.fetchOne(db, key: record.modelId)
                return record.toRun(modelName: model?.name ?? "Unknown")
            }
        }
    }

    func findCompleted(limit: Int = 100) async throws -> [TrainingRun] {
        try await db.read { db in
            let records = try TrainingRunRecord
                .filter(TrainingRunRecord.Columns.status == RunStatus.completed.rawValue)
                .order(TrainingRunRecord.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)

            return try records.map { record in
                let model = try ModelRecord.fetchOne(db, key: record.modelId)
                return record.toRun(modelName: model?.name ?? "Unknown")
            }
        }
    }

    func count() async throws -> Int {
        try await db.read { db in
            try TrainingRunRecord.fetchCount(db)
        }
    }

    func countByStatus(_ status: RunStatus) async throws -> Int {
        try await db.read { db in
            try TrainingRunRecord
                .filter(TrainingRunRecord.Columns.status == status.rawValue)
                .fetchCount(db)
        }
    }

    // MARK: - Metrics

    func addMetric(runId: String, epoch: Int, step: Int? = nil, name: String, value: Double) async throws {
        let record = MetricRecord(runId: runId, epoch: epoch, step: step, name: name, value: value)
        try await db.write { db in
            try record.insert(db, onConflict: .replace)
        }
    }

    func addMetrics(runId: String, epoch: Int, metrics: [String: Double]) async throws {
        try await db.write { db in
            for (name, value) in metrics {
                let record = MetricRecord(runId: runId, epoch: epoch, name: name, value: value)
                try record.insert(db, onConflict: .replace)
            }
        }
    }

    func getMetrics(runId: String) async throws -> [MetricPoint] {
        try await db.read { db in
            let records = try MetricRecord
                .filter(MetricRecord.Columns.runId == runId)
                .order(MetricRecord.Columns.epoch.asc)
                .fetchAll(db)

            // Group by epoch and combine loss/accuracy
            var metricsByEpoch: [Int: (loss: Double?, accuracy: Double?)] = [:]
            for record in records {
                var metrics = metricsByEpoch[record.epoch] ?? (nil, nil)
                if record.metricName == "loss" {
                    metrics.loss = record.metricValue
                } else if record.metricName == "accuracy" {
                    metrics.accuracy = record.metricValue
                }
                metricsByEpoch[record.epoch] = metrics
            }

            return metricsByEpoch.sorted { $0.key < $1.key }.map { epoch, metrics in
                MetricPoint(epoch: epoch, loss: metrics.loss ?? 0, accuracy: metrics.accuracy ?? 0)
            }
        }
    }

    // MARK: - Logs

    func addLog(runId: String, entry: LogEntry) async throws {
        let record = RunLogRecord(runId: runId, entry: entry)
        try await db.write { db in
            try record.insert(db)
        }
    }

    func addLogs(runId: String, entries: [LogEntry]) async throws {
        try await db.write { db in
            for entry in entries {
                let record = RunLogRecord(runId: runId, entry: entry)
                try record.insert(db)
            }
        }
    }

    func getLogs(runId: String, limit: Int = 1000) async throws -> [LogEntry] {
        try await db.read { db in
            try RunLogRecord
                .filter(RunLogRecord.Columns.runId == runId)
                .order(RunLogRecord.Columns.timestamp.asc)
                .limit(limit)
                .fetchAll(db)
                .map { $0.toLogEntry() }
        }
    }
}
