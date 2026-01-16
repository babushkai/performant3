import Foundation

/// Service for exporting trained models to various formats
actor ModelExportService {
    static let shared = ModelExportService()

    private let pythonEnv = PythonEnvironmentManager.shared
    private let fileManager = FileManager.default

    enum ExportFormat: String, CaseIterable, Identifiable {
        case coreml = "CoreML"
        case onnx = "ONNX"
        case pytorch = "PyTorch"
        case torchscript = "TorchScript"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .coreml: return "mlpackage"
            case .onnx: return "onnx"
            case .pytorch: return "pt"
            case .torchscript: return "torchscript"
            }
        }

        var description: String {
            switch self {
            case .coreml: return "Apple Core ML format for iOS/macOS deployment"
            case .onnx: return "Open Neural Network Exchange format"
            case .pytorch: return "PyTorch checkpoint format"
            case .torchscript: return "PyTorch TorchScript for production"
            }
        }
    }

    struct ExportResult {
        let format: ExportFormat
        let outputPath: String
        let fileSize: Int64
        let exportTime: TimeInterval
        let metadata: [String: String]
    }

    enum ExportError: Error, LocalizedError {
        case modelNotFound(String)
        case unsupportedFormat(ExportFormat)
        case exportFailed(String)
        case pythonEnvironmentNotReady
        case invalidModelPath

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let path):
                return "Model not found at path: \(path)"
            case .unsupportedFormat(let format):
                return "Export to \(format.rawValue) is not supported for this model type"
            case .exportFailed(let reason):
                return "Export failed: \(reason)"
            case .pythonEnvironmentNotReady:
                return "Python environment is not ready"
            case .invalidModelPath:
                return "Invalid model path"
            }
        }
    }

    // MARK: - Export Methods

    /// Export a YOLOv8 model to various formats
    func exportYOLOv8(
        modelPath: String,
        to format: ExportFormat,
        outputDir: String? = nil,
        progressHandler: ((String) -> Void)? = nil
    ) async throws -> ExportResult {
        let startTime = Date()

        // Verify model exists
        guard fileManager.fileExists(atPath: modelPath) else {
            throw ExportError.modelNotFound(modelPath)
        }

        // Ensure Python environment is ready
        progressHandler?("Checking Python environment...")
        try await pythonEnv.ensureReady()

        // Determine output path
        let modelURL = URL(fileURLWithPath: modelPath)
        let modelName = modelURL.deletingPathExtension().lastPathComponent
        let outputDirectory = outputDir ?? modelURL.deletingLastPathComponent().path
        let outputPath = "\(outputDirectory)/\(modelName).\(format.fileExtension)"

        progressHandler?("Exporting to \(format.rawValue)...")

        // Build export command
        let exportFormat: String
        switch format {
        case .coreml:
            exportFormat = "coreml"
        case .onnx:
            exportFormat = "onnx"
        case .pytorch:
            // PyTorch is the native format, just copy
            if modelPath != outputPath {
                try fileManager.copyItem(atPath: modelPath, toPath: outputPath)
            }
            let attrs = try fileManager.attributesOfItem(atPath: outputPath)
            let fileSize = attrs[.size] as? Int64 ?? 0
            return ExportResult(
                format: format,
                outputPath: outputPath,
                fileSize: fileSize,
                exportTime: Date().timeIntervalSince(startTime),
                metadata: ["source": modelPath]
            )
        case .torchscript:
            exportFormat = "torchscript"
        }

        // Run YOLO export command
        let pythonPath = await pythonEnv.pythonPath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            "-c",
            """
            from ultralytics import YOLO
            model = YOLO('\(modelPath)')
            model.export(format='\(exportFormat)')
            """
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ExportError.exportFailed(errorMessage)
        }

        // Find the exported file (YOLO creates it in the same directory as the input)
        let expectedOutputPath = modelURL.deletingPathExtension()
            .appendingPathExtension(format.fileExtension).path

        let finalPath: String
        if fileManager.fileExists(atPath: expectedOutputPath) {
            if expectedOutputPath != outputPath {
                try? fileManager.removeItem(atPath: outputPath)
                try fileManager.moveItem(atPath: expectedOutputPath, toPath: outputPath)
            }
            finalPath = outputPath
        } else if fileManager.fileExists(atPath: outputPath) {
            finalPath = outputPath
        } else {
            throw ExportError.exportFailed("Exported file not found")
        }

        let attrs = try fileManager.attributesOfItem(atPath: finalPath)
        let fileSize = attrs[.size] as? Int64 ?? 0

        progressHandler?("Export complete!")

        return ExportResult(
            format: format,
            outputPath: finalPath,
            fileSize: fileSize,
            exportTime: Date().timeIntervalSince(startTime),
            metadata: [
                "source": modelPath,
                "format": format.rawValue
            ]
        )
    }

    /// Export MLX model to CoreML
    func exportMLXToCoreML(
        modelPath: String,
        inputShape: [Int],
        outputPath: String,
        progressHandler: ((String) -> Void)? = nil
    ) async throws -> ExportResult {
        let startTime = Date()

        progressHandler?("Converting MLX model to CoreML...")

        // MLX to CoreML conversion requires specific handling
        // For now, we'll use coremltools if available

        try await pythonEnv.ensureReady()

        let pythonPath = await pythonEnv.pythonPath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            "-c",
            """
            import coremltools as ct
            import torch
            import json

            # Load the model state dict
            state_dict = torch.load('\(modelPath)', map_location='cpu')

            # This is a placeholder - actual conversion depends on model architecture
            print('CoreML conversion requires model-specific handling')
            """
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        // Check if conversion succeeded
        guard fileManager.fileExists(atPath: outputPath) else {
            throw ExportError.exportFailed("CoreML conversion not yet implemented for MLX models")
        }

        let attrs = try fileManager.attributesOfItem(atPath: outputPath)
        let fileSize = attrs[.size] as? Int64 ?? 0

        return ExportResult(
            format: .coreml,
            outputPath: outputPath,
            fileSize: fileSize,
            exportTime: Date().timeIntervalSince(startTime),
            metadata: ["source": modelPath, "inputShape": inputShape.map(String.init).joined(separator: ",")]
        )
    }

    /// Get supported export formats for a model type
    func supportedFormats(for architecture: ArchitectureType) -> [ExportFormat] {
        switch architecture {
        case .yolov8:
            return [.coreml, .onnx, .pytorch, .torchscript]
        case .mlp, .cnn, .resnet, .transformer:
            return [.pytorch, .onnx]
        }
    }

    /// Validate an exported model
    func validateExport(at path: String, format: ExportFormat) -> Bool {
        guard fileManager.fileExists(atPath: path) else {
            return false
        }

        // Basic validation - check file size
        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64,
              size > 0 else {
            return false
        }

        // Format-specific validation could be added here
        return true
    }
}

