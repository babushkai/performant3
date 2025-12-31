import SwiftUI

// MARK: - Model Creation Wizard

struct ModelCreationWizard: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var currentStep = 0
    @State private var modelName = ""
    @State private var modelDescription = ""
    @State private var selectedFramework: MLFramework = .mlx
    @State private var selectedArchitecture: ArchitectureType = .mlp
    @State private var importFromFile = false
    @State private var selectedFilePath: String?
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var isCreating = false

    private let steps = ["Basic Info", "Framework", "Architecture", "Review"]

    var body: some View {
        VStack(spacing: 0) {
            // Header with progress
            WizardHeader(
                title: "Create New Model",
                steps: steps,
                currentStep: currentStep,
                onCancel: { dismiss() }
            )

            Divider()

            // Step content
            ScrollView {
                VStack(spacing: 24) {
                    switch currentStep {
                    case 0:
                        BasicInfoStep(
                            name: $modelName,
                            description: $modelDescription,
                            tags: $tags,
                            newTag: $newTag
                        )
                    case 1:
                        FrameworkStep(
                            selectedFramework: $selectedFramework,
                            importFromFile: $importFromFile,
                            selectedFilePath: $selectedFilePath
                        )
                    case 2:
                        ArchitectureStep(
                            selectedArchitecture: $selectedArchitecture,
                            selectedFramework: selectedFramework
                        )
                    case 3:
                        ReviewStep(
                            name: modelName,
                            description: modelDescription,
                            framework: selectedFramework,
                            architecture: selectedArchitecture,
                            tags: tags,
                            importFromFile: importFromFile,
                            filePath: selectedFilePath
                        )
                    default:
                        EmptyView()
                    }
                }
                .padding(24)
            }

            Divider()

            // Navigation buttons
            WizardNavigation(
                currentStep: $currentStep,
                totalSteps: steps.count,
                canProceed: canProceedToNextStep,
                isLastStep: currentStep == steps.count - 1,
                isProcessing: isCreating,
                onBack: { currentStep -= 1 },
                onNext: {
                    if currentStep == steps.count - 1 {
                        createModel()
                    } else {
                        currentStep += 1
                    }
                },
                nextButtonText: currentStep == steps.count - 1 ? "Create Model" : "Next"
            )
        }
        .frame(width: 600, height: 550)
    }

    private var canProceedToNextStep: Bool {
        switch currentStep {
        case 0: return !modelName.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return true
        case 2: return true
        case 3: return true
        default: return false
        }
    }

    private func createModel() {
        isCreating = true

        let model = MLModel(
            name: modelName.trimmingCharacters(in: .whitespaces),
            framework: selectedFramework,
            status: importFromFile ? .importing : .draft,
            filePath: selectedFilePath,
            metadata: [
                "description": modelDescription,
                "architecture": selectedArchitecture.rawValue,
                "tags": tags.joined(separator: ",")
            ]
        )

        Task {
            await appState.addModel(model)
            await MainActor.run {
                isCreating = false
                dismiss()
            }
        }
    }
}

// MARK: - Step Views

struct BasicInfoStep: View {
    @Binding var name: String
    @Binding var description: String
    @Binding var tags: [String]
    @Binding var newTag: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WizardStepHeader(
                icon: "doc.text",
                title: "Basic Information",
                subtitle: "Give your model a name and description"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Model Name")
                    .font(.headline)
                TextField("e.g., Image Classifier v1", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline)
                TextEditor(text: $description)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.headline)

                HStack {
                    TextField("Add tag...", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addTag()
                        }

                    Button("Add") {
                        addTag()
                    }
                    .disabled(newTag.isEmpty)
                }

                if !tags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(text: tag) {
                                tags.removeAll { $0 == tag }
                            }
                        }
                    }
                }
            }
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !tags.contains(trimmed) {
            tags.append(trimmed)
            newTag = ""
        }
    }
}

struct FrameworkStep: View {
    @Binding var selectedFramework: MLFramework
    @Binding var importFromFile: Bool
    @Binding var selectedFilePath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WizardStepHeader(
                icon: "cpu",
                title: "Select Framework",
                subtitle: "Choose the ML framework for your model"
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(MLFramework.allCases, id: \.self) { framework in
                    FrameworkCard(
                        framework: framework,
                        isSelected: selectedFramework == framework
                    ) {
                        selectedFramework = framework
                    }
                }
            }

