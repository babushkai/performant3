import SwiftUI

struct NewRunSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedModelId: String?
    @State private var selectedDatasetId: String?
    @State private var selectedExperimentId: String?
    @State private var experiments: [ExperimentRecord] = []
    @State private var config = TrainingConfig.default
    @State private var showAdvanced = false
    @State private var isStarting = false

    var selectedModel: MLModel? {
        selectedModelId.flatMap { id in appState.models.first { $0.id == id } }
    }

    var selectedDataset: Dataset? {
        selectedDatasetId.flatMap { id in appState.datasets.first { $0.id == id } }
    }

    var selectedExperiment: ExperimentRecord? {
        selectedExperimentId.flatMap { id in experiments.first { $0.id == id } }
    }

    // Validation
    var validationErrors: [String] {
        var errors: [String] = []

        if name.isEmpty {
            errors.append("Run name is required")
        }

        if selectedModelId == nil {
            errors.append("Please select a model")
        }

        if config.epochs < 1 {
            errors.append("Epochs must be at least 1")
        } else if config.epochs > 10000 {
            errors.append("Epochs should not exceed 10,000")
        }

        if config.batchSize < 1 {
            errors.append("Batch size must be at least 1")
        } else if config.batchSize > 1024 {
            errors.append("Batch size should not exceed 1,024")
        }

        if config.learningRate <= 0 {
            errors.append("Learning rate must be positive")
        } else if config.learningRate > 1.0 {
            errors.append("Learning rate should not exceed 1.0")
        }

        if config.validationSplit < 0 || config.validationSplit > 0.5 {
            errors.append("Validation split should be between 0 and 0.5")
        }

        return errors
    }

    var canStart: Bool {
        validationErrors.isEmpty && !isStarting
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L.newTrainingRunTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Run Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.runName)
                            .font(.headline)
                        TextField(L.runName, text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Model Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.model)
                            .font(.headline)

                        if appState.models.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text(L.noModelsAvailableMsg)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        } else {
                            Picker("", selection: $selectedModelId) {
                                Text(L.selectAModel).tag(nil as String?)
                                ForEach(appState.models) { model in
                                    HStack {
                                        Image(systemName: model.framework.icon)
                                        Text(model.name)
                                    }
                                    .tag(model.id as String?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    // Dataset Selection (Optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.datasetOptional)
                            .font(.headline)

                        Picker("", selection: $selectedDatasetId) {
                            Text(L.noDataset).tag(nil as String?)
                            ForEach(appState.datasets) { dataset in
                                HStack {
                                    Image(systemName: dataset.type.icon)
                                    Text(dataset.name)
                                }
                                .tag(dataset.id as String?)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Experiment Selection (Optional) - for experiment tracking
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.experimentOptional)
                            .font(.headline)

                        if experiments.isEmpty {
                            HStack {
                                Image(systemName: "flask")
                                    .foregroundColor(.secondary)
                                Text(L.noExperimentsAvailable)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        } else {
                            Picker("", selection: $selectedExperimentId) {
                                Text(L.noExperiment).tag(nil as String?)
                                ForEach(experiments) { experiment in
                                    Text(experiment.name).tag(experiment.id as String?)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Text(L.linkExperimentDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Architecture Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.modelArchitecture)
                            .font(.headline)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(ArchitectureType.allCases, id: \.self) { arch in
                                ArchitectureCard(
                                    architecture: arch,
                                    isSelected: config.architecture == arch,
                                    onSelect: { config.architecture = arch }
                                )
                            }
                        }
                    }

                    // Basic Configuration
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.trainingParameters)
                            .font(.headline)

                        VStack(spacing: 16) {
                            ConfigSlider(
                                title: L.epochs,
                                value: Binding(
                                    get: { Double(config.epochs) },
                                    set: { config.epochs = Int($0) }
                                ),
                                range: 1...100,
                                format: "%.0f"
                            )

                            ConfigSlider(
                                title: L.batchSize,
                                value: Binding(
                                    get: { Double(config.batchSize) },
                                    set: { config.batchSize = Int($0) }
                                ),
                                range: 1...256,
                                format: "%.0f"
                            )

                            ConfigSlider(
                                title: L.learningRate,
                                value: $config.learningRate,
                                range: 0.00001...0.1,
                                format: "%.5f"
                            )
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    // Advanced Settings
                    DisclosureGroup("Advanced Settings", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 16) {
                            // Optimizer
                            HStack {
                                Text(L.optimizer)
                                Spacer()
                                Picker("", selection: $config.optimizer) {
                                    ForEach(Optimizer.allCases, id: \.self) { opt in
                                        Text(opt.rawValue).tag(opt)
                                    }
                                }
                                .frame(width: 120)
                            }

                            // Loss Function
                            HStack {
                                Text(L.lossFunction)
                                Spacer()
                                Picker("", selection: $config.lossFunction) {
                                    ForEach(LossFunction.allCases, id: \.self) { loss in
                                        Text(loss.rawValue).tag(loss)
                                    }
                                }
                                .frame(width: 180)
                            }

                            // Validation Split
                            ConfigSlider(
                                title: L.validationSplit,
                                value: $config.validationSplit,
                                range: 0.1...0.5,
                                format: "%.0f%%",
                                multiplier: 100
                            )

                            // Early Stopping
                            Toggle("Early Stopping", isOn: $config.earlyStopping)

                            if config.earlyStopping {
                                HStack {
                                    Text(L.patience)
                                    Spacer()
                                    Stepper("\(config.patience) epochs", value: $config.patience, in: 1...20)
                                }
                            }

                            Divider()

                            // Learning Rate Scheduler
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L.learningRateScheduler)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Picker("Scheduler", selection: $config.lrScheduler) {
                                    ForEach(LRScheduler.allCases, id: \.self) { scheduler in
                                        Label(scheduler.rawValue, systemImage: scheduler.icon).tag(scheduler)
                                    }
                                }
                                .pickerStyle(.menu)

                                Text(config.lrScheduler.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if config.lrScheduler == .step {
                                    HStack {
                                        Text(L.decayEvery)
                                        Spacer()
                                        Stepper("\(config.lrDecaySteps) epochs", value: $config.lrDecaySteps, in: 1...50)
                                    }
                                    HStack {
                                        Text(L.decayFactor)
                                        Spacer()
                                        Text(String(format: "%.2f", config.lrDecayFactor))
                                        Slider(value: $config.lrDecayFactor, in: 0.1...0.9)
                                            .frame(width: 100)
                                    }
                                }

                                if config.lrScheduler == .warmupCosine || config.lrScheduler == .oneCycle {
                                    HStack {
                                        Text(L.warmupEpochs)
                                        Spacer()
                                        Stepper("\(config.warmupEpochs)", value: $config.warmupEpochs, in: 1...20)
                                    }
                                }

                                if config.lrScheduler != .none {
                                    HStack {
                                        Text(L.minimumLR)
                                        Spacer()
                                        TextField("", value: $config.lrMinimum, format: .number)
                                            .frame(width: 80)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }
                            }

                            Divider()

                            // Data Augmentation
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L.dataAugmentation)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Toggle("Enable augmentation", isOn: $config.augmentation.enabled)

                                if config.augmentation.enabled {
                                    VStack(spacing: 8) {
                                        HStack {
                                            Toggle("Horizontal Flip", isOn: $config.augmentation.horizontalFlip)
                                            Spacer()
                                            Toggle("Vertical Flip", isOn: $config.augmentation.verticalFlip)
                                        }

                                        ConfigSlider(
                                            title: "Rotation (degrees)",
                                            value: $config.augmentation.rotation,
                                            range: 0...45,
                                            format: "%.0f°"
                                        )

                                        ConfigSlider(
                                            title: "Zoom",
                                            value: $config.augmentation.zoom,
                                            range: 0...0.5,
                                            format: "%.0f%%",
                                            multiplier: 100
                                        )

                                        ConfigSlider(
                                            title: "Brightness",
                                            value: $config.augmentation.brightness,
                                            range: 0...0.5,
                                            format: "%.0f%%",
                                            multiplier: 100
                                        )

                                        ConfigSlider(
                                            title: "Contrast",
                                            value: $config.augmentation.contrast,
                                            range: 0...0.5,
                                            format: "%.0f%%",
                                            multiplier: 100
                                        )
                                    }
                                    .padding(.leading, 8)
                                }
                            }

                            Divider()

                            // Checkpointing
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L.checkpointing)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Toggle("Save checkpoints during training", isOn: $config.saveCheckpoints)

                                if config.saveCheckpoints {
                                    HStack {
                                        Text(L.saveEvery)
                                        Spacer()
                                        Stepper("\(config.checkpointFrequency) epochs", value: $config.checkpointFrequency, in: 1...100)
                                    }

                                    HStack {
                                        Text(L.keepLast)
                                        Spacer()
                                        Stepper("\(config.keepCheckpoints) checkpoints", value: $config.keepCheckpoints, in: 1...10)
                                    }
                                }
                            }

                            Divider()

                            // Dataset Fallback
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L.datasetOptions)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Toggle("Allow synthetic data fallback", isOn: $config.allowSyntheticFallback)

                                if config.allowSyntheticFallback {
                                    Text(L.syntheticDataDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if selectedDatasetId == nil && !config.allowSyntheticFallback {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                        Text(L.noDatasetWarning)
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding()
            }

            // Validation errors
            if !validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(validationErrors, id: \.self) { error in
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // Footer
            HStack {
                Button(L.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: startTraining) {
                    if isStarting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text(L.startTraining)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 650)
        .onAppear {
            // Pre-select model if one was already selected
            if let modelId = appState.selectedModelId {
                selectedModelId = modelId
            }
            // Generate default name
            if name.isEmpty {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMdd-HHmm"
                name = "Run-\(dateFormatter.string(from: Date()))"
            }
            // Load available experiments
            loadExperiments()
        }
    }

    private func loadExperiments() {
        Task {
            let repo = ExperimentRepository()
            experiments = (try? await repo.findAll()) ?? []
        }
    }

    private func startTraining() {
        guard let modelId = selectedModelId else { return }

        isStarting = true
        Task {
            await appState.startTraining(
                modelId: modelId,
                name: name,
                config: config,
                datasetId: selectedDatasetId,
                experimentId: selectedExperimentId
            )
            dismiss()
        }
    }
}

// MARK: - Config Slider

struct ConfigSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var multiplier: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value * multiplier))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - Architecture Card

struct ArchitectureCard: View {
    let architecture: ArchitectureType
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: architecture.icon)
                        .font(.title2)
                        .foregroundColor(isSelected ? .white : .accentColor)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.15))
                        )

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }

                Text(architecture.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(architecture.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