// MARK: - Export Script

/// Python script for model export
let modelExportScript = """
#!/usr/bin/env python3
\"\"\"
Model Export Script for Performant3
Exports models to various formats.
\"\"\"

import argparse
import json
import sys
from pathlib import Path

def export_yolo(model_path: str, format: str, output_dir: str = None):
    \"\"\"Export YOLOv8 model to specified format.\"\"\"
    from ultralytics import YOLO

    model = YOLO(model_path)
    result = model.export(format=format)

    print(json.dumps({
        "type": "completed",
        "outputPath": str(result),
        "format": format
    }))

def export_pytorch_to_onnx(model_path: str, output_path: str, input_shape: list):
    \"\"\"Export PyTorch model to ONNX.\"\"\"
    import torch
    import torch.onnx

    model = torch.load(model_path, map_location='cpu')
    model.eval()

    dummy_input = torch.randn(*input_shape)

    torch.onnx.export(
        model,
        dummy_input,
        output_path,
        export_params=True,
        opset_version=11,
        do_constant_folding=True,
        input_names=['input'],
        output_names=['output'],
        dynamic_axes={'input': {0: 'batch_size'}, 'output': {0: 'batch_size'}}
    )

    print(json.dumps({
        "type": "completed",
        "outputPath": output_path,
        "format": "onnx"
    }))

def main():
    parser = argparse.ArgumentParser(description="Export ML models")
    parser.add_argument("--model", required=True, help="Path to model")
    parser.add_argument("--format", required=True, choices=["coreml", "onnx", "torchscript"])
    parser.add_argument("--output", help="Output path")
    parser.add_argument("--type", default="yolo", choices=["yolo", "pytorch"])
    parser.add_argument("--input-shape", help="Input shape as comma-separated values")

    args = parser.parse_args()

    if args.type == "yolo":
        export_yolo(args.model, args.format, args.output)
    elif args.type == "pytorch":
        if not args.input_shape:
            print(json.dumps({"type": "error", "message": "Input shape required for PyTorch export"}))
            sys.exit(1)
        shape = [int(x) for x in args.input_shape.split(",")]
        export_pytorch_to_onnx(args.model, args.output, shape)

if __name__ == "__main__":
    main()
"""
