import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            Group {
                switch appState.selectedTab {
                case .dashboard:
                    DashboardView()
                case .models:
                    ModelsView()
                case .runs:
                    RunsView()
                case .experiments:
                    ExperimentBrowserView()
                case .metrics:
                    MetricsDashboardView()
                case .datasets:
                    DatasetsView()
                case .inference:
                    InferenceView()
                case .settings:
                    SettingsView()
                }
            }
            .background(AppTheme.background)
        }
        .overlay {
            if appState.isLoading {
                LoadingOverlay(message: appState.loadingMessage)
            }
        }
        .overlay(alignment: .top) {
            if let successMessage = appState.successMessage {
                SuccessToast(message: successMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: appState.successMessage)
                    .padding(.top, 8)
            }
        }
        .alert("Error", isPresented: .init(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .sheet(isPresented: $appState.showNewModelSheet) {
            NewModelSheet()
        }
        .sheet(isPresented: $appState.showNewRunSheet) {
            NewRunSheet()
        }
        .sheet(isPresented: $appState.showImportDatasetSheet) {
            ImportDatasetSheet()
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var modelsExpanded = true
    @State private var runsExpanded = true

    var body: some View {
        List(selection: $appState.selectedTab) {
            Section("Overview") {
                Label(NavigationTab.dashboard.rawValue, systemImage: NavigationTab.dashboard.icon)
                    .tag(NavigationTab.dashboard)
            }

            // Models Section - Expandable with individual models
            Section("Models") {
                DisclosureGroup(isExpanded: $modelsExpanded) {
                    ForEach(appState.models) { model in
                        Button {
                            appState.selectedModelId = model.id
                            appState.selectedTab = .models
                        } label: {
                            SidebarModelRow(model: model)
                        }
                        .buttonStyle(.plain)
                    }

                    if appState.models.isEmpty {
                        Text("No models yet")
                            .font(.caption)
                            .foregroundColor(AppTheme.textMuted)
                            .padding(.leading, 4)
                    }
                } label: {
                    Button {
                        appState.selectedModelId = nil
                        appState.selectedTab = .models
                    } label: {
                        HStack {
                            Label("All Models", systemImage: NavigationTab.models.icon)
                            Spacer()
                            Text("\(appState.models.count)")
                                .font(.caption)
                                .foregroundColor(AppTheme.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Training Runs Section - Expandable with individual runs
            Section("Training") {
                DisclosureGroup(isExpanded: $runsExpanded) {
                    // Active runs first
                    if !appState.activeRuns.isEmpty {
                        ForEach(appState.activeRuns) { run in
                            Button {
                                appState.selectedRunId = run.id
                                appState.selectedTab = .runs
                            } label: {
                                SidebarRunRow(run: run, isActive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Recent completed runs
                    ForEach(appState.completedRuns.prefix(5)) { run in
                        Button {
                            appState.selectedRunId = run.id
                            appState.selectedTab = .runs
                        } label: {
                            SidebarRunRow(run: run, isActive: false)
                        }
                        .buttonStyle(.plain)
                    }

                    if appState.activeRuns.isEmpty && appState.completedRuns.isEmpty {
                        Text("No training runs yet")
                            .font(.caption)
                            .foregroundColor(AppTheme.textMuted)
                            .padding(.leading, 4)
                    }
                } label: {
                    Button {
                        appState.selectedRunId = nil
                        appState.selectedTab = .runs
                    } label: {
                        HStack {
                            Label("Training Runs", systemImage: NavigationTab.runs.icon)
                            Spacer()
                            if !appState.activeRuns.isEmpty {
                                HStack(spacing: 4) {
                                    PulsingDot(color: AppTheme.success, size: 6)
                                    Text("\(appState.activeRuns.count)")
                                        .font(.caption)
                                        .foregroundColor(AppTheme.success)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Data & Experiments") {
                Label(NavigationTab.experiments.rawValue, systemImage: NavigationTab.experiments.icon)
                    .tag(NavigationTab.experiments)

                Label(NavigationTab.datasets.rawValue, systemImage: NavigationTab.datasets.icon)
                    .tag(NavigationTab.datasets)
                    .badge(appState.datasets.count)

                Label(NavigationTab.inference.rawValue, systemImage: NavigationTab.inference.icon)
                    .tag(NavigationTab.inference)
            }

            Section("Analytics") {
                Label(NavigationTab.metrics.rawValue, systemImage: NavigationTab.metrics.icon)
                    .tag(NavigationTab.metrics)
            }

            Section {
                Label(NavigationTab.settings.rawValue, systemImage: NavigationTab.settings.icon)
                    .tag(NavigationTab.settings)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
        .background(AppTheme.background)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button(action: { appState.showNewModelSheet = true }) {
                        Label("New Model", systemImage: "cpu.fill")
                    }
                    Button(action: { appState.showNewRunSheet = true }) {
                        Label("New Training Run", systemImage: "play.fill")
                    }
                    Button(action: { appState.showImportDatasetSheet = true }) {
                        Label("Import Dataset", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(AppTheme.primary)
                }
            }
        }
    }
}

// MARK: - Sidebar Model Row

struct SidebarModelRow: View {
    let model: MLModel
    @EnvironmentObject var appState: AppState
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(model.framework.rawValue)
                    .font(.caption2)
                    .foregroundColor(AppTheme.textMuted)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.leading, 8)
        .contextMenu {
            Button {
                appState.selectedModelId = model.id
                appState.showNewRunSheet = true
            } label: {
                Label("Train Model", systemImage: "play.fill")
            }

            if model.status == .ready && model.filePath != nil {
                Button {
                    appState.selectedModelId = model.id
                    appState.selectedTab = .inference
                } label: {
                    Label("Run Inference", systemImage: "wand.and.stars")
                }
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.id, forType: .string)
            } label: {
                Label("Copy Model ID", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Model", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                appState.selectedModelId = model.id
                appState.showNewRunSheet = true
            } label: {
                Label("Train", systemImage: "play.fill")
            }
            .tint(AppTheme.success)
        }
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await appState.deleteModel(model) }
            }
        } message: {
            Text("Are you sure you want to delete \"\(model.name)\"? Associated training runs will also be deleted.")
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .ready: return AppTheme.success
        case .training: return AppTheme.warning
        case .draft: return AppTheme.textMuted
        case .failed: return AppTheme.error
        case .archived: return AppTheme.secondary
        case .importing: return AppTheme.primary
        case .deployed: return AppTheme.success
        case .deprecated: return AppTheme.warning
        }
    }
}

// MARK: - Sidebar Run Row

struct SidebarRunRow: View {
    let run: TrainingRun
    let isActive: Bool
    @EnvironmentObject var appState: AppState
    @State private var showDeleteConfirmation = false
    @State private var showCancelConfirmation = false

    var body: some View {
        HStack(spacing: 8) {
            if isActive {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: statusIcon)
                    .font(.caption)
                    .foregroundColor(statusColor)
                    .frame(width: 12)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(run.name)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                if isActive {
                    Text("\(Int(run.progress * 100))% - Epoch \(run.currentEpoch)/\(run.totalEpochs)")
                        .font(.caption2)
                        .foregroundColor(AppTheme.success)
                } else {
                    Text(run.status.rawValue)
                        .font(.caption2)
                        .foregroundColor(AppTheme.textMuted)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.leading, 8)
        .contextMenu {
            if run.status == .running {
                Button {
                    appState.pauseTraining(runId: run.id)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                Button(role: .destructive) {
                    showCancelConfirmation = true
                } label: {
                    Label("Stop Training", systemImage: "stop.fill")
                }
            } else if run.status == .paused {
                Button {
                    appState.resumeTraining(runId: run.id)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                Button(role: .destructive) {
                    showCancelConfirmation = true
                } label: {
                    Label("Stop Training", systemImage: "stop.fill")
                }
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(run.id, forType: .string)
            } label: {
                Label("Copy Run ID", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Run", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if run.status == .running {
                Button {
                    appState.pauseTraining(runId: run.id)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .tint(AppTheme.warning)
            } else if run.status == .paused {
                Button {
                    appState.resumeTraining(runId: run.id)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .tint(AppTheme.success)
            }
        }
        .alert("Delete Run", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await appState.deleteRun(run) }
            }
        } message: {
            Text("Are you sure you want to delete \"\(run.name)\"? This cannot be undone.")
        }
        .alert("Stop Training", isPresented: $showCancelConfirmation) {
            Button("Continue Training", role: .cancel) {}
            Button("Stop", role: .destructive) {
                appState.cancelTraining(runId: run.id)
            }
        } message: {
            Text("Are you sure you want to stop this training run? Progress will be lost.")
        }
    }

    private var statusIcon: String {
        switch run.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .paused: return "pause.circle.fill"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        switch run.status {
        case .completed: return AppTheme.success
        case .failed: return AppTheme.error
        case .cancelled: return AppTheme.warning
        case .paused: return AppTheme.warning
        default: return AppTheme.textMuted
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            AppTheme.background.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(AppTheme.primary)
                Text(message)
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(32)
            .background(AppTheme.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

// MARK: - Success Toast

struct SuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(AppTheme.success)

            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .cornerRadius(25)
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(AppTheme.success.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: AppTheme.success.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(color)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?

    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var buttonsOpacity: Double = 0

    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        VStack(spacing: 24) {
            // Animated Icon
            ZStack {
                Circle()
                    .fill(AppTheme.primary.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(AppTheme.primaryGradient)
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    iconScale = 1.0
                    iconOpacity = 1.0
                }
            }

            // Content
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.textPrimary)

                Text(message)
                    .font(.body)
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }
            .opacity(contentOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                    contentOpacity = 1.0
                }
            }

            // Action Buttons
            HStack(spacing: 12) {
                if let actionTitle = actionTitle, let action = action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(AppTheme.primaryGradient)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }

                if let secondaryTitle = secondaryActionTitle, let secondaryAction = secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.primary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(AppTheme.primary.opacity(0.15))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(buttonsOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                    buttonsOpacity = 1.0
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(AppTheme.background)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String?
    let actionLabel: String?
    let action: (() -> Void)?

    init(_ title: String, icon: String? = nil, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.icon = icon
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.primary)
            }
            Text(title)
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
            if let actionLabel = actionLabel, let action = action {
                Button(actionLabel, action: action)
                    .font(.caption)
                    .foregroundColor(AppTheme.primary)
                    .buttonStyle(.plain)
            }
        }
    }
}
