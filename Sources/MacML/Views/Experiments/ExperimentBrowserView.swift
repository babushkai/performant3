import SwiftUI

// MARK: - Experiments Tab Container

struct ExperimentBrowserView: View {
    @State private var selectedMode: ExperimentsMode = .browser

    enum ExperimentsMode: String, CaseIterable {
        case browser = "Experiments"
        case tuning = "Hyperparameter Tuning"

        var icon: String {
            switch self {
            case .browser: return "flask"
            case .tuning: return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode selector
            HStack {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(ExperimentsMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                Spacer()
            }
            .padding()
            .background(AppTheme.background)

            Divider()

            // Content
            switch selectedMode {
            case .browser:
                ExperimentBrowserContent()
            case .tuning:
                HyperparameterTuningView()
            }
        }
    }
}

// MARK: - Experiment Browser Content

struct ExperimentBrowserContent: View {
    @EnvironmentObject var appState: AppState
    @State private var projects: [ProjectRecord] = []
    @State private var selectedProjectId: String?
    @State private var experiments: [ExperimentRecord] = []
    @State private var selectedExperimentId: String?
    @State private var experimentRuns: [TrainingRun] = []
    @State private var showNewProjectSheet = false
    @State private var showNewExperimentSheet = false
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            // Projects list
            List(selection: $selectedProjectId) {
                Section("Projects") {
                    ForEach(filteredProjects) { project in
                        ProjectRow(project: project)
                            .tag(project.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
            .searchable(text: $searchText, prompt: "Search projects")
            .toolbar {
                ToolbarItem {
                    Button(action: { showNewProjectSheet = true }) {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
        } content: {
            // Experiments for selected project
            if selectedProjectId != nil {
                List(selection: $selectedExperimentId) {
                    Section("Experiments") {
                        ForEach(experiments) { experiment in
                            ExperimentRow(experiment: experiment)
                                .tag(experiment.id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 220)
                .toolbar {
                    ToolbarItem {
                        Button(action: { showNewExperimentSheet = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            } else {
                ContentUnavailableView("Select a Project", systemImage: "folder", description: Text("Choose a project to view its experiments"))
            }
        } detail: {
            // Experiment detail / runs
            if let experimentId = selectedExperimentId {
                ExperimentDetailView(
                    experimentId: experimentId,
                    runs: experimentRuns
                )
            } else {
                ContentUnavailableView("Select an Experiment", systemImage: "flask", description: Text("Choose an experiment to view runs"))
            }
        }
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet(onCreated: loadProjects)
        }
        .sheet(isPresented: $showNewExperimentSheet) {
            if let projectId = selectedProjectId {
                NewExperimentSheet(projectId: projectId, onCreated: { loadExperiments(for: projectId) })
            }
        }
        .onChange(of: selectedProjectId) { _, newId in
            if let id = newId {
                loadExperiments(for: id)
            }
        }
        .onChange(of: selectedExperimentId) { _, newId in
            if let id = newId {
                loadRuns(for: id)
            }
        }
        .task {
            await loadProjects()
        }
    }

    var filteredProjects: [ProjectRecord] {
        if searchText.isEmpty {
            return projects
        }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    func loadProjects() {
        Task {
            let repo = ProjectRepository()
            projects = (try? await repo.findAll()) ?? []
        }
    }

    func loadExperiments(for projectId: String) {
        Task {
            let repo = ExperimentRepository()
            experiments = (try? await repo.findByProject(projectId)) ?? []
            selectedExperimentId = nil
        }
    }

    func loadRuns(for experimentId: String) {
        Task {
            let repo = TrainingRunRepository()
            experimentRuns = (try? await repo.findByExperiment(experimentId)) ?? []
        }
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    let project: ProjectRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.headline)
            if let description = project.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(Date(timeIntervalSince1970: project.updatedAt), style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Experiment Row

struct ExperimentRow: View {
    let experiment: ExperimentRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(experiment.name)
                .font(.headline)
            if let description = experiment.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(Date(timeIntervalSince1970: experiment.createdAt), style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Experiment Detail View

struct ExperimentDetailView: View {
    let experimentId: String
    let runs: [TrainingRun]
    @State private var selectedRunIds: Set<String> = []
    @State private var showComparison = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(runs.count) runs")
                    .foregroundColor(.secondary)

                Spacer()

                if selectedRunIds.count >= 2 {
                    Button("Compare Selected (\(selectedRunIds.count))") {
                        showComparison = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Runs list
            List(selection: $selectedRunIds) {
                ForEach(runs) { run in
                    RunComparisonRow(run: run)
                        .tag(run.id)
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Experiment Runs")
        .sheet(isPresented: $showComparison) {
            let selectedRuns = runs.filter { selectedRunIds.contains($0.id) }
            RunComparisonView(runs: selectedRuns)
        }
    }
}

// MARK: - Run Comparison Row

struct RunComparisonRow: View {
    let run: TrainingRun

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.name)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label("\(run.totalEpochs) epochs", systemImage: "repeat")
                    Label("BS: \(run.batchSize)", systemImage: "square.grid.3x3")
                    Label(String(format: "LR: %.4f", run.learningRate), systemImage: "dial.low")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(text: run.status.rawValue, color: run.status.color)

                if let accuracy = run.accuracy {
                    Text(String(format: "%.1f%%", accuracy * 100))
                        .font(.headline)
                        .foregroundColor(.green)
                }

                if let loss = run.loss {
                    Text(String(format: "Loss: %.4f", loss))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var description = ""
    let onCreated: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("New Project")
                .font(.headline)

            TextField("Project Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $description)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    createProject()
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    func createProject() {
        Task {
            let project = ProjectRecord(name: name, description: description.isEmpty ? nil : description)
            let repo = ProjectRepository()
            try? await repo.create(project)
            onCreated()
            dismiss()
        }
    }
}

// MARK: - New Experiment Sheet

struct NewExperimentSheet: View {
    @Environment(\.dismiss) var dismiss
    let projectId: String
    @State private var name = ""
    @State private var description = ""
    let onCreated: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("New Experiment")
                .font(.headline)

            TextField("Experiment Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $description)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    createExperiment()
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    func createExperiment() {
        Task {
            let experiment = ExperimentRecord(projectId: projectId, name: name, description: description.isEmpty ? nil : description)
            let repo = ExperimentRepository()
            try? await repo.create(experiment)
            onCreated()
            dismiss()
        }
    }
}
