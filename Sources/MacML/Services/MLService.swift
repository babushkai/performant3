import Foundation
import CoreML
import Vision
import AppKit

actor MLService {
    static let shared = MLService()

    private var loadedModels: [String: MLModel] = [:]
    private var compiledModels: [String: VNCoreMLModel] = [:]

    // MARK: - Model Loading

    func loadModel(_ model: MLModel) async throws -> VNCoreMLModel {
        if let cached = compiledModels[model.id] {
            return cached
        }

        guard let filePath = model.filePath else {
            throw MLServiceError.modelNotFound
        }

        let modelURL = URL(fileURLWithPath: filePath)

        // Check if it's a compiled model or needs compilation
        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else {
            compiledURL = try await compileModel(at: modelURL)
        }

        let coreMLModel = try CoreML.MLModel(contentsOf: compiledURL)
        let vnModel = try VNCoreMLModel(for: coreMLModel)

        compiledModels[model.id] = vnModel
        return vnModel
    }

    private func compileModel(at url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let compiledURL = try CoreML.MLModel.compileModel(at: url)
                    continuation.resume(returning: compiledURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func unloadModel(_ modelId: String) {
        compiledModels.removeValue(forKey: modelId)
    }

    // MARK: - Image Classification

    func classifyImage(model: MLModel, imageURL: URL) async throws -> InferenceResult {
        let startTime = Date()

        let vnModel = try await loadModel(model)

        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MLServiceError.invalidInput
        }

        let predictions = try await performClassification(vnModel: vnModel, cgImage: cgImage)

        let inferenceTime = Date().timeIntervalSince(startTime) * 1000

        return InferenceResult(
            id: UUID().uuidString,
            requestId: UUID().uuidString,
            modelId: model.id,
            predictions: predictions,
            inferenceTimeMs: inferenceTime,
            timestamp: Date()
        )
    }

    private func performClassification(vnModel: VNCoreMLModel, cgImage: CGImage) async throws -> [Prediction] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: vnModel) { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let predictions = results.prefix(5).map { observation in
                    Prediction(
                        label: observation.identifier,
                        confidence: Double(observation.confidence)
                    )
                }

                continuation.resume(returning: predictions)
            }

            request.imageCropAndScaleOption = .centerCrop

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Object Detection

    func detectObjects(model: MLModel, imageURL: URL) async throws -> [DetectedObject] {
        let vnModel = try await loadModel(model)

        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MLServiceError.invalidInput
        }

        return try await performObjectDetection(vnModel: vnModel, cgImage: cgImage)
    }

    private func performObjectDetection(vnModel: VNCoreMLModel, cgImage: CGImage) async throws -> [DetectedObject] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: vnModel) { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let objects = results.map { observation in
                    DetectedObject(
                        label: observation.labels.first?.identifier ?? "Unknown",
                        confidence: Double(observation.confidence),
                        boundingBox: observation.boundingBox
                    )
                }

                continuation.resume(returning: objects)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Model Info

    func getModelInfo(_ model: MLModel) async throws -> ModelInfo {
        guard let filePath = model.filePath else {
            throw MLServiceError.modelNotFound
        }

        let modelURL = URL(fileURLWithPath: filePath)

        // Try to get model description
        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else {
            compiledURL = try await compileModel(at: modelURL)
        }

        let coreMLModel = try CoreML.MLModel(contentsOf: compiledURL)
        let description = coreMLModel.modelDescription

        var inputDescriptions: [String] = []
        var outputDescriptions: [String] = []

        for (name, feature) in description.inputDescriptionsByName {
            inputDescriptions.append("\(name): \(feature.type.rawValue)")
        }

        for (name, feature) in description.outputDescriptionsByName {
            outputDescriptions.append("\(name): \(feature.type.rawValue)")
        }

        return ModelInfo(
            author: description.metadata[MLModelMetadataKey.author] as? String ?? "Unknown",
            description: description.metadata[MLModelMetadataKey.description] as? String ?? "",
            version: description.metadata[MLModelMetadataKey.versionString] as? String ?? "1.0",
            inputs: inputDescriptions,
            outputs: outputDescriptions
        )
    }

    // MARK: - Batch Inference

    func batchClassify(model: MLModel, imageURLs: [URL], progress: @escaping (Double) -> Void) async throws -> [InferenceResult] {
        var results: [InferenceResult] = []
        let total = Double(imageURLs.count)

        for (index, url) in imageURLs.enumerated() {
            let result = try await classifyImage(model: model, imageURL: url)
            results.append(result)
            progress(Double(index + 1) / total)
        }

        return results
    }
}

struct DetectedObject: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Double
    let boundingBox: CGRect
}

struct ModelInfo {
    let author: String
    let description: String
    let version: String
    let inputs: [String]
    let outputs: [String]
}

enum MLServiceError: Error, LocalizedError {
    case modelNotFound
    case invalidInput
    case compilationFailed
    case inferenceFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "Model file not found"
        case .invalidInput: return "Invalid input data"
        case .compilationFailed: return "Failed to compile model"
        case .inferenceFailed: return "Inference failed"
        }
    }
}

extension MLFeatureType {
    var rawValue: String {
        switch self {
        case .invalid: return "Invalid"
        case .int64: return "Int64"
        case .double: return "Double"
        case .string: return "String"
        case .image: return "Image"
        case .multiArray: return "MultiArray"
        case .dictionary: return "Dictionary"
        case .sequence: return "Sequence"
        case .state: return "State"
        @unknown default: return "Unknown"
        }
    }
}
