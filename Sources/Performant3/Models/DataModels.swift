import Foundation
import SwiftUI

// MARK: - ML Model

struct MLModel: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var framework: MLFramework
    var status: ModelStatus
    var accuracy: Double
    var fileSize: Int64
    var filePath: String?
    var createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]

    init(
        id: String = UUID().uuidString,
        name: String,
        framework: MLFramework,
        status: ModelStatus = .draft,
        accuracy: Double = 0,
        fileSize: Int64 = 0,
        filePath: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.framework = framework
        self.status = status
        self.accuracy = accuracy
        self.fileSize = fileSize
        self.filePath = filePath
        self.createdAt = Date()
        self.updatedAt = Date()
        self.metadata = metadata
    }
}

enum ModelStatus: String, Codable, CaseIterable {
    case draft = "Draft"
    case importing = "Importing"
    case ready = "Ready"
    case training = "Training"
    case deployed = "Deployed"
    case failed = "Failed"
    case archived = "Archived"
    case deprecated = "Deprecated"

    var color: Color {
        switch self {
        case .draft: return .gray
        case .importing: return .orange
        case .ready: return .green
        case .training: return .blue
        case .deployed: return .purple
        case .failed: return .red
        case .archived: return .secondary
        case .deprecated: return .brown
        }
    }

    var icon: String {
        switch self {
        case .draft: return "doc"
        case .importing: return "arrow.down.circle"
        case .ready: return "checkmark.circle"
        case .training: return "gear"
        case .deployed: return "icloud"
        case .failed: return "xmark.circle"
        case .archived: return "archivebox"
        case .deprecated: return "exclamationmark.triangle"
        }
    }

    var isActive: Bool {
        switch self {
        case .archived, .deprecated: return false
        default: return true
        }
    }
}

enum MLFramework: String, Codable, CaseIterable {
    case coreML = "Core ML"
    case pytorch = "PyTorch"
    case tensorflow = "TensorFlow"
    case mlx = "MLX"
    case onnx = "ONNX"
    case custom = "Custom"

    var icon: String {
        switch self {
        case .coreML: return "apple.logo"
        case .pytorch: return "flame"
        case .tensorflow: return "brain"
        case .mlx: return "cpu"
        case .onnx: return "square.stack.3d.up"
        case .custom: return "cube"
        }
    }

    var color: Color {
        switch self {
        case .coreML: return .blue
        case .pytorch: return .orange
        case .tensorflow: return .red
        case .mlx: return .purple
        case .onnx: return .green
        case .custom: return .gray
        }
    }

    var fileExtension: String {
        switch self {
        case .coreML: return "mlmodel"
        case .pytorch: return "pt"
        case .tensorflow: return "pb"
        case .mlx: return "safetensors"
        case .onnx: return "onnx"
        case .custom: return "*"
        }
    }
}

// MARK: - Training Run

struct TrainingRun: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var modelId: String
    var modelName: String
    var experimentId: String?  // Optional experiment this run belongs to
    var status: RunStatus
    var progress: Double
    var currentEpoch: Int
    var totalEpochs: Int
    var batchSize: Int
    var learningRate: Double
    var architectureType: String  // Store as string for Codable compatibility
    var loss: Double?
    var accuracy: Double?
    var startedAt: Date
    var finishedAt: Date?
    var logs: [LogEntry]
    var metrics: [MetricPoint]

    init(
        id: String = UUID().uuidString,
        name: String,
        modelId: String,
        modelName: String,
        epochs: Int = 10,
        batchSize: Int = 32,
        learningRate: Double = 0.001,
        architecture: String = "MLP",
        experimentId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.modelId = modelId
        self.modelName = modelName
        self.experimentId = experimentId
        self.status = .queued
        self.progress = 0
        self.currentEpoch = 0
        self.totalEpochs = epochs
        self.batchSize = batchSize
        self.learningRate = learningRate
        self.architectureType = architecture
        self.startedAt = Date()
        self.logs = []
        self.metrics = []
    }

    var duration: String {
        let end = finishedAt ?? Date()
        let interval = end.timeIntervalSince(startedAt)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        }
        return String(format: "%ds", seconds)
    }
}

enum RunStatus: String, Codable, CaseIterable {
    case queued = "Queued"
    case running = "Running"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"

    var color: Color {
        switch self {
        case .queued: return .gray
        case .running: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .queued: return "clock"
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }
}

struct LogEntry: Identifiable, Codable, Hashable {
    let id: String
    let timestamp: Date
    let level: LogLevel
    let message: String

    init(level: LogLevel, message: String) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.level = level
        self.message = message
    }
}

