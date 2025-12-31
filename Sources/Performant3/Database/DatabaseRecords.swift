import Foundation
import GRDB

// MARK: - Project Record

struct ProjectRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "projects"

    var id: String
    var name: String
    var description: String?
    var createdAt: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: String = UUID().uuidString, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = Date().timeIntervalSince1970
        self.updatedAt = Date().timeIntervalSince1970
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let description = Column(CodingKeys.description)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// MARK: - Experiment Record

struct ExperimentRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "experiments"

    var id: String
    var projectId: String
    var name: String
    var description: String?
    var createdAt: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case projectId = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: String = UUID().uuidString, projectId: String, name: String, description: String? = nil) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.description = description
        self.createdAt = Date().timeIntervalSince1970
        self.updatedAt = Date().timeIntervalSince1970
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let projectId = Column(CodingKeys.projectId)
        static let name = Column(CodingKeys.name)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    static let project = belongsTo(ProjectRecord.self)
    static let runs = hasMany(TrainingRunRecord.self)
}

// MARK: - Model Record

struct ModelRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "models"

    var id: String
    var name: String
    var framework: String
    var status: String
    var accuracy: Double?
    var fileSize: Int64?
    var filePath: String?
    var createdAt: Double
    var updatedAt: Double
    var metadata: String?

    enum CodingKeys: String, CodingKey {
        case id, name, framework, status, accuracy, metadata
        case fileSize = "file_size"
        case filePath = "file_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from model: MLModel) {
        self.id = model.id
        self.name = model.name
        self.framework = model.framework.rawValue
        self.status = model.status.rawValue
        self.accuracy = model.accuracy
        self.fileSize = model.fileSize
        self.filePath = model.filePath
        self.createdAt = model.createdAt.timeIntervalSince1970
        self.updatedAt = model.updatedAt.timeIntervalSince1970
        if !model.metadata.isEmpty {
            self.metadata = try? String(data: JSONEncoder().encode(model.metadata), encoding: .utf8)
        }
    }

    func toModel() -> MLModel {
        var metadataDict: [String: String] = [:]
        if let metadataStr = metadata,
           let data = metadataStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            metadataDict = decoded
        }

        let model = MLModel(
            id: id,
            name: name,
            framework: MLFramework(rawValue: framework) ?? .custom,
            status: ModelStatus(rawValue: status) ?? .draft,
            accuracy: accuracy ?? 0,
            fileSize: fileSize ?? 0,
            filePath: filePath,
            metadata: metadataDict
        )
        return model
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let framework = Column(CodingKeys.framework)
        static let status = Column(CodingKeys.status)
        static let accuracy = Column(CodingKeys.accuracy)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    static let runs = hasMany(TrainingRunRecord.self)
}

// MARK: - Training Run Record

struct TrainingRunRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "training_runs"

    var id: String
    var experimentId: String?
    var modelId: String
    var name: String
    var status: String
    var progress: Double
    var currentEpoch: Int
    var totalEpochs: Int
    var batchSize: Int
    var learningRate: Double
    var loss: Double?
    var accuracy: Double?
    var startedAt: Double
    var finishedAt: Double?
    var errorMessage: String?
    var config: String
    var architectureType: String

    enum CodingKeys: String, CodingKey {
        case id, name, status, progress, loss, accuracy, config
        case experimentId = "experiment_id"
        case modelId = "model_id"
        case currentEpoch = "current_epoch"
        case totalEpochs = "total_epochs"
        case batchSize = "batch_size"
        case learningRate = "learning_rate"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case errorMessage = "error_message"
        case architectureType = "architecture_type"
    }

    init(from run: TrainingRun, experimentId: String? = nil) {
        self.id = run.id
        self.experimentId = experimentId
        self.modelId = run.modelId
        self.name = run.name
        self.status = run.status.rawValue
        self.progress = run.progress
        self.currentEpoch = run.currentEpoch
        self.totalEpochs = run.totalEpochs
        self.batchSize = run.batchSize
        self.learningRate = run.learningRate
        self.loss = run.loss
        self.accuracy = run.accuracy
        self.startedAt = run.startedAt.timeIntervalSince1970
        self.finishedAt = run.finishedAt?.timeIntervalSince1970
        self.architectureType = run.architectureType

        // Serialize full config as JSON
        let configDict: [String: Any] = [
            "epochs": run.totalEpochs,
            "batchSize": run.batchSize,
            "learningRate": run.learningRate,
            "architectureType": run.architectureType
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: configDict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.config = jsonString
        } else {
            self.config = "{}"
        }
    }

    func toRun(modelName: String) -> TrainingRun {
        var run = TrainingRun(
            id: id,
            name: name,
            modelId: modelId,
            modelName: modelName,
            epochs: totalEpochs,
            batchSize: batchSize,
            learningRate: learningRate,
            architecture: architectureType
        )
        run.status = RunStatus(rawValue: status) ?? .queued
        run.progress = progress
        run.currentEpoch = currentEpoch
        run.loss = loss
        run.accuracy = accuracy
        run.finishedAt = finishedAt.map { Date(timeIntervalSince1970: $0) }
        return run
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let experimentId = Column(CodingKeys.experimentId)
        static let modelId = Column(CodingKeys.modelId)
        static let status = Column(CodingKeys.status)
        static let startedAt = Column(CodingKeys.startedAt)
    }

    static let model = belongsTo(ModelRecord.self)
    static let experiment = belongsTo(ExperimentRecord.self)
    static let metrics = hasMany(MetricRecord.self)
    static let logs = hasMany(RunLogRecord.self)
}

// MARK: - Metric Record