            Divider()
                .padding(.vertical)

            Toggle("Import from existing file", isOn: $importFromFile)
                .toggleStyle(.switch)

            if importFromFile {
                HStack {
                    Text(selectedFilePath ?? "No file selected")
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Button("Browse...") {
                        selectFile()
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedFilePath = url.path
        }
    }
}

struct ArchitectureStep: View {
    @Binding var selectedArchitecture: ArchitectureType
    let selectedFramework: MLFramework

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WizardStepHeader(
                icon: "square.stack.3d.up",
                title: "Model Architecture",
                subtitle: "Select the neural network architecture"
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ArchitectureType.allCases, id: \.self) { arch in
                    ArchitectureCard(
                        architecture: arch,
                        isSelected: selectedArchitecture == arch
                    ) {
                        selectedArchitecture = arch
                    }
                }
            }

            if selectedFramework == .mlx {
                InfoBanner(
                    icon: "info.circle",
                    message: "MLX supports all architectures with Apple Silicon acceleration",
                    color: .blue
                )
            }
        }
    }
}

struct ReviewStep: View {
    let name: String
    let description: String
    let framework: MLFramework
    let architecture: ArchitectureType
    let tags: [String]
    let importFromFile: Bool
    let filePath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WizardStepHeader(
                icon: "checkmark.circle",
                title: "Review & Create",
                subtitle: "Confirm your model configuration"
            )

            VStack(spacing: 16) {
                ReviewRow(label: "Name", value: name)
                ReviewRow(label: "Description", value: description.isEmpty ? "No description" : description)
                ReviewRow(label: "Framework", value: framework.rawValue)
                ReviewRow(label: "Architecture", value: architecture.displayName)

                if !tags.isEmpty {
                    HStack(alignment: .top) {
                        Text("Tags")
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .leading)

                        FlowLayout(spacing: 4) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                if importFromFile {
                    ReviewRow(label: "Import From", value: filePath ?? "No file")
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            InfoBanner(
                icon: "lightbulb",
                message: "After creation, you can start training your model with a dataset",
                color: .green
            )
        }
    }
}

// MARK: - Shared Wizard Components

struct WizardHeader: View {
    let title: String
    let steps: [String]
    let currentStep: Int
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.borderless)
            }

            // Progress indicator
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    StepIndicator(
                        number: index + 1,
                        title: step,
                        isActive: index == currentStep,
                        isCompleted: index < currentStep
                    )

                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(index < currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
        }
        .padding()
    }
}

struct StepIndicator: View {
    let number: Int
    let title: String
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.accentColor : (isActive ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.2)))
                    .frame(width: 28, height: 28)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundColor(isActive ? .accentColor : .secondary)
                }
            }

            Text(title)
                .font(.caption2)
                .foregroundColor(isActive ? .primary : .secondary)
        }
        .frame(width: 70)
    }
}

struct WizardStepHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct WizardNavigation: View {
    @Binding var currentStep: Int
    let totalSteps: Int
    let canProceed: Bool
    let isLastStep: Bool
    let isProcessing: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let nextButtonText: String

    var body: some View {
        HStack {
            Button("Back") {
                onBack()
            }
            .disabled(currentStep == 0)

            Spacer()

            Button(nextButtonText) {
                onNext()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canProceed || isProcessing)
        }
        .padding()
    }
}

struct FrameworkCard: View {
    let framework: MLFramework
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: framework.icon)
                    .font(.title)
                    .foregroundColor(isSelected ? .white : .accentColor)

                Text(framework.rawValue)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : .primary)

                Text(frameworkDescription)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var frameworkDescription: String {
        switch framework {
        case .mlx: return "Apple Silicon native"
        case .coreML: return "iOS/macOS optimized"
        case .pytorch: return "Research & production"
        case .tensorflow: return "Cross-platform ML"
        }
    }
}

struct ArchitectureCard: View {
    let architecture: ArchitectureType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(architecture.rawValue)
                        .font(.headline)
                        .foregroundColor(isSelected ? .white : .primary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                    }
                }

                Text(architecture.displayName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding()
            .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .fontWeight(.medium)

            Spacer()
        }
    }
}

struct InfoBanner: View {
    let icon: String
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct TagChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.2))
        .cornerRadius(12)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        let maxX = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxX && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}
