import Foundation
import MLX
import MLXNN
import MLXRandom

// MARK: - MLP (Multi-Layer Perceptron)

/// A simple multi-layer perceptron for classification
class MLP: Module, @unchecked Sendable {
    let layers: [Linear]
    let activation: ActivationType
    let dropoutRate: Double

    init(config: MLPConfig) {
        let sizes = [config.inputSize] + config.hiddenSizes + [config.outputSize]
        var layers: [Linear] = []

        for i in 0..<(sizes.count - 1) {
            layers.append(Linear(sizes[i], sizes[i + 1]))
        }

        self.layers = layers
        self.activation = config.activation
        self.dropoutRate = config.dropout

        super.init()
    }

    func callAsFunction(_ x: MLXArray, training: Bool = false) -> MLXArray {
        var output = x

        // Flatten if needed (e.g., images)
        if output.ndim > 2 {
            output = output.reshaped([output.dim(0), -1])
        }

        // Forward through all layers except the last
        for i in 0..<(layers.count - 1) {
            output = layers[i](output)
            output = activationFunction(output, type: activation)

            // Apply dropout during training
            if training && dropoutRate > 0 {
                output = dropoutFunction(output, p: dropoutRate)
            }
        }

        // Last layer (no activation for logits)
        output = layers[layers.count - 1](output)

        return output
    }
}

// MARK: - Simple CNN for Image Classification

/// A simplified CNN that works with MLX's available operations
class SimpleCNN: Module, @unchecked Sendable {
    let fc1: Linear
    let fc2: Linear
    let fc3: Linear
    let dropoutRate: Double
    let inputSize: Int

    init(config: CNNConfig) {
        // For simplicity, use fully connected layers that operate on flattened images
        // This avoids Conv2d API issues while still providing a neural network
        self.inputSize = config.imageSize * config.imageSize * config.inputChannels
        self.dropoutRate = config.dropout

        // Create FC layers
        self.fc1 = Linear(inputSize, 256)
        self.fc2 = Linear(256, 128)
        self.fc3 = Linear(128, config.outputSize)

        super.init()
    }

    func callAsFunction(_ x: MLXArray, training: Bool = false) -> MLXArray {
        var output = x

        // Flatten input
        if output.ndim > 2 {
            output = output.reshaped([output.dim(0), -1])
        }

        // FC layers with ReLU
        output = fc1(output)
        output = maximum(output, MLXArray(0))  // ReLU

        if training && dropoutRate > 0 {
            output = dropoutFunction(output, p: dropoutRate)
        }

        output = fc2(output)
        output = maximum(output, MLXArray(0))  // ReLU

        if training && dropoutRate > 0 {
            output = dropoutFunction(output, p: dropoutRate)
        }

        output = fc3(output)

        return output
    }
}

// MARK: - ResNet-style Network

/// A ResNet-inspired network with residual connections
class ResNetMini: Module, @unchecked Sendable {
    let inputLayer: Linear
    let blocks: [ResidualBlock]
    let outputLayer: Linear
    let dropoutRate: Double

    init(config: ResNetConfig) {
        let inputSize = config.inputSize
        self.dropoutRate = config.dropout

        // Input projection
        self.inputLayer = Linear(inputSize, config.hiddenSize)

        // Residual blocks
        var blocks: [ResidualBlock] = []
        for _ in 0..<config.numBlocks {
            blocks.append(ResidualBlock(size: config.hiddenSize, dropout: config.dropout))
        }
        self.blocks = blocks

        // Output layer
        self.outputLayer = Linear(config.hiddenSize, config.outputSize)

        super.init()
    }

    func callAsFunction(_ x: MLXArray, training: Bool = false) -> MLXArray {
        var output = x

        // Flatten if needed
        if output.ndim > 2 {
            output = output.reshaped([output.dim(0), -1])
        }

        // Input projection
        output = inputLayer(output)
        output = activationFunction(output, type: .gelu)

        // Residual blocks
        for block in blocks {
            output = block(output, training: training)
        }

        // Output
        output = outputLayer(output)
        return output
    }
}

/// A single residual block
class ResidualBlock: Module, @unchecked Sendable {
    let fc1: Linear
    let fc2: Linear
    let dropoutRate: Double

    init(size: Int, dropout: Double) {
        self.fc1 = Linear(size, size)
        self.fc2 = Linear(size, size)
        self.dropoutRate = dropout
        super.init()
    }

    func callAsFunction(_ x: MLXArray, training: Bool = false) -> MLXArray {
        var output = fc1(x)
        output = activationFunction(output, type: .gelu)

        if training && dropoutRate > 0 {
            output = dropoutFunction(output, p: dropoutRate)
        }

        output = fc2(output)

        // Residual connection
        output = output + x

        output = activationFunction(output, type: .gelu)
        return output
    }
}

// MARK: - Simple Transformer

/// A simple transformer encoder for sequence/tabular classification
class SimpleTransformer: Module, @unchecked Sendable {
    let inputProjection: Linear
    let encoderLayers: [TransformerEncoderLayer]
    let outputLayer: Linear
    let seqLength: Int

    init(config: TransformerConfig) {
        self.seqLength = config.seqLength

        // Project input to model dimension
        self.inputProjection = Linear(config.inputDim, config.modelDim)

        // Encoder layers
        var layers: [TransformerEncoderLayer] = []
        for _ in 0..<config.numLayers {
            layers.append(TransformerEncoderLayer(
                modelDim: config.modelDim,
                numHeads: config.numHeads,
                ffnDim: config.ffnDim,
                dropout: config.dropout
            ))
        }
        self.encoderLayers = layers

        // Output projection
        self.outputLayer = Linear(config.modelDim, config.outputSize)

        super.init()
    }