struct MetricRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "metrics"

    var id: Int64?
    var runId: String
    var epoch: Int
    var step: Int?
    var metricName: String
    var metricValue: Double
    var timestamp: Double

    enum CodingKeys: String, CodingKey {
        case id, epoch, step, timestamp
        case runId = "run_id"
        case metricName = "metric_name"
        case metricValue = "metric_value"
    }

    init(runId: String, epoch: Int, step: Int? = nil, name: String, value: Double) {
        self.runId = runId
        self.epoch = epoch
        self.step = step
        self.metricName = name
        self.metricValue = value
        self.timestamp = Date().timeIntervalSince1970
    }

    enum Columns {
        static let runId = Column(CodingKeys.runId)
        static let epoch = Column(CodingKeys.epoch)
        static let metricName = Column(CodingKeys.metricName)
    }

    static let run = belongsTo(TrainingRunRecord.self)
}

// MARK: - Run Log Record

struct RunLogRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "run_logs"

    var id: Int64?
    var runId: String
    var timestamp: Double
    var level: String
    var message: String

    enum CodingKeys: String, CodingKey {
        case id, timestamp, level, message
        case runId = "run_id"
    }

    init(runId: String, entry: LogEntry) {
        self.runId = runId
        self.timestamp = entry.timestamp.timeIntervalSince1970
        self.level = entry.level.rawValue
        self.message = entry.message
    }

    func toLogEntry() -> LogEntry {
        LogEntry(level: LogLevel(rawValue: level) ?? .info, message: message)
    }

    enum Columns {
        static let runId = Column(CodingKeys.runId)
        static let timestamp = Column(CodingKeys.timestamp)
    }

    static let run = belongsTo(TrainingRunRecord.self)
}

// MARK: - Dataset Record

struct DatasetRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "datasets"

    var id: String
    var name: String
    var type: String
    var path: String?
    var sampleCount: Int?
    var size: Int64?
    var classes: String?
    var createdAt: Double
    var metadata: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, path, size, classes, metadata
        case sampleCount = "sample_count"
        case createdAt = "created_at"
    }

    init(from dataset: Dataset) {
        self.id = dataset.id
        self.name = dataset.name
        self.type = dataset.type.rawValue
        self.path = dataset.path
        self.sampleCount = dataset.sampleCount
        self.size = dataset.size
        if !dataset.classes.isEmpty {
            self.classes = try? String(data: JSONEncoder().encode(dataset.classes), encoding: .utf8)
        }
        self.createdAt = dataset.createdAt.timeIntervalSince1970
        if !dataset.metadata.isEmpty {
            self.metadata = try? String(data: JSONEncoder().encode(dataset.metadata), encoding: .utf8)
        }
    }

    func toDataset() -> Dataset {
        var classesArray: [String] = []
        if let classesStr = classes,
           let data = classesStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            classesArray = decoded
        }

        var metadataDict: [String: String] = [:]
        if let metadataStr = metadata,
           let data = metadataStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            metadataDict = decoded
        }

        return Dataset(
            id: id,
            name: name,
            type: DatasetType(rawValue: type) ?? .custom,
            path: path,
            sampleCount: sampleCount ?? 0,
            size: size ?? 0,
            classes: classesArray,
            metadata: metadataDict
        )
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let type = Column(CodingKeys.type)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}

// MARK: - Artifact Record

struct ArtifactRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "artifacts"

    var sha256: String
    var runId: String?
    var type: String
    var name: String
    var size: Int64
    var createdAt: Double
    var localPath: String?

    enum CodingKeys: String, CodingKey {
        case sha256, type, name, size
        case runId = "run_id"
        case createdAt = "created_at"
        case localPath = "local_path"
    }

    enum ArtifactType: String, Codable {
        case checkpoint = "checkpoint"
        case model = "model"
        case log = "log"
        case plot = "plot"
        case data = "data"
    }

    enum Columns {
        static let sha256 = Column(CodingKeys.sha256)
        static let runId = Column(CodingKeys.runId)
        static let type = Column(CodingKeys.type)
    }

    static let run = belongsTo(TrainingRunRecord.self)
}

// MARK: - Inference Result Record

struct InferenceResultRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "inference_results"

    var id: String
    var modelId: String
    var predictions: String
    var inferenceTimeMs: Double
    var timestamp: Double

    enum CodingKeys: String, CodingKey {
        case id, predictions, timestamp
        case modelId = "model_id"
        case inferenceTimeMs = "inference_time_ms"
    }

    init(from result: InferenceResult) {
        self.id = result.id
        self.modelId = result.modelId
        self.predictions = (try? String(data: JSONEncoder().encode(result.predictions), encoding: .utf8)) ?? "[]"
        self.inferenceTimeMs = result.inferenceTimeMs
        self.timestamp = result.timestamp.timeIntervalSince1970
    }

    func toInferenceResult() -> InferenceResult? {
        guard let data = predictions.data(using: .utf8),
              let preds = try? JSONDecoder().decode([Prediction].self, from: data) else {
            return nil
        }

        return InferenceResult(
            id: id,
            requestId: id,
            modelId: modelId,
            predictions: preds,
            inferenceTimeMs: inferenceTimeMs,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let modelId = Column(CodingKeys.modelId)
        static let timestamp = Column(CodingKeys.timestamp)
    }

    static let model = belongsTo(ModelRecord.self)
}

// MARK: - Settings Record

struct SettingsRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "settings"

    var key: String
    var value: String
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case key, value
        case updatedAt = "updated_at"
    }

    enum Columns {
        static let key = Column(CodingKeys.key)
    }
}
