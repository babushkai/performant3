import Foundation
import MLX
import MLXNN
import AppKit

// MARK: - MLX Inference Service

/// Service for running inference on trained MLX models
actor MLXInferenceService {
    static let shared = MLXInferenceService()

    private var loadedModels: [String: Module] = [:]
    private var modelClassLabels: [String: [String]] = [:]
    private let checkpointManager = CheckpointManager.shared

    // MARK: - Inference

    func runInference(model: MLModel, imageURL: URL) async throws -> InferenceResult {
        let startTime = Date()

        // Load the model if not already loaded
        let mlxModel = try await loadModel(model)

        // Get class labels for this model
        let classLabels = getClassLabels(for: model)

        // Load and preprocess the image
        let inputArray = try preprocessImage(at: imageURL, for: model)

        // Run forward pass
        let logits = forwardPass(model: mlxModel, inputs: inputArray, training: false)
        eval(logits)

        // Get predictions with real class labels
        let predictions = extractPredictions(from: logits, classLabels: classLabels)

        let inferenceTime = Date().timeIntervalSince(startTime) * 1000 // ms

        return InferenceResult(
            id: UUID().uuidString,
            requestId: UUID().uuidString,
            modelId: model.id,
            predictions: predictions,
            inferenceTimeMs: inferenceTime,
            timestamp: Date()
        )
    }

    /// Get class labels from model metadata
    private func getClassLabels(for model: MLModel) -> [String] {
        // Try cached labels first
        if let cached = modelClassLabels[model.id] {
            return cached
        }

        // Try to load from model metadata
        if let labelsJson = model.metadata["classLabels"],
           let labelsData = labelsJson.data(using: .utf8),
           let labels = try? JSONDecoder().decode([String].self, from: labelsData) {
            modelClassLabels[model.id] = labels
            return labels
        }

        // Fallback to generic labels based on numClasses
        let numClasses = Int(model.metadata["numClasses"] ?? "10") ?? 10
        let fallbackLabels = (0..<numClasses).map { "Class \($0)" }
        return fallbackLabels
    }

    // MARK: - Model Loading

    private func loadModel(_ model: MLModel) async throws -> Module {
        // Return cached model if available
        if let cached = loadedModels[model.id] {
            return cached
        }

        guard let filePath = model.filePath else {
            throw MLXInferenceError.modelNotFound(model.name)
        }

        // Determine model architecture from metadata
        let modelArchitecture = getModelArchitecture(for: model)
        let mlxModel = try ModelFactory.create(from: modelArchitecture)

        // Load weights from checkpoint
        let checkpointURL = URL(fileURLWithPath: filePath)
        let loadedArrays = try MLX.loadArrays(url: checkpointURL)

        // Update model parameters
        var nestedParams = NestedDictionary<String, MLXArray>()
        for (key, array) in loadedArrays {
            nestedParams[key] = .value(array)
        }
        mlxModel.update(parameters: nestedParams)

        // Cache the model
        loadedModels[model.id] = mlxModel

        return mlxModel
    }

    /// Get model architecture from metadata
    private func getModelArchitecture(for model: MLModel) -> ModelArchitecture {
        guard let archType = model.metadata["architectureType"] else {
            return .defaultMLP
        }

        switch archType {
        case "MLP":
            return .defaultMLP
        case "CNN":
            return .defaultCNN
        case "ResNet":
            return .defaultResNet
        case "Transformer":
            return .defaultTransformer
        default:
            return .defaultMLP
        }
    }

    // MARK: - Image Preprocessing

    private func preprocessImage(at url: URL, for model: MLModel) throws -> MLXArray {
        guard let image = NSImage(contentsOf: url) else {
            throw MLXInferenceError.imageLoadFailed
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MLXInferenceError.imageLoadFailed
        }

        // Determine target size based on architecture
        let archType = model.metadata["architectureType"] ?? "MLP"
        let targetSize: Int
        switch archType {
        case "CNN":
            targetSize = 28 // CNN default for MNIST-style
        case "ResNet":
            targetSize = 28 // ResNet for MNIST
        case "Transformer":
            targetSize = 28 // Transformer input
        default:
            targetSize = 28 // MLP default
        }

        let resizedImage = resizeImage(cgImage, to: CGSize(width: targetSize, height: targetSize))

        // Convert to grayscale float array
        let pixelData = getPixelData(from: resizedImage)

        // Normalize to [0, 1]
        let normalizedData = pixelData.map { Float($0) / 255.0 }

        // Create MLXArray with appropriate shape for the architecture
        let inputSize = targetSize * targetSize
        switch archType {
        case "CNN":
            // CNN expects [batch, channels, height, width] format
            return MLXArray(normalizedData).reshaped([1, 1, targetSize, targetSize])
        case "ResNet":
            // ResNet also uses [batch, features] for our implementation
            return MLXArray(normalizedData).reshaped([1, inputSize])
        case "Transformer":
            // Transformer uses [batch, sequence_length, features] but our impl takes flat
            return MLXArray(normalizedData).reshaped([1, inputSize])
        default:
            // MLP expects [batch, features]
            return MLXArray(normalizedData).reshaped([1, inputSize])
        }
    }

    private func resizeImage(_ image: CGImage, to size: CGSize) -> CGImage {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))

        return context.makeImage()!
    }

    private func getPixelData(from image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Convert RGBA to grayscale
        var grayscale = [UInt8]()
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let r = Float(pixelData[i])
            let g = Float(pixelData[i + 1])
            let b = Float(pixelData[i + 2])
            let gray = UInt8(0.299 * r + 0.587 * g + 0.114 * b)
            grayscale.append(gray)
        }

        return grayscale
    }

    // MARK: - Prediction Extraction

    private func extractPredictions(from logits: MLXArray, classLabels: [String]) -> [Prediction] {
        // Apply softmax to get probabilities
        let maxLogit = logits.max(axis: -1, keepDims: true)
        let expLogits = exp(logits - maxLogit)
        let sumExp = expLogits.sum(axis: -1, keepDims: true)
        let probabilities = expLogits / sumExp
        eval(probabilities)

        // Get number of classes
        let numClasses = logits.dim(-1)

        // Extract all predictions with real class labels
        var predictions: [Prediction] = []
        let probsFlat = probabilities.reshaped([-1])

        for i in 0..<numClasses {
            let prob = probsFlat[i].item(Float.self)
            let label = i < classLabels.count ? classLabels[i] : "Class \(i)"
            predictions.append(Prediction(
                label: label,
                confidence: Double(prob)
            ))
        }

        // Sort by confidence (highest first)
        predictions.sort { $0.confidence > $1.confidence }

        // Return top 5 predictions
        return Array(predictions.prefix(5))
    }

    // MARK: - Cache Management

    func clearCache() {
        loadedModels.removeAll()
    }

    func unloadModel(_ modelId: String) {
        loadedModels.removeValue(forKey: modelId)
    }
}

// MARK: - Errors

enum MLXInferenceError: Error, LocalizedError {
    case modelNotFound(String)
    case imageLoadFailed
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Model '\(name)' not found or has no weights file"
        case .imageLoadFailed:
            return "Failed to load or process the input image"
        case .inferenceFailed(let reason):
            return "Inference failed: \(reason)"
        }
    }
}
