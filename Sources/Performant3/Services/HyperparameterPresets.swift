import Foundation

/// Predefined hyperparameter configurations for common training scenarios
struct HyperparameterPreset: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let category: Category
    let config: TrainingConfig

    enum Category: String, Codable, CaseIterable {
        case quickTest = "Quick Test"
        case balanced = "Balanced"
        case highAccuracy = "High Accuracy"
        case lowMemory = "Low Memory"
        case objectDetection = "Object Detection"
        case custom = "Custom"
    }
}

/// Manages hyperparameter presets
class HyperparameterPresetsManager {
    static let shared = HyperparameterPresetsManager()

    private(set) var presets: [HyperparameterPreset] = []
    private let customPresetsKey = "customHyperparameterPresets"

    init() {
        loadBuiltInPresets()
        loadCustomPresets()
    }

    // MARK: - Built-in Presets

    private func loadBuiltInPresets() {
        presets = [
            // Quick Test - Fast iteration for debugging
            HyperparameterPreset(
                id: "quick-test",
                name: "Quick Test",
                description: "Fast training for testing and debugging. Low epochs, small batch size.",
                category: .quickTest,
                config: TrainingConfig(
                    epochs: 5,
                    batchSize: 8,
                    learningRate: 0.01,
                    optimizer: .adam,
                    lossFunction: .crossEntropy,
                    validationSplit: 0.2,
                    earlyStopping: false,
                    patience: 3,
                    architecture: .cnn,
                    saveCheckpoints: false,
                    checkpointFrequency: 5,
                    keepCheckpoints: 1,
                    allowSyntheticFallback: true
                )
            ),

            // Balanced - Good default for most cases
            HyperparameterPreset(
                id: "balanced",
                name: "Balanced",
                description: "Recommended settings for most training tasks. Good balance of speed and accuracy.",
                category: .balanced,
                config: TrainingConfig(
                    epochs: 50,
                    batchSize: 32,
                    learningRate: 0.001,
                    optimizer: .adam,
                    lossFunction: .crossEntropy,
                    validationSplit: 0.2,
                    earlyStopping: true,
                    patience: 5,
                    architecture: .cnn,
                    saveCheckpoints: true,
                    checkpointFrequency: 10,
                    keepCheckpoints: 3,
                    allowSyntheticFallback: true
                )
            ),

            // High Accuracy - Best results, slower training
            HyperparameterPreset(
                id: "high-accuracy",
                name: "High Accuracy",
                description: "Optimized for maximum accuracy. Longer training with fine-tuned learning rate.",
                category: .highAccuracy,
                config: TrainingConfig(
                    epochs: 100,
                    batchSize: 16,
                    learningRate: 0.0001,
                    optimizer: .adamw,
                    lossFunction: .crossEntropy,
                    validationSplit: 0.15,
                    earlyStopping: true,
                    patience: 10,
                    architecture: .resnet,
                    saveCheckpoints: true,
                    checkpointFrequency: 5,
                    keepCheckpoints: 5,
                    allowSyntheticFallback: true
                )
            ),

            // Low Memory - For constrained environments
            HyperparameterPreset(
                id: "low-memory",
                name: "Low Memory",
                description: "Optimized for systems with limited GPU memory. Smaller batches, gradient accumulation.",
                category: .lowMemory,
                config: TrainingConfig(
                    epochs: 50,
                    batchSize: 4,
                    learningRate: 0.0005,
                    optimizer: .adam,
                    lossFunction: .crossEntropy,
                    validationSplit: 0.2,
                    earlyStopping: true,
                    patience: 5,
                    architecture: .mlp,
                    saveCheckpoints: true,
                    checkpointFrequency: 10,
                    keepCheckpoints: 2,
                    allowSyntheticFallback: true
                )
            ),

            // YOLOv8 Quick
            HyperparameterPreset(
                id: "yolo-quick",
                name: "YOLOv8 Quick",
                description: "Fast YOLOv8 training for testing object detection.",
                category: .objectDetection,
                config: TrainingConfig(
                    epochs: 10,
                    batchSize: 8,
                    learningRate: 0.01,
                    optimizer: .adam,
                    lossFunction: .crossEntropy,
                    validationSplit: 0.2,
                    earlyStopping: false,
                    patience: 3,
                    architecture: .yolov8,
                    saveCheckpoints: true,
                    checkpointFrequency: 5,
                    keepCheckpoints: 2,
                    allowSyntheticFallback: false
                )
            ),

            // YOLOv8 Production
            HyperparameterPreset(
                id: "yolo-production",
                name: "YOLOv8 Production",
                description: "Full YOLOv8 training for production object detection models.",
                category: .objectDetection,
                config: TrainingConfig(
                    epochs: 100,
                    batchSize: 16,
                    learningRate: 0.01,
                    optimizer: .adam,
                    lossFunction: .crossEntropy,
                    validationSplit: 0.1,
                    earlyStopping: false,
                    patience: 10,
                    architecture: .yolov8,
                    saveCheckpoints: true,
                    checkpointFrequency: 10,
                    keepCheckpoints: 5,
                    allowSyntheticFallback: false
                )
            ),

            // Transformer
            HyperparameterPreset(
                id: "transformer",
                name: "Transformer",
                description: "Settings optimized for transformer-based models.",
                category: .balanced,
                config: TrainingConfig(
                    epochs: 30,
                    batchSize: 16,
                    learningRate: 0.0001,
                    optimizer: .adamw,
                    lossFunction: .crossEntropy,
                    validationSplit: 0.1,
                    earlyStopping: true,
                    patience: 5,
                    architecture: .transformer,
                    saveCheckpoints: true,
                    checkpointFrequency: 5,
                    keepCheckpoints: 3,
                    allowSyntheticFallback: false
                )
            )
        ]
    }

