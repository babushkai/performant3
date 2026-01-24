import Foundation

// MARK: - Python Executor

/// Executes Python ML training scripts via subprocess
actor PythonExecutor {
    private var currentProcess: Process?
    private var _isRunning = false

    var isRunning: Bool { _isRunning }

    // MARK: - Training Events

    enum TrainingEvent: Codable, Sendable {
        case metric(epoch: Int, step: Int?, loss: Double, accuracy: Double?)
        case log(level: String, message: String)
        case progress(epoch: Int, totalEpochs: Int, step: Int?, totalSteps: Int?)
        case completed(finalLoss: Double, finalAccuracy: Double?, duration: Double)
        case error(message: String)
        case checkpoint(path: String, epoch: Int)

        enum CodingKeys: String, CodingKey {
            case type, epoch, step, loss, accuracy, level, message
            case totalEpochs, totalSteps, finalLoss, finalAccuracy, duration, path
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "metric":
                let epoch = try container.decode(Int.self, forKey: .epoch)
                let step = try container.decodeIfPresent(Int.self, forKey: .step)
                let loss = try container.decode(Double.self, forKey: .loss)
                let accuracy = try container.decodeIfPresent(Double.self, forKey: .accuracy)
                self = .metric(epoch: epoch, step: step, loss: loss, accuracy: accuracy)
            case "log":
                let level = try container.decode(String.self, forKey: .level)
                let message = try container.decode(String.self, forKey: .message)
                self = .log(level: level, message: message)
            case "progress":
                let epoch = try container.decode(Int.self, forKey: .epoch)
                let totalEpochs = try container.decode(Int.self, forKey: .totalEpochs)
                let step = try container.decodeIfPresent(Int.self, forKey: .step)
                let totalSteps = try container.decodeIfPresent(Int.self, forKey: .totalSteps)
                self = .progress(epoch: epoch, totalEpochs: totalEpochs, step: step, totalSteps: totalSteps)
            case "completed":
                let finalLoss = try container.decode(Double.self, forKey: .finalLoss)
                let finalAccuracy = try container.decodeIfPresent(Double.self, forKey: .finalAccuracy)
                let duration = try container.decode(Double.self, forKey: .duration)
                self = .completed(finalLoss: finalLoss, finalAccuracy: finalAccuracy, duration: duration)
            case "error":
                let message = try container.decode(String.self, forKey: .message)
                self = .error(message: message)
            case "checkpoint":
                let path = try container.decode(String.self, forKey: .path)
                let epoch = try container.decode(Int.self, forKey: .epoch)
                self = .checkpoint(path: path, epoch: epoch)
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown event type")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .metric(let epoch, let step, let loss, let accuracy):
                try container.encode("metric", forKey: .type)
                try container.encode(epoch, forKey: .epoch)
                try container.encodeIfPresent(step, forKey: .step)
                try container.encode(loss, forKey: .loss)
                try container.encodeIfPresent(accuracy, forKey: .accuracy)
            case .log(let level, let message):
                try container.encode("log", forKey: .type)
                try container.encode(level, forKey: .level)
                try container.encode(message, forKey: .message)
            case .progress(let epoch, let totalEpochs, let step, let totalSteps):
                try container.encode("progress", forKey: .type)
                try container.encode(epoch, forKey: .epoch)
                try container.encode(totalEpochs, forKey: .totalEpochs)
                try container.encodeIfPresent(step, forKey: .step)
                try container.encodeIfPresent(totalSteps, forKey: .totalSteps)
            case .completed(let finalLoss, let finalAccuracy, let duration):
                try container.encode("completed", forKey: .type)
                try container.encode(finalLoss, forKey: .finalLoss)
                try container.encodeIfPresent(finalAccuracy, forKey: .finalAccuracy)
                try container.encode(duration, forKey: .duration)
            case .error(let message):
                try container.encode("error", forKey: .type)
                try container.encode(message, forKey: .message)
            case .checkpoint(let path, let epoch):
                try container.encode("checkpoint", forKey: .type)
                try container.encode(path, forKey: .path)
                try container.encode(epoch, forKey: .epoch)
            }
        }
    }

    // MARK: - Run Training Script

    /// Run a Python training script and stream events
    func runTraining(
        scriptPath: String,
        config: TrainingConfig,
        datasetPath: String?,
        pythonPath: String = "/usr/bin/python3",
        eventHandler: @escaping (TrainingEvent) -> Void
    ) async throws {
        guard !_isRunning else {
            throw PythonExecutorError.alreadyRunning
        }

        _isRunning = true
        defer { _isRunning = false }

        // Encode config to JSON
        let configJSON = try JSONEncoder().encode(config)
        let configString = String(data: configJSON, encoding: .utf8) ?? "{}"

        // Build arguments
        var arguments = [scriptPath, "--config", configString]
        if let datasetPath = datasetPath {
            arguments.append(contentsOf: ["--dataset", datasetPath])
        }

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = arguments

        // Set up pipes for stdout/stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set environment variables
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"  // Disable buffering
        process.environment = environment

        currentProcess = process

        // Start process
        try process.run()

        // Read stdout in background
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let decoder = JSONDecoder()

        // Process output line by line
        await withTaskGroup(of: Void.self) { group in
            // Stdout reader
            group.addTask {
                var buffer = Data()

                while true {
                    let data = stdoutHandle.availableData
                    if data.isEmpty {
                        break
                    }

                    buffer.append(data)

                    // Process complete lines
                    while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = buffer[buffer.startIndex..<newlineIndex]
                        buffer.removeSubrange(buffer.startIndex...newlineIndex)

                        if let event = try? decoder.decode(TrainingEvent.self, from: lineData) {
                            eventHandler(event)
                        } else if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                            // Non-JSON output treated as log
                            eventHandler(.log(level: "info", message: line))
                        }
                    }
                }
            }

            // Stderr reader
            group.addTask {
                let stderrHandle = stderrPipe.fileHandleForReading
                while true {
                    let data = stderrHandle.availableData
                    if data.isEmpty {
                        break
                    }

                    if let message = String(data: data, encoding: .utf8) {
                        eventHandler(.log(level: "error", message: message))
                    }
                }
            }
        }

        // Wait for process to complete
        process.waitUntilExit()

        // Close pipe file handles to release resources immediately
        // Without this, pipes remain open until garbage collected
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        let exitCode = process.terminationStatus
        if exitCode != 0 {
            throw PythonExecutorError.scriptFailed(exitCode: Int(exitCode))
        }

        currentProcess = nil
    }

    // MARK: - Run Script (Generic)

    /// Run a Python script with arbitrary arguments and stream events
    func runScript(
        python: String = "python3",
        arguments: [String],
        eventHandler: @escaping (TrainingEvent) -> Void
    ) async throws {
        guard !_isRunning else {
            throw PythonExecutorError.alreadyRunning
        }

        _isRunning = true
        defer { _isRunning = false }

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [python] + arguments

        // Set up pipes for stdout/stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set environment variables
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"  // Disable buffering
        process.environment = environment

        currentProcess = process

        // Start process
        try process.run()

        // Read stdout in background
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let decoder = JSONDecoder()

        // Process output line by line
        await withTaskGroup(of: Void.self) { group in
            // Stdout reader - parse JSON events
            group.addTask {
                var buffer = Data()

                while true {
                    let availableData = stdoutHandle.availableData
                    if availableData.isEmpty { break }

                    buffer.append(availableData)

                    // Process complete lines
                    while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                        buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                        // Try to parse as JSON event
                        if let event = try? decoder.decode(TrainingEvent.self, from: lineData) {
                            eventHandler(event)
                        } else if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                            // Emit as log if not valid JSON
                            eventHandler(.log(level: "info", message: line))
                        }
                    }
                }
            }

            // Stderr reader - log as warnings
            group.addTask {
                let stderrHandle = stderrPipe.fileHandleForReading
                while true {
                    let data = stderrHandle.availableData
                    if data.isEmpty { break }
                    if let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !line.isEmpty {
                        eventHandler(.log(level: "warning", message: line))
                    }
                }
            }
        }

        // Wait for process to complete
        process.waitUntilExit()

        // Close pipe file handles to release resources immediately
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        let exitCode = process.terminationStatus
        if exitCode != 0 {
            throw PythonExecutorError.scriptFailed(exitCode: Int(exitCode))
        }

        currentProcess = nil
    }

    // MARK: - Run Inference

    /// Run a Python inference script
    func runInference(
        scriptPath: String,
        modelPath: String,
        inputPath: String,
        pythonPath: String = "/usr/bin/python3"
    ) async throws -> [Prediction] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, "--model", modelPath, "--input", inputPath]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe

        try process.run()
        process.waitUntilExit()

        let fileHandle = stdoutPipe.fileHandleForReading
        let data = fileHandle.readDataToEndOfFile()

        // Close pipe file handle to release resources immediately
        try? fileHandle.close()

        guard process.terminationStatus == 0 else {
            throw PythonExecutorError.scriptFailed(exitCode: Int(process.terminationStatus))
        }

        // Parse predictions from JSON output
        let result = try JSONDecoder().decode(InferenceOutput.self, from: data)
        return result.predictions.map { Prediction(label: $0.label, confidence: $0.confidence) }
    }

    // MARK: - Cancel

    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
        _isRunning = false
    }

    // MARK: - Check Python

    /// Check if Python is available
    func checkPythonAvailable(path: String = "/usr/bin/python3") -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            // Close pipe file handle to release resources
            try? pipe.fileHandleForReading.close()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Get installed Python packages
    func getInstalledPackages(pythonPath: String = "/usr/bin/python3") async throws -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "pip", "list", "--format=json"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let fileHandle = pipe.fileHandleForReading
        let data = fileHandle.readDataToEndOfFile()
        // Close pipe file handle to release resources
        try? fileHandle.close()

        let packages = try JSONDecoder().decode([PipPackage].self, from: data)

        var result: [String: String] = [:]
        for package in packages {
            result[package.name.lowercased()] = package.version
        }
        return result
    }
}

