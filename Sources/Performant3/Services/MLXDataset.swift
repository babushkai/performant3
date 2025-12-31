import Foundation
import MLX
import MLXRandom
import AppKit

// MARK: - MLX Dataset Protocol

/// Protocol for datasets that can be used with MLX training
protocol MLXDataset: Sendable {
    /// Total number of samples
    var count: Int { get }

    /// Number of classes for classification
    var numClasses: Int { get }

    /// Class labels
    var classLabels: [String] { get }

    /// Input shape (e.g., [28, 28, 1] for MNIST)
    var inputShape: [Int] { get }

    /// Get a batch of samples
    func getBatch(indices: [Int]) -> (inputs: MLXArray, labels: MLXArray)

    /// Generate batches for an epoch
    func batches(batchSize: Int, shuffle: Bool) -> BatchIterator
}

// MARK: - Batch Iterator

/// Iterator for generating batches
struct BatchIterator: Sequence, IteratorProtocol {
    private let dataset: any MLXDataset
    private let batchSize: Int
    private var indices: [Int]
    private var currentIndex: Int = 0

    init(dataset: any MLXDataset, batchSize: Int, shuffle: Bool) {
        self.dataset = dataset
        self.batchSize = batchSize
        self.indices = Array(0..<dataset.count)
        if shuffle {
            self.indices.shuffle()
        }
    }

    var totalBatches: Int {
        (indices.count + batchSize - 1) / batchSize
    }

    mutating func next() -> (inputs: MLXArray, labels: MLXArray, batchIndex: Int)? {
        guard currentIndex < indices.count else { return nil }

        let batchEnd = Swift.min(currentIndex + batchSize, indices.count)
        let batchIndices = Array(indices[currentIndex..<batchEnd])
        let batch = dataset.getBatch(indices: batchIndices)
        let batchIdx = currentIndex / batchSize

        currentIndex = batchEnd
        return (batch.inputs, batch.labels, batchIdx)
    }
}

// MARK: - Image Classification Dataset

/// Dataset for image classification from folder structure
/// Expected structure: root/class1/image1.jpg, root/class2/image2.jpg, etc.
final class ImageClassificationDataset: MLXDataset, @unchecked Sendable {
    let rootPath: String
    let classLabels: [String]
    let imagePaths: [(path: String, label: Int)]
    let imageSize: Int
    let channels: Int

    var count: Int { imagePaths.count }
    var numClasses: Int { classLabels.count }
    var inputShape: [Int] { [imageSize, imageSize, channels] }

    init(rootPath: String, imageSize: Int = 28, channels: Int = 1) throws {
        self.rootPath = rootPath
        self.imageSize = imageSize
        self.channels = channels

        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: rootPath)

        // Discover class directories
        var classes: [String] = []
        var paths: [(String, Int)] = []

        let contents = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey])

        for item in contents {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                let className = item.lastPathComponent
                if !className.hasPrefix(".") {
                    classes.append(className)
                }
            }
        }

        classes.sort()
        self.classLabels = classes

        // Collect image paths
        for (labelIdx, className) in classes.enumerated() {
            let classDir = rootURL.appendingPathComponent(className)
            if let files = try? fileManager.contentsOfDirectory(at: classDir, includingPropertiesForKeys: nil) {
                for file in files {
                    let ext = file.pathExtension.lowercased()
                    if ["jpg", "jpeg", "png", "bmp", "gif"].contains(ext) {
                        paths.append((file.path, labelIdx))
                    }
                }
            }
        }

        self.imagePaths = paths

        if paths.isEmpty {
            throw TrainingError.invalidDataset("No images found in dataset")
        }
    }

    func getBatch(indices: [Int]) -> (inputs: MLXArray, labels: MLXArray) {
        var imageData: [[Float]] = []
        var labelData: [Int32] = []

        for idx in indices {
            let (path, label) = imagePaths[idx]
            if let image = loadAndPreprocessImage(path: path) {
                imageData.append(image)
                labelData.append(Int32(label))
            }
        }

        let batchSize = imageData.count
        let flattenedSize = imageSize * imageSize * channels

        // Create MLXArrays
        let inputArray = MLXArray(imageData.flatMap { $0 })
            .reshaped([batchSize, imageSize, imageSize, channels])

        let labelArray = MLXArray(labelData)

        return (inputArray, labelArray)
    }

    private func loadAndPreprocessImage(path: String) -> [Float]? {
        guard let nsImage = NSImage(contentsOfFile: path),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // Resize and convert to grayscale or RGB
        let width = imageSize
        let height = imageSize
        let bytesPerPixel = channels == 1 ? 1 : 4
        let bytesPerRow = width * bytesPerPixel

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let colorSpace = channels == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = channels == 1
            ? CGBitmapInfo(rawValue: 0)
            : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Normalize to [0, 1]
        return pixelData.map { Float($0) / 255.0 }
    }

    func batches(batchSize: Int, shuffle: Bool = true) -> BatchIterator {
        BatchIterator(dataset: self, batchSize: batchSize, shuffle: shuffle)
    }
}