    // MARK: - Custom Presets

    private func loadCustomPresets() {
        guard let data = UserDefaults.standard.data(forKey: customPresetsKey),
              let customPresets = try? JSONDecoder().decode([HyperparameterPreset].self, from: data) else {
            return
        }
        presets.append(contentsOf: customPresets)
    }

    func saveCustomPreset(_ preset: HyperparameterPreset) {
        var customPresets = presets.filter { $0.category == .custom }
        customPresets.append(preset)

        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: customPresetsKey)
        }

        presets.append(preset)
    }

    func deletePreset(id: String) {
        presets.removeAll { $0.id == id }

        // Update stored custom presets
        let customPresets = presets.filter { $0.category == .custom }
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: customPresetsKey)
        }
    }

    // MARK: - Queries

    func presets(for category: HyperparameterPreset.Category) -> [HyperparameterPreset] {
        presets.filter { $0.category == category }
    }

    func presets(for architecture: ArchitectureType) -> [HyperparameterPreset] {
        presets.filter { $0.config.architecture == architecture }
    }

    func recommendedPreset(for architecture: ArchitectureType) -> HyperparameterPreset? {
        switch architecture {
        case .yolov8:
            return presets.first { $0.id == "yolo-production" }
        case .transformer:
            return presets.first { $0.id == "transformer" }
        case .resnet:
            return presets.first { $0.id == "high-accuracy" }
        default:
            return presets.first { $0.id == "balanced" }
        }
    }
}

// MARK: - Learning Rate Schedules

enum LearningRateSchedule: String, Codable, CaseIterable {
    case constant = "Constant"
    case stepDecay = "Step Decay"
    case exponentialDecay = "Exponential Decay"
    case cosineAnnealing = "Cosine Annealing"
    case warmupCosine = "Warmup + Cosine"
    case oneCycle = "One Cycle"

    var description: String {
        switch self {
        case .constant:
            return "Learning rate stays constant throughout training"
        case .stepDecay:
            return "Reduce learning rate by factor every N epochs"
        case .exponentialDecay:
            return "Exponentially decrease learning rate each epoch"
        case .cosineAnnealing:
            return "Smoothly decrease learning rate following cosine curve"
        case .warmupCosine:
            return "Linear warmup followed by cosine decay"
        case .oneCycle:
            return "Increase then decrease learning rate in one cycle"
        }
    }

    func computeLR(baseLR: Double, epoch: Int, totalEpochs: Int, warmupEpochs: Int = 5) -> Double {
        switch self {
        case .constant:
            return baseLR

        case .stepDecay:
            let stepSize = totalEpochs / 3
            let decay = pow(0.1, Double(epoch / max(stepSize, 1)))
            return baseLR * decay

        case .exponentialDecay:
            let decay = pow(0.95, Double(epoch))
            return baseLR * decay

        case .cosineAnnealing:
            let progress = Double(epoch) / Double(totalEpochs)
            return baseLR * 0.5 * (1 + cos(.pi * progress))

        case .warmupCosine:
            if epoch < warmupEpochs {
                return baseLR * Double(epoch + 1) / Double(warmupEpochs)
            } else {
                let progress = Double(epoch - warmupEpochs) / Double(totalEpochs - warmupEpochs)
                return baseLR * 0.5 * (1 + cos(.pi * progress))
            }

        case .oneCycle:
            let midpoint = totalEpochs / 2
            if epoch < midpoint {
                let progress = Double(epoch) / Double(midpoint)
                return baseLR * (1 + 9 * progress) // Increase to 10x
            } else {
                let progress = Double(epoch - midpoint) / Double(totalEpochs - midpoint)
                return baseLR * 10 * (1 - progress) // Decrease from 10x
            }
        }
    }
}