enum LogLevel: String, Codable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    case debug = "DEBUG"

    var color: Color {
        switch self {
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        case .debug: return .gray
        }
    }

    var prefix: String {
        switch self {
        case .info: return "[INFO]"
        case .warning: return "[WARN]"
        case .error: return "[ERROR]"
        case .debug: return "[DEBUG]"
        }
    }
}

struct MetricPoint: Identifiable, Codable, Hashable {
    let id: String
    let epoch: Int
    let loss: Double
    let accuracy: Double
    let timestamp: Date

    init(epoch: Int, loss: Double, accuracy: Double) {
        self.id = UUID().uuidString
        self.epoch = epoch
        self.loss = loss
        self.accuracy = accuracy
        self.timestamp = Date()
    }
}

// MARK: - Dataset

struct Dataset: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var description: String
    var type: DatasetType
    var status: DatasetStatus
    var path: String?
    var sampleCount: Int
    var size: Int64
    var classes: [String]
    var createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        type: DatasetType,
        status: DatasetStatus = .active,
        path: String? = nil,
        sampleCount: Int = 0,
        size: Int64 = 0,
        classes: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.status = status
        self.path = path
        self.sampleCount = sampleCount
        self.size = size
        self.classes = classes
        self.createdAt = Date()
        self.updatedAt = Date()
        self.metadata = metadata
    }
}

enum DatasetStatus: String, Codable, CaseIterable {
    case active = "Active"
    case processing = "Processing"
    case archived = "Archived"
    case deprecated = "Deprecated"

    var color: Color {
        switch self {
        case .active: return .green
        case .processing: return .orange
        case .archived: return .secondary
        case .deprecated: return .brown
        }
    }

    var icon: String {
        switch self {
        case .active: return "checkmark.circle"
        case .processing: return "arrow.triangle.2.circlepath"
        case .archived: return "archivebox"
        case .deprecated: return "exclamationmark.triangle"
        }
    }

    var isActive: Bool {
        switch self {
        case .archived, .deprecated: return false
        default: return true
        }
    }
}

enum DatasetType: String, Codable, CaseIterable {
    case images = "Images"
    case text = "Text"
    case audio = "Audio"
    case video = "Video"
    case tabular = "Tabular"
    case custom = "Custom"

    var icon: String {
        switch self {
        case .images: return "photo.stack"
        case .text: return "doc.text"
        case .audio: return "waveform"
        case .video: return "video"
        case .tabular: return "tablecells"
        case .custom: return "folder"
        }
    }

    var color: Color {
        switch self {
        case .images: return .blue
        case .text: return .green
        case .audio: return .purple
        case .video: return .red
        case .tabular: return .orange
        case .custom: return .gray
        }
    }
}

// MARK: - Inference

struct InferenceRequest: Identifiable, Codable {
    let id: String
    let modelId: String
    let inputPath: String
    let timestamp: Date

    init(modelId: String, inputPath: String) {
        self.id = UUID().uuidString
        self.modelId = modelId
        self.inputPath = inputPath
        self.timestamp = Date()
    }
}

struct InferenceResult: Identifiable, Codable, Hashable {
    let id: String
    let requestId: String
    let modelId: String
    let predictions: [Prediction]
    let inferenceTimeMs: Double
    let timestamp: Date
}

struct Prediction: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let confidence: Double

    init(label: String, confidence: Double) {
        self.id = UUID().uuidString
        self.label = label
        self.confidence = confidence
    }
}

// MARK: - App Settings

struct AppSettings: Codable, Equatable {
    var gpuEnabled: Bool
    var autoSave: Bool
    var autoSaveCheckpoints: Bool
    var showNotifications: Bool
    var cacheModels: Bool
    var maxConcurrentRuns: Int
    var defaultEpochs: Int
    var defaultBatchSize: Int
    var defaultLearningRate: Double
    var theme: String
    var modelsDirectory: String
    var datasetsDirectory: String

    static var `default`: AppSettings {
        AppSettings(
            gpuEnabled: true,
            autoSave: true,
            autoSaveCheckpoints: true,
            showNotifications: true,
            cacheModels: true,
            maxConcurrentRuns: 2,
            defaultEpochs: 10,
            defaultBatchSize: 32,
            defaultLearningRate: 0.001,
            theme: "system",
            modelsDirectory: "Models",
            datasetsDirectory: "Datasets"
        )
    }
}

// MARK: - Helpers

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    let secs = Int(seconds) % 60
    if hours > 0 {
        return String(format: "%dh %dm", hours, minutes)
    } else if minutes > 0 {
        return String(format: "%dm %ds", minutes, secs)
    }
    return String(format: "%ds", secs)
}