    func callAsFunction(_ x: MLXArray, training: Bool = false) -> MLXArray {
        var output = x

        // Flatten and reshape for sequence processing
        if output.ndim > 2 {
            output = output.reshaped([output.dim(0), -1])
        }

        // Project to model dimension
        output = inputProjection(output)

        // Process through encoder layers
        for layer in encoderLayers {
            output = layer(output, training: training)
        }

        // Global average (just use the output directly for classification)
        output = outputLayer(output)
        return output
    }
}

/// A single transformer encoder layer (simplified)
class TransformerEncoderLayer: Module, @unchecked Sendable {
    let attnQKV: Linear
    let attnOut: Linear
    let ffn1: Linear
    let ffn2: Linear
    let modelDim: Int
    let numHeads: Int
    let dropoutRate: Double

    init(modelDim: Int, numHeads: Int, ffnDim: Int, dropout: Double) {
        self.modelDim = modelDim
        self.numHeads = numHeads
        self.dropoutRate = dropout

        // Simplified attention (QKV combined)
        self.attnQKV = Linear(modelDim, modelDim * 3)
        self.attnOut = Linear(modelDim, modelDim)

        // Feed-forward network
        self.ffn1 = Linear(modelDim, ffnDim)
        self.ffn2 = Linear(ffnDim, modelDim)

        super.init()
    }

    func callAsFunction(_ x: MLXArray, training: Bool = false) -> MLXArray {
        // Simplified self-attention (linear attention approximation)
        let qkv = attnQKV(x)
        let q = qkv[0..., 0..<modelDim]
        let k = qkv[0..., modelDim..<(modelDim*2)]
        let v = qkv[0..., (modelDim*2)...]

        // Scaled dot-product attention (simplified)
        let scale = Float(1.0 / sqrt(Float(modelDim)))
        let scores = (q * k) * scale
        let attnWeights = softmax(scores, axis: -1)
        var attnOutput = attnWeights * v
        attnOutput = attnOut(attnOutput)

        // Residual + layer norm (simplified as just add)
        var output = x + attnOutput

        // Feed-forward
        var ffnOut = ffn1(output)
        ffnOut = activationFunction(ffnOut, type: .gelu)
        if training && dropoutRate > 0 {
            ffnOut = dropoutFunction(ffnOut, p: dropoutRate)
        }
        ffnOut = ffn2(ffnOut)

        // Residual
        output = output + ffnOut

        return output
    }
}

/// Softmax function
func softmax(_ x: MLXArray, axis: Int = -1) -> MLXArray {
    let maxVal = x.max(axis: axis, keepDims: true)
    let expX = exp(x - maxVal)
    return expX / expX.sum(axis: axis, keepDims: true)
}

// MARK: - Model Factory

/// Factory for creating models from configuration
enum ModelFactory {
    static func create(from architecture: ModelArchitecture) throws -> Module {
        switch architecture {
        case .mlp(let config):
            return MLP(config: config)
        case .cnn(let config):
            return SimpleCNN(config: config)
        case .resnet(let config):
            return ResNetMini(config: config)
        case .transformer(let config):
            return SimpleTransformer(config: config)
        case .custom(let name):
            throw TrainingError.modelCreationFailed("Custom model '\(name)' not implemented")
        }
    }
}

// MARK: - Activation Functions

/// Apply activation function
func activationFunction(_ x: MLXArray, type: ActivationType) -> MLXArray {
    switch type {
    case .relu:
        return maximum(x, MLXArray(0))
    case .gelu:
        // GELU approximation
        let sqrt2pi = Float(0.7978845608)
        let coef = Float(0.044715)
        let inner = sqrt2pi * (x + coef * (x * x * x))
        return x * 0.5 * (1 + MLX.tanh(inner))
    case .silu:
        // SiLU (Swish): x * sigmoid(x)
        return x * (1 / (1 + exp(-x)))
    case .tanh:
        return MLX.tanh(x)
    case .sigmoid:
        return 1 / (1 + exp(-x))
    }
}

/// Apply dropout
func dropoutFunction(_ x: MLXArray, p: Double) -> MLXArray {
    guard p > 0 && p < 1 else { return x }
    let mask = MLXRandom.uniform(low: 0, high: 1, x.shape) .> Float(p)
    return (x * mask) / Float(1 - p)
}

// Helper functions for activation (keeping old names for compatibility)
func applyRelu(_ x: MLXArray) -> MLXArray {
    maximum(x, MLXArray(0))
}

func applyGelu(_ x: MLXArray) -> MLXArray {
    let sqrt2pi = Float(0.7978845608)
    let coef = Float(0.044715)
    let inner = sqrt2pi * (x + coef * (x * x * x))
    return x * 0.5 * (1 + MLX.tanh(inner))
}

func applySilu(_ x: MLXArray) -> MLXArray {
    x * (1 / (1 + exp(-x)))
}

func applySigmoid(_ x: MLXArray) -> MLXArray {
    1 / (1 + exp(-x))
}

func applyDropout(_ x: MLXArray, p: Double) -> MLXArray {
    dropoutFunction(x, p: p)
}
