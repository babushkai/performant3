# MacML

[![Build](https://github.com/babushkai/macml/actions/workflows/build.yml/badge.svg)](https://github.com/babushkai/macml/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/babushkai/macml)](https://github.com/babushkai/macml/releases/latest)
[![License](https://img.shields.io/github/license/babushkai/macml)](LICENSE)

A native macOS MLOps platform built for Apple Silicon, featuring SwiftUI interface and MLX integration for local machine learning workflows.

## Architecture Overview

MacML follows a layered architecture pattern optimized for SwiftUI and Apple Silicon:

```
┌─────────────────────────────────────────────────────────────┐
│                      SwiftUI Views                          │
│  Dashboard │ Models │ Training │ Inference │ Settings       │
├─────────────────────────────────────────────────────────────┤
│                       AppState                              │
│              (Central Observable State)                     │
├─────────────────────────────────────────────────────────────┤
│                    Service Layer                            │
│  TrainingService │ MLXInferenceService │ DistillationService│
├─────────────────────────────────────────────────────────────┤
│                   MLX Training Core                         │
│         MLP │ CNN │ ResNet │ Transformer                    │
├─────────────────────────────────────────────────────────────┤
│                  Persistence Layer                          │
│         GRDB (SQLite) │ JSON Storage │ Checkpoints          │
└─────────────────────────────────────────────────────────────┘
```

### Core Components

#### AppState (`main.swift`)

The central state management class using SwiftUI's `@Observable` pattern:

- **Published Data**: Models, training runs, datasets, inference history
- **UI State**: Navigation, selection, sheet presentation
- **Service Coordination**: Orchestrates training, inference, and storage operations
- **Callbacks**: Real-time updates from training and distillation services

```swift
@MainActor
class AppState: ObservableObject {
    @Published var models: [MLModel] = []
    @Published var runs: [TrainingRun] = []
    @Published var datasets: [Dataset] = []

    let trainingService = TrainingService.shared
    let mlService = MLService.shared
    private let storage = StorageManager.shared
}
```

#### Service Layer

| Service | Responsibility |
|---------|----------------|
| `TrainingService` | Orchestrates training runs, manages training lifecycle (start/pause/resume/cancel) |
| `MLXTrainingService` | Native MLX training on Apple Silicon with GPU acceleration |
| `MLXInferenceService` | Real-time inference using trained MLX models |
| `DistillationService` | Knowledge distillation from cloud LLMs to local student models |
| `CheckpointManager` | Saves and loads model checkpoints with metadata |
| `StorageManager` | Manages file storage for models, datasets, and artifacts |
| `PythonEnvironmentManager` | Manages Python virtual environment for YOLOv8 training |

#### MLX Neural Network Architectures

Native Swift implementations using Apple's MLX framework:

- **MLP (Multi-Layer Perceptron)**: Dense layers for tabular/image classification
- **CNN (Convolutional Neural Network)**: Spatial feature extraction for images
- **ResNet**: Residual connections for deep networks
- **Transformer**: Attention-based architecture for sequence tasks

Each architecture implements the `MLXModelProtocol`:

```swift
protocol MLXModelProtocol {
    func forward(_ x: MLXArray) -> MLXArray
    func parameters() -> [String: MLXArray]
    func update(parameters: [String: MLXArray])
}
```

#### Database Layer (`Database/`)

GRDB-based SQLite persistence with migration support:

- **Tables**: projects, experiments, models, training_runs, metrics, datasets, artifacts
- **WAL Mode**: Write-ahead logging for concurrent access
- **Migrations**: Versioned schema evolution (v1_initial, v2_architecture_type, v3_extended_metrics)

```swift
actor DatabaseManager {
    private var dbPool: DatabasePool?

    func read<T>(_ block: (Database) throws -> T) async throws -> T
    func write<T>(_ block: (Database) throws -> T) async throws -> T
}
```

### Data Flow

#### Training Flow

```
User Action → AppState.startTraining()
    → TrainingService.startTraining()
        → MLXTrainingService.train()
            → Forward pass (MLX GPU)
            → Backward pass (automatic differentiation)
            → Optimizer step
            → Progress callback
        → CheckpointManager.save()
    → AppState.onRunCompleted()
        → Update model accuracy
        → Register trained model for inference
```

#### Inference Flow

```
User drops image → InferenceView
    → AppState.runInference()
        → MLXInferenceService.runInference()
            → Load checkpoint
            → Preprocess image
            → Forward pass
            → Return predictions
        → Save to InferenceResultRepository
    → Display predictions
```

### Data Models (`Models/DataModels.swift`)

| Model | Purpose |
|-------|---------|
| `MLModel` | Model metadata (name, framework, status, accuracy, file path) |
| `TrainingRun` | Training session state (epochs, metrics, logs, hyperparameters) |
| `Dataset` | Dataset metadata (type, sample count, classes) |
| `InferenceResult` | Inference output (predictions, timing) |
| `DistillationRun` | Knowledge distillation session |
| `TrainingConfig` | Hyperparameters (epochs, batch size, learning rate, scheduler) |

### View Architecture

SwiftUI views organized by feature:

```
Views/
├── ContentView.swift        # Main navigation container
├── DashboardView.swift      # Overview with metrics and quick actions
├── ModelsView.swift         # Model management and creation
├── RunsView.swift           # Training run monitoring
├── DatasetsView.swift       # Dataset import and management
├── InferenceView.swift      # Real-time inference UI
├── ExperimentsView.swift    # Experiment tracking
├── MetricsView.swift        # Training metrics visualization
└── SettingsView.swift       # App configuration
```

### Localization

Multi-language support (English, Japanese) using:

- `Localization.swift`: Centralized localization keys
- `en.lproj/Localizable.strings`: English translations
- `ja.lproj/Localizable.strings`: Japanese translations
- `LanguageManager`: Runtime language switching

### Key Design Decisions

1. **Local-First**: All ML operations run on-device using MLX
2. **Actor Isolation**: Database and services use Swift actors for thread safety
3. **Singleton Services**: Shared instances for consistent state management
4. **Callback Pattern**: Services notify AppState via callbacks for UI updates
5. **Dual Storage**: SQLite (GRDB) for structured data, JSON for compatibility
6. **Content-Addressed Storage**: SHA256 hashes for artifact deduplication

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3/M4)
- Xcode 15.0+ (for building from source)

## Installation

Download the latest `.dmg` from [Releases](../../releases), or build from source:

```bash
git clone https://github.com/babushkai/macml.git
cd macml && ./build-app.sh
```

## Dependencies

| Package | Purpose |
|---------|---------|
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | Apple Silicon ML framework |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database |
| [swift-crypto](https://github.com/apple/swift-crypto) | Cryptographic operations |

## License

MIT License - see [LICENSE](LICENSE) for details.
