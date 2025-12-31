import SwiftUI
import Charts
import AppKit

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var storageStats: StorageStats?

    // Computed analytics
    var completedRuns: [TrainingRun] {
        appState.runs.filter { $0.status == .completed }
    }

    var averageAccuracy: Double? {
        let accuracies = completedRuns.compactMap { $0.accuracy }
        guard !accuracies.isEmpty else { return nil }
        return accuracies.reduce(0, +) / Double(accuracies.count)
    }

    var bestModel: (run: TrainingRun, accuracy: Double)? {
        completedRuns
            .compactMap { run -> (TrainingRun, Double)? in
                guard let acc = run.accuracy else { return nil }
                return (run, acc)
            }
            .max(by: { $0.1 < $1.1 })
    }

    var totalTrainingTime: TimeInterval {
        completedRuns.reduce(0) { total, run in
            guard let finished = run.finishedAt else { return total }
            return total + finished.timeIntervalSince(run.startedAt)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dashboard")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Overview of your ML platform")
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Button(action: { Task { await appState.loadData() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .padding(.horizontal)

                // Stats Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(
                        title: "Models",
                        value: "\(appState.models.count)",
                        icon: "cpu",
                        color: .blue
                    )

                    StatCard(
                        title: "Active Runs",
                        value: "\(appState.activeRuns.count)",
                        icon: "play.circle.fill",
                        color: .green
                    )

                    StatCard(
                        title: "Datasets",
                        value: "\(appState.datasets.count)",
                        icon: "folder.fill",
                        color: .orange
                    )

                    StatCard(
                        title: "Storage",
                        value: storageStats.map { formatBytes($0.totalSize) } ?? "—",
                        icon: "internaldrive",
                        color: .purple
                    )
                }
                .padding(.horizontal)

                // Training Analytics Section (only shown if there are completed runs)
                if !completedRuns.isEmpty {
                    TrainingAnalyticsSection(
                        completedRuns: completedRuns,
                        averageAccuracy: averageAccuracy,
                        bestModel: bestModel,
                        totalTrainingTime: totalTrainingTime
                    )
                    .padding(.horizontal)
                }

                // Active Training Runs
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Active Training Runs", icon: "play.circle", actionLabel: appState.activeRuns.isEmpty ? nil : "View All") {
                        appState.selectedTab = .runs
                    }

                    if appState.activeRuns.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                            Text("No active training runs")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Start Training") {
                                appState.showNewRunSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    } else {
                        ForEach(appState.activeRuns.prefix(3)) { run in
                            ActiveRunCard(run: run)
                        }
                    }
                }
                .padding(.horizontal)

                // Recent Models
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Recent Models", icon: "cpu", actionLabel: appState.models.isEmpty ? nil : "View All") {
                        appState.selectedTab = .models
                    }

                    if appState.models.isEmpty {
                        HStack {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.blue)
                            Text("No models yet")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Add Model") {
                                appState.showNewModelSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(appState.models.prefix(6)) { model in
                                ModelQuickCard(model: model)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Recent Completed Runs
                if !appState.completedRuns.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Recently Completed", icon: "checkmark.circle")

                        ForEach(appState.completedRuns.prefix(3)) { run in
                            CompletedRunCard(run: run)
                        }
                    }
                    .padding(.horizontal)
                }

                // Getting Started (shown when no data)
                if appState.models.isEmpty && appState.datasets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Getting Started", icon: "sparkles")

                        VStack(spacing: 16) {
                            HStack(spacing: 16) {
                                Image(systemName: "wand.and.stars")
                                    .font(.largeTitle)
                                    .foregroundColor(.accentColor)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Welcome to Performant3")
                                        .font(.headline)
                                    Text("Load demo data to explore the app, or import your own models and datasets.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }

                            HStack(spacing: 12) {
                                Button(action: { Task { await appState.loadDemoData() } }) {
                                    Label("Load Demo Data", systemImage: "sparkles")
                                }
                                .buttonStyle(.borderedProminent)

                                Button(action: { appState.showNewModelSheet = true }) {
                                    Label("Import Model", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.bordered)

                                Button(action: { appState.showImportDatasetSheet = true }) {
                                    Label("Import Dataset", systemImage: "folder.badge.plus")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

                // Quick Actions
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Quick Actions", icon: "bolt")

                    HStack(spacing: 12) {
                        QuickActionButton(
                            title: "Import Model",
                            icon: "square.and.arrow.down",
                            color: .blue
                        ) {
                            appState.showNewModelSheet = true
                        }

                        QuickActionButton(
                            title: "Start Training",
                            icon: "play.fill",
                            color: .green
                        ) {
                            appState.showNewRunSheet = true
                        }

                        QuickActionButton(
                            title: "Import Dataset",
                            icon: "folder.badge.plus",
                            color: .orange
                        ) {
                            appState.showImportDatasetSheet = true
                        }

                        QuickActionButton(
                            title: "Run Inference",
                            icon: "wand.and.stars",
                            color: .purple
                        ) {
                            appState.selectedTab = .inference
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            storageStats = await appState.getStorageStats()
        }
    }
}

// MARK: - Active Run Card

struct ActiveRunCard: View {
    let run: TrainingRun
    @EnvironmentObject var appState: AppState
    @State private var showCancelConfirmation = false

    var body: some View {
        HStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(run.status.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: run.status.icon)
                    .foregroundColor(run.status.color)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(run.name)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(run.modelName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("Epoch \(run.currentEpoch)/\(run.totalEpochs)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Progress
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(run.progress * 100))%")
                    .font(.headline)
                    .monospacedDigit()
                ProgressView(value: run.progress)
                    .frame(width: 120)
            }

            // Actions
            HStack(spacing: 8) {
                if run.status == .running {
                    Button(action: { appState.pauseTraining(runId: run.id) }) {
                        Image(systemName: "pause.fill")
                    }
                    .buttonStyle(.borderless)
                } else if run.status == .paused {
                    Button(action: { appState.resumeTraining(runId: run.id) }) {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderless)
                }

                Button(action: { showCancelConfirmation = true }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .alert("Stop Training", isPresented: $showCancelConfirmation) {
            Button("Continue Training", role: .cancel) {}
            Button("Stop", role: .destructive) {
                appState.cancelTraining(runId: run.id)
            }
        } message: {
            Text("Are you sure you want to stop this training run?")
        }
    }
}

// MARK: - Model Quick Card

struct ModelQuickCard: View {
    let model: MLModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: model.framework.icon)
                    .foregroundColor(model.framework.color)
                Spacer()
                StatusBadge(text: model.status.rawValue, color: model.status.color)
            }

            Text(model.name)
                .fontWeight(.medium)
                .lineLimit(1)

            HStack {
                Text(model.framework.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if model.accuracy > 0 {
                    Text(String(format: "%.1f%%", model.accuracy * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .contextMenu {
            Button(action: {
                appState.selectedModelId = model.id
                appState.showNewRunSheet = true
            }) {
                Label("Train Model", systemImage: "play.fill")
            }
            Button(action: {
                appState.selectedModelId = model.id
                appState.selectedTab = .inference
            }) {
                Label("Run Inference", systemImage: "wand.and.stars")
            }
            .disabled(model.filePath == nil)
            Divider()
            Button(action: {
                appState.selectedModelId = model.id
                appState.selectedTab = .models
            }) {
                Label("View Details", systemImage: "info.circle")
            }
        }
    }
}

// MARK: - Completed Run Card

struct CompletedRunCard: View {
    let run: TrainingRun
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.name)
                    .fontWeight(.medium)
                Text(run.modelName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let accuracy = run.accuracy {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f%%", accuracy * 100))
                        .fontWeight(.medium)
                    Text("Accuracy")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(run.duration)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .contextMenu {
            Button(action: {
                appState.selectedRunId = run.id
                appState.selectedTab = .runs
            }) {
                Label("View Details", systemImage: "info.circle")
            }
            Button(action: {
                // Export model from this run
                exportModel()
            }) {
                Label("Export Model", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(action: {
                appState.selectedTab = .experiments
            }) {
                Label("Compare Runs", systemImage: "chart.xyaxis.line")
            }
        }
    }

    private func exportModel() {
        Task {
            guard let checkpoint = try? await CheckpointManager.shared.getLatestCheckpoint(runId: run.id) else {
                appState.errorMessage = "No checkpoint found for this run"
                return
            }

            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "\(run.name).mlpackage"
                panel.allowedContentTypes = [.init(filenameExtension: "mlpackage")!]

                if panel.runModal() == .OK, let url = panel.url {
                    do {
                        let checkpointURL = URL(fileURLWithPath: checkpoint.path)
                        try FileManager.default.copyItem(at: checkpointURL, to: url)
                        appState.showSuccess("Model exported to \(url.lastPathComponent)")
                    } catch {
                        appState.errorMessage = "Export failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Training Analytics Section

struct TrainingAnalyticsSection: View {
    let completedRuns: [TrainingRun]
    let averageAccuracy: Double?
    let bestModel: (run: TrainingRun, accuracy: Double)?
    let totalTrainingTime: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Training Analytics", icon: "chart.bar.xaxis")

            HStack(spacing: 16) {
                // Performance Metrics
                AnalyticsMetricsColumn(
                    completedRuns: completedRuns,
                    averageAccuracy: averageAccuracy,
                    bestModel: bestModel,
                    totalTrainingTime: totalTrainingTime
                )
                .frame(width: 220)

                // Accuracy Trend Chart
                AccuracyTrendChart(
                    completedRuns: completedRuns,
                    bestAccuracy: bestModel?.accuracy
                )
                .frame(maxWidth: .infinity)

                // Architecture Distribution
                ArchitectureDistributionChart(completedRuns: completedRuns)
                    .frame(width: 200)
            }
        }
    }
}

struct AnalyticsMetricsColumn: View {
    let completedRuns: [TrainingRun]
    let averageAccuracy: Double?
    let bestModel: (run: TrainingRun, accuracy: Double)?
    let totalTrainingTime: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AnalyticsMetricCard(
                title: "Average Accuracy",
                value: averageAccuracy.map { String(format: "%.1f%%", $0 * 100) } ?? "—",
                subtitle: "across \(completedRuns.count) runs",
                icon: "target",
                color: .green
            )

            if let best = bestModel {
                AnalyticsMetricCard(
                    title: "Best Model",
                    value: String(format: "%.1f%%", best.accuracy * 100),
                    subtitle: best.run.name,
                    icon: "star.fill",
                    color: .yellow
                )
            }

            AnalyticsMetricCard(
                title: "Total Training Time",
                value: formatDuration(totalTrainingTime),
                subtitle: "\(completedRuns.count) completed runs",
                icon: "clock.fill",
                color: .blue
            )
        }
    }
}

struct AccuracyTrendChart: View {
    let completedRuns: [TrainingRun]
    let bestAccuracy: Double?

    var chartData: [(name: String, accuracy: Double)] {
        completedRuns.suffix(10).compactMap { run in
            guard let acc = run.accuracy else { return nil }
            return (run.name, acc * 100)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accuracy Trend")
                .font(.headline)

            if chartData.count > 1 {
                Chart(chartData, id: \.name) { item in
                    BarMark(
                        x: .value("Run", item.name),
                        y: .value("Accuracy", item.accuracy)
                    )
                    .foregroundStyle(
                        item.accuracy == (bestAccuracy ?? 0) * 100 ? Color.yellow : Color.accentColor
                    )
                    .cornerRadius(4)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100])
                }
                .frame(height: 180)
            } else {
                ContentUnavailableView(
                    "Not Enough Data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Complete more training runs to see trends")
                )
                .frame(height: 180)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct ArchitectureDistributionChart: View {
    let completedRuns: [TrainingRun]

    var archData: [(arch: String, count: Int)] {
        let counts = Dictionary(grouping: completedRuns, by: { $0.architectureType })
            .mapValues { $0.count }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Architectures Used")
                .font(.headline)

            if !archData.isEmpty {
                Chart(archData, id: \.arch) { item in
                    SectorMark(
                        angle: .value("Count", item.count),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Architecture", item.arch))
                    .cornerRadius(4)
                }
                .chartLegend(position: .bottom, alignment: .center)
                .frame(height: 180)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Analytics Metric Card

struct AnalyticsMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}