// MARK: - Helper Types

private struct InferenceOutput: Codable {
    let predictions: [PredictionOutput]
}

private struct PredictionOutput: Codable {
    let label: String
    let confidence: Double
}

private struct PipPackage: Codable {
    let name: String
    let version: String
}

// MARK: - Errors

enum PythonExecutorError: Error, LocalizedError {
    case pythonNotFound
    case alreadyRunning
    case scriptNotFound(String)
    case scriptFailed(exitCode: Int)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python interpreter not found"
        case .alreadyRunning:
            return "A Python script is already running"
        case .scriptNotFound(let path):
            return "Script not found: \(path)"
        case .scriptFailed(let exitCode):
            return "Script failed with exit code \(exitCode)"
        case .invalidOutput:
            return "Invalid output from Python script"
        }
    }
}

// MARK: - Python Training Script Template

/// Template for a Python training script that communicates with Performant3
let pythonTrainingScriptTemplate = """
#!/usr/bin/env python3
\"\"\"
Performant3 Training Script Template

This script demonstrates how to write a training script that communicates
with the Performant3 MLOps platform via JSON events on stdout.

Usage:
    python train.py --config '{"epochs": 10, "batchSize": 32, ...}' --dataset /path/to/data
\"\"\"

import json
import sys
import argparse
import time

def log_event(event_type: str, **kwargs):
    \"\"\"Log an event to stdout for Performant3 to consume.\"\"\"
    event = {"type": event_type, **kwargs}
    print(json.dumps(event), flush=True)

def log_metric(epoch: int, loss: float, accuracy: float = None, step: int = None):
    \"\"\"Log training metrics.\"\"\"
    event = {"type": "metric", "epoch": epoch, "loss": loss}
    if accuracy is not None:
        event["accuracy"] = accuracy
    if step is not None:
        event["step"] = step
    print(json.dumps(event), flush=True)

def log_progress(epoch: int, total_epochs: int, step: int = None, total_steps: int = None):
    \"\"\"Log training progress.\"\"\"
    event = {"type": "progress", "epoch": epoch, "totalEpochs": total_epochs}
    if step is not None:
        event["step"] = step
    if total_steps is not None:
        event["totalSteps"] = total_steps
    print(json.dumps(event), flush=True)

def log_message(level: str, message: str):
    \"\"\"Log a message.\"\"\"
    log_event("log", level=level, message=message)

def log_completed(final_loss: float, final_accuracy: float = None, duration: float = 0):
    \"\"\"Log training completion.\"\"\"
    event = {"type": "completed", "finalLoss": final_loss, "duration": duration}
    if final_accuracy is not None:
        event["finalAccuracy"] = final_accuracy
    print(json.dumps(event), flush=True)

def log_checkpoint(path: str, epoch: int):
    \"\"\"Log checkpoint saved.\"\"\"
    log_event("checkpoint", path=path, epoch=epoch)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=str, required=True, help="Training config JSON")
    parser.add_argument("--dataset", type=str, help="Path to dataset")
    args = parser.parse_args()

    config = json.loads(args.config)
    epochs = config.get("epochs", 10)
    batch_size = config.get("batchSize", 32)
    learning_rate = config.get("learningRate", 0.001)

    log_message("info", f"Starting training with {epochs} epochs")
    log_message("info", f"Batch size: {batch_size}, Learning rate: {learning_rate}")

    start_time = time.time()

    # Your training loop here
    for epoch in range(1, epochs + 1):
        # Simulate training
        loss = 2.5 * (0.7 ** epoch)  # Decreasing loss
        accuracy = min(0.99, 0.1 + 0.09 * epoch)  # Increasing accuracy

        log_progress(epoch, epochs)

        # Simulate batch steps
        for step in range(10):
            time.sleep(0.1)  # Simulate computation

        log_metric(epoch, loss, accuracy)
        log_message("info", f"Epoch {epoch}/{epochs} - loss: {loss:.4f}, acc: {accuracy:.2%}")

    duration = time.time() - start_time
    log_completed(loss, accuracy, duration)

if __name__ == "__main__":
    main()
"""