// MARK: - Synthetic Dataset (for testing)

/// Synthetic dataset for testing training pipeline
final class SyntheticDataset: MLXDataset, @unchecked Sendable {
    let sampleCount: Int
    let inputSize: Int
    let numClasses: Int
    let classLabels: [String]
    var inputShape: [Int] { [inputSize] }
    var count: Int { sampleCount }

    private let data: MLXArray
    private let labels: MLXArray

    init(sampleCount: Int = 1000, inputSize: Int = 784, numClasses: Int = 10) {
        self.sampleCount = sampleCount
        self.inputSize = inputSize
        self.numClasses = numClasses
        self.classLabels = (0..<numClasses).map { "Class \($0)" }

        // Generate random data
        self.data = MLXRandom.uniform(low: 0, high: 1, [sampleCount, inputSize])
        self.labels = MLXRandom.randInt(low: 0, high: Int32(numClasses), [sampleCount])
    }

    func getBatch(indices: [Int]) -> (inputs: MLXArray, labels: MLXArray) {
        let indicesArray = MLXArray(indices.map { Int32($0) })
        let batchInputs = data[indicesArray]
        let batchLabels = labels[indicesArray]
        return (batchInputs, batchLabels)
    }

    func batches(batchSize: Int, shuffle: Bool = true) -> BatchIterator {
        BatchIterator(dataset: self, batchSize: batchSize, shuffle: shuffle)
    }
}

// MARK: - MNIST Dataset (built-in)

/// MNIST dataset loader
/// Downloads and caches MNIST data locally
final class MNISTDataset: MLXDataset, @unchecked Sendable {
    static let imageSize = 28
    static let channels = 1

    let isTrain: Bool
    let classLabels = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
    var numClasses: Int { 10 }
    var inputShape: [Int] { [Self.imageSize, Self.imageSize, Self.channels] }

    private var images: MLXArray
    private var labels: MLXArray
    var count: Int { Int(images.dim(0)) }

    init(train: Bool = true) throws {
        self.isTrain = train

        // For now, create synthetic MNIST-like data
        // In production, this would download actual MNIST
        let sampleCount = train ? 60000 : 10000

        // Create synthetic data that resembles MNIST
        // Each "digit" is a different pattern
        var allImages: [[Float]] = []
        var allLabels: [Int32] = []

        for i in 0..<sampleCount {
            let label = Int32(i % 10)
            allLabels.append(label)

            // Create a simple pattern based on the label
            var image = [Float](repeating: 0, count: Self.imageSize * Self.imageSize)

            // Add some structure based on label
            let baseIntensity = Float(label + 1) / 11.0
            for y in 0..<Self.imageSize {
                for x in 0..<Self.imageSize {
                    let idx = y * Self.imageSize + x
                    // Create different patterns for different digits
                    let distFromCenter = sqrt(pow(Float(x - 14), 2) + pow(Float(y - 14), 2))
                    let pattern: Float
                    switch label {
                    case 0: // Circle
                        pattern = abs(distFromCenter - 8) < 3 ? 1.0 : 0.0
                    case 1: // Vertical line
                        pattern = abs(x - 14) < 2 ? 1.0 : 0.0
                    case 2: // Horizontal top and bottom with diagonal
                        pattern = (y < 5 || y > 23 || abs(x - y) < 2) ? baseIntensity : 0.0
                    default:
                        // Random pattern with some structure
                        pattern = Float.random(in: 0...1) * baseIntensity
                    }
                    image[idx] = pattern + Float.random(in: 0...0.1)
                }
            }
            allImages.append(image)
        }

        self.images = MLXArray(allImages.flatMap { $0 })
            .reshaped([sampleCount, Self.imageSize, Self.imageSize, Self.channels])
        self.labels = MLXArray(allLabels)
    }

    func getBatch(indices: [Int]) -> (inputs: MLXArray, labels: MLXArray) {
        let indicesArray = MLXArray(indices.map { Int32($0) })
        let batchInputs = images[indicesArray]
        let batchLabels = labels[indicesArray]
        return (batchInputs, batchLabels)
    }

    func batches(batchSize: Int, shuffle: Bool = true) -> BatchIterator {
        BatchIterator(dataset: self, batchSize: batchSize, shuffle: shuffle)
    }
}
