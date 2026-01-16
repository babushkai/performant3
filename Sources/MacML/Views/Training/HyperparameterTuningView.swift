import SwiftUI

// MARK: - Hyperparameter Tuning View

struct HyperparameterTuningView: View {
    @ObservedObject var tuner = HyperparameterTuner.shared
    @State private var showNewStudySheet = false
    @State private var selectedStudyId: String?

    var body: some View {
        NavigationSplitView {
            // Studies List
            List(selection: $selectedStudyId) {
                Section("Active Studies") {
                    ForEach(tuner.studies.filter { $0.status == .running || $0.status == .paused }) { study in
                        StudyRow(study: study)
                            .tag(study.id)
                    }
                }

                Section("Completed Studies") {
                    ForEach(tuner.studies.filter { $0.status == .completed }) { study in
                        StudyRow(study: study)
                            .tag(study.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Hyperparameter Tuning")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewStudySheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        } detail: {
            if let studyId = selectedStudyId,
               let study = tuner.studies.first(where: { $0.id == studyId }) {
                StudyDetailView(study: study)
            } else {
                ContentUnavailableView(
                    "No Study Selected",
                    systemImage: "slider.horizontal.3",
                    description: Text("Select a study from the sidebar or create a new one")
                )
            }
        }
        .sheet(isPresented: $showNewStudySheet) {
            NewStudySheet()
        }
    }
}

// MARK: - Study Row

struct StudyRow: View {
    let study: TuningStudy
    @ObservedObject var tuner = HyperparameterTuner.shared

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(study.config.name)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(study.config.searchStrategy.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(study.completedTrials.count)/\(study.config.maxTrials) trials")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if study.status == .running {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if study.status == .running {
                Button("Pause") {
                    tuner.pauseStudy(study.id)
                }
            } else if study.status == .paused {
                Button("Resume") {
                    tuner.resumeStudy(study.id)
                }
            } else if study.status == .created {
                Button("Start") {
                    tuner.startStudy(study.id)
                }
            }

            Divider()

            Button("Delete", role: .destructive) {
                tuner.deleteStudy(study.id)
            }
        }
    }

    private var statusColor: Color {
        switch study.status {
        case .created: return .gray
        case .running: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Study Detail View

struct StudyDetailView: View {
    let study: TuningStudy
    @ObservedObject var tuner = HyperparameterTuner.shared
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            StudyHeaderView(study: study)

            Divider()

            // Tabs
            Picker("View", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Trials").tag(1)
                Text("Parameters").tag(2)
                Text("Analysis").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()

            // Tab content
            switch selectedTab {
            case 0:
                StudyOverviewTab(study: study)
            case 1:
                TrialsListTab(study: study)
            case 2:
                ParameterAnalysisTab(study: study)
            case 3:
                OptimizationAnalysisTab(study: study)
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Study Header

struct StudyHeaderView: View {
    let study: TuningStudy
    @ObservedObject var tuner = HyperparameterTuner.shared

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(study.config.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    Label(study.config.searchStrategy.rawValue, systemImage: "magnifyingglass")
                    Label(study.config.objective.rawValue, systemImage: "target")
                    Label("\(study.config.parameters.count) params", systemImage: "slider.horizontal.3")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Progress
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(study.progress * 100))%")
                    .font(.title3)
                    .fontWeight(.medium)

                ProgressView(value: study.progress)
                    .frame(width: 100)
            }

            // Actions
            HStack(spacing: 8) {
                if study.status == .running {
                    Button {
                        tuner.pauseStudy(study.id)
                    } label: {
                        Image(systemName: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                } else if study.status == .paused || study.status == .created {
                    Button {
                        if study.status == .created {
                            tuner.startStudy(study.id)
                        } else {
                            tuner.resumeStudy(study.id)
                        }
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }
}

// MARK: - Overview Tab

struct StudyOverviewTab: View {
    let study: TuningStudy

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Best trial
                if let bestTrial = study.bestTrial {
                    GroupBox("Best Trial") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Trial #\(bestTrial.trialNumber)")
                                    .font(.headline)
                                Spacer()
                                if let score = bestTrial.score {
                                    Text(String(format: "%.4f", score))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                }
                            }

                            Divider()

                            // Parameters
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(Array(bestTrial.parameters.keys.sorted()), id: \.self) { key in
                                    HStack {
                                        Text(key)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(bestTrial.parameters[key]?.description ?? "-")
                                            .fontWeight(.medium)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .padding()
                    }
                }

                // Statistics
                GroupBox("Statistics") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        TuningStatCard(title: "Total Trials", value: "\(study.trials.count)")
                        TuningStatCard(title: "Completed", value: "\(study.completedTrials.count)")
                        TuningStatCard(title: "Failed", value: "\(study.trials.filter { $0.status == .failed }.count)")

                        if let best = bestScore {
                            TuningStatCard(title: "Best Score", value: String(format: "%.4f", best))
                        }
                        if let worst = worstScore {
                            TuningStatCard(title: "Worst Score", value: String(format: "%.4f", worst))
                        }
                        if let avg = averageScore {
                            TuningStatCard(title: "Avg Score", value: String(format: "%.4f", avg))
                        }
                    }
                    .padding()
                }

                // Score distribution chart
                if study.completedTrials.count > 0 {
                    GroupBox("Score Distribution") {
                        ScoreDistributionChart(trials: study.completedTrials)
                            .frame(height: 200)
                            .padding()
                    }
                }
            }
            .padding()
        }
    }

    private var bestScore: Double? {
        study.completedTrials.compactMap { $0.score }.max()
    }

    private var worstScore: Double? {
        study.completedTrials.compactMap { $0.score }.min()
    }

    private var averageScore: Double? {
        let scores = study.completedTrials.compactMap { $0.score }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
}

struct TuningStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Trials List Tab

struct TrialsListTab: View {
    let study: TuningStudy
    @State private var sortOrder = [KeyPathComparator(\HyperparameterTrial.trialNumber)]

    var body: some View {
        Table(study.trials, sortOrder: $sortOrder) {
            TableColumn("#", value: \.trialNumber) { trial in
                Text("\(trial.trialNumber)")
            }
            .width(40)

            TableColumn("Status", value: \.status.rawValue) { trial in
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor(trial.status))
                        .frame(width: 8, height: 8)
                    Text(trial.status.rawValue)
                }
            }
            .width(100)

            TableColumn("Score") { trial in
                if let score = trial.score {
                    Text(String(format: "%.4f", score))
                        .fontWeight(study.bestTrialId == trial.id ? .bold : .regular)
                        .foregroundColor(study.bestTrialId == trial.id ? .green : .primary)
                } else {
                    Text("-")
                        .foregroundColor(.secondary)
                }
            }
            .width(80)

            TableColumn("Duration") { trial in
                if let duration = trial.duration {
                    Text(formatDuration(duration))
                        .foregroundColor(.secondary)
                } else {
                    Text("-")
                        .foregroundColor(.secondary)
                }
            }
            .width(80)

            TableColumn("Parameters") { trial in
                Text(formatParameters(trial.parameters))
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }

    private func statusColor(_ status: HyperparameterTrial.TrialStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .pruned: return .orange
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            return String(format: "%.1fm", duration / 60)
        }
    }

    private func formatParameters(_ params: [String: ParameterValue]) -> String {
        params.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}

// MARK: - Parameter Analysis Tab

struct ParameterAnalysisTab: View {
    let study: TuningStudy
    @State private var selectedParameter: String?

    var body: some View {
        HSplitView {
            // Parameter list
            List(study.config.parameters, selection: $selectedParameter) { param in
                VStack(alignment: .leading, spacing: 4) {
                    Text(param.name)
                        .fontWeight(.medium)
                    Text(param.type.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .tag(param.name)
            }
            .frame(width: 200)

            // Parameter detail
            if let paramName = selectedParameter,
               let param = study.config.parameters.first(where: { $0.name == paramName }) {
                ParameterDetailView(parameter: param, trials: study.completedTrials)
            } else {
                ContentUnavailableView(
                    "Select a Parameter",
                    systemImage: "slider.horizontal.3",
                    description: Text("Select a parameter to see its analysis")
                )
            }
        }
    }
}

struct ParameterDetailView: View {
    let parameter: HyperparameterSpec
    let trials: [HyperparameterTrial]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Parameter info
                GroupBox("Parameter Info") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Name", value: parameter.name)
                        LabeledContent("Type", value: parameter.type.rawValue)
                        LabeledContent("Scale", value: parameter.scale.rawValue)

                        if let min = parameter.minValue {
                            LabeledContent("Min", value: String(format: "%.4g", min))
                        }
                        if let max = parameter.maxValue {
                            LabeledContent("Max", value: String(format: "%.4g", max))
                        }
                        if let step = parameter.stepSize {
                            LabeledContent("Step", value: String(format: "%.4g", step))
                        }
                        if let cats = parameter.categories {
                            LabeledContent("Categories", value: cats.joined(separator: ", "))
                        }
                    }
                    .padding()
                }

                // Value vs Score chart
                GroupBox("Value vs Score") {
                    ParameterScoreChart(parameter: parameter, trials: trials)
                        .frame(height: 250)
                        .padding()
                }

                // Value distribution
                GroupBox("Value Distribution") {
                    ParameterDistributionChart(parameter: parameter, trials: trials)
                        .frame(height: 150)
                        .padding()
                }
            }
            .padding()
        }
    }
}

// MARK: - Optimization Analysis Tab

struct OptimizationAnalysisTab: View {
    let study: TuningStudy

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Optimization history
                GroupBox("Optimization History") {
                    OptimizationHistoryChart(trials: study.completedTrials)
                        .frame(height: 250)
                        .padding()
                }

                // Convergence analysis
                if study.completedTrials.count >= 5 {
                    GroupBox("Convergence Analysis") {
                        ConvergenceView(trials: study.completedTrials)
                            .padding()
                    }
                }

                // Parameter importance
                GroupBox("Parameter Importance") {
                    ParameterImportanceView(study: study)
                        .padding()
                }
            }
            .padding()
        }
    }
}

struct ConvergenceView: View {
    let trials: [HyperparameterTrial]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let recentScores = trials.suffix(10).compactMap { $0.score }
            let allScores = trials.compactMap { $0.score }

            if let recentStd = standardDeviation(recentScores),
               let overallStd = standardDeviation(allScores) {

                let convergenceRatio = recentStd / max(overallStd, 0.0001)

                HStack(spacing: 20) {
                    VStack {
                        Text(String(format: "%.4f", overallStd))
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Overall Std Dev")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text(String(format: "%.4f", recentStd))
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Recent Std Dev")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text(convergenceRatio < 0.5 ? "Converging" : "Exploring")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(convergenceRatio < 0.5 ? .green : .blue)
                        Text("Status")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }
}

struct ParameterImportanceView: View {
    let study: TuningStudy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parameterImportance, id: \.name) { item in
                HStack {
                    Text(item.name)
                        .frame(width: 120, alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: geo.size.width * CGFloat(item.importance))
                    }
                    .frame(height: 20)

                    Text(String(format: "%.1f%%", item.importance * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    private var parameterImportance: [(name: String, importance: Double)] {
        // Simple importance estimation based on correlation with score
        var importances: [(name: String, importance: Double)] = []

        for param in study.config.parameters {
            let correlation = calculateCorrelation(paramName: param.name)
            importances.append((name: param.name, importance: abs(correlation)))
        }

        // Normalize
        let total = importances.map { $0.importance }.reduce(0, +)
        if total > 0 {
            importances = importances.map { ($0.name, $0.importance / total) }
        }

        return importances.sorted { $0.importance > $1.importance }
    }

    private func calculateCorrelation(paramName: String) -> Double {
        let pairs = study.completedTrials.compactMap { trial -> (Double, Double)? in
            guard let score = trial.score,
                  let value = trial.parameters[paramName]?.doubleValue else { return nil }
            return (value, score)
        }

        guard pairs.count > 2 else { return 0 }

        let xMean = pairs.map { $0.0 }.reduce(0, +) / Double(pairs.count)
        let yMean = pairs.map { $0.1 }.reduce(0, +) / Double(pairs.count)

        var covariance = 0.0
        var xVariance = 0.0
        var yVariance = 0.0

        for (x, y) in pairs {
            let xDiff = x - xMean
            let yDiff = y - yMean
            covariance += xDiff * yDiff
            xVariance += xDiff * xDiff
            yVariance += yDiff * yDiff
        }

        let denominator = sqrt(xVariance * yVariance)
        guard denominator > 0 else { return 0 }

        return covariance / denominator
    }
}

// MARK: - Charts

struct ScoreDistributionChart: View {
    let trials: [HyperparameterTrial]

    var body: some View {
        let scores = trials.compactMap { $0.score }
        let bins = createHistogram(scores, binCount: 10)

        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(bins.enumerated()), id: \.offset) { index, bin in
                    VStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(height: CGFloat(bin.count) / CGFloat(maxBinCount(bins)) * (geo.size.height - 20))

                        Text(String(format: "%.2f", bin.range.lowerBound))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func createHistogram(_ values: [Double], binCount: Int) -> [(range: Range<Double>, count: Int)] {
        guard let minVal = values.min(), let maxVal = values.max(), minVal < maxVal else {
            return []
        }

        let binWidth = (maxVal - minVal) / Double(binCount)
        var bins: [(range: Range<Double>, count: Int)] = []

        for i in 0..<binCount {
            let lower = minVal + Double(i) * binWidth
            let upper = i == binCount - 1 ? maxVal + 0.001 : minVal + Double(i + 1) * binWidth
            let count = values.filter { $0 >= lower && $0 < upper }.count
            bins.append((range: lower..<upper, count: count))
        }

        return bins
    }

    private func maxBinCount(_ bins: [(range: Range<Double>, count: Int)]) -> Int {
        max(bins.map { $0.count }.max() ?? 1, 1)
    }
}

struct ParameterScoreChart: View {
    let parameter: HyperparameterSpec
    let trials: [HyperparameterTrial]

    var body: some View {
        let points = trials.compactMap { trial -> CGPoint? in
            guard let score = trial.score,
                  let value = trial.parameters[parameter.name]?.doubleValue else { return nil }
            return CGPoint(x: value, y: score)
        }

        GeometryReader { geo in
            if let xRange = xAxisRange, let yRange = yAxisRange {
                ZStack {
                    // Grid
                    ForEach(0..<5) { i in
                        let y = geo.size.height * CGFloat(i) / 4
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    }

                    // Points
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        let x = (point.x - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound) * geo.size.width
                        let y = geo.size.height - (point.y - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound) * geo.size.height

                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }

    private var xAxisRange: ClosedRange<Double>? {
        let values = trials.compactMap { $0.parameters[parameter.name]?.doubleValue }
        guard let min = values.min(), let max = values.max() else { return nil }
        return min...max
    }

    private var yAxisRange: ClosedRange<Double>? {
        let scores = trials.compactMap { $0.score }
        guard let min = scores.min(), let max = scores.max() else { return nil }
        let padding = (max - min) * 0.1
        return (min - padding)...(max + padding)
    }
}

struct ParameterDistributionChart: View {
    let parameter: HyperparameterSpec
    let trials: [HyperparameterTrial]

    var body: some View {
        let values = trials.compactMap { $0.parameters[parameter.name]?.doubleValue }

        GeometryReader { geo in
            if let min = values.min(), let max = values.max(), min < max {
                ZStack(alignment: .bottom) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        let x = (value - min) / (max - min) * geo.size.width

                        Rectangle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 3, height: geo.size.height)
                            .position(x: x, y: geo.size.height / 2)
                    }
                }
            }
        }
    }
}

struct OptimizationHistoryChart: View {
    let trials: [HyperparameterTrial]

    private var sortedTrials: [HyperparameterTrial] {
        trials.sorted { $0.trialNumber < $1.trialNumber }
    }

    private var bestSoFar: [Double] {
        var result: [Double] = []
        var currentBest: Double?
        for trial in sortedTrials {
            if let score = trial.score {
                if let best = currentBest {
                    currentBest = max(best, score)
                } else {
                    currentBest = score
                }
            }
            result.append(currentBest ?? 0)
        }
        return result
    }

    var body: some View {
        let bestValues = bestSoFar
        let sorted = sortedTrials

        GeometryReader { geo in
            if let minScore = bestValues.min(), let maxScore = bestValues.max(), minScore < maxScore {
                let range = maxScore - minScore
                let padding = range * 0.1

                ZStack {
                    // All scores
                    Path { path in
                        for (i, trial) in sorted.enumerated() {
                            if let score = trial.score {
                                let x = CGFloat(i) / CGFloat(max(sorted.count - 1, 1)) * geo.size.width
                                let y = geo.size.height - (score - minScore + padding) / (range + 2 * padding) * geo.size.height

                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                    }
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)

                    // Best so far
                    Path { path in
                        for (i, best) in bestValues.enumerated() {
                            let x = CGFloat(i) / CGFloat(max(bestValues.count - 1, 1)) * geo.size.width
                            let y = geo.size.height - (best - minScore + padding) / (range + 2 * padding) * geo.size.height

                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.green, lineWidth: 2)

                    // Points
                    ForEach(Array(sorted.enumerated()), id: \.offset) { i, trial in
                        if let score = trial.score {
                            let x = CGFloat(i) / CGFloat(max(sorted.count - 1, 1)) * geo.size.width
                            let y = geo.size.height - (score - minScore + padding) / (range + 2 * padding) * geo.size.height

                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                                .position(x: x, y: y)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - New Study Sheet

struct NewStudySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tuner = HyperparameterTuner.shared

    @State private var studyName = ""
    @State private var selectedModelId = ""
    @State private var searchStrategy: TuningStudyConfig.SearchStrategy = .random
    @State private var objective: TuningStudyConfig.Objective = .minimizeLoss
    @State private var maxTrials = 20
    @State private var parallelTrials = 1
    @State private var selectedParameters: Set<String> = []
    @State private var enableEarlyStopping = false
    @State private var earlyStoppingPatience = 5

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Tuning Study")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            Form {
                Section("Basic Info") {
                    TextField("Study Name", text: $studyName)

                    Picker("Search Strategy", selection: $searchStrategy) {
                        ForEach(TuningStudyConfig.SearchStrategy.allCases, id: \.self) { strategy in
                            Text(strategy.rawValue).tag(strategy)
                        }
                    }

                    Text(searchStrategy.description)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Objective", selection: $objective) {
                        Text("Minimize Loss").tag(TuningStudyConfig.Objective.minimizeLoss)
                        Text("Maximize Accuracy").tag(TuningStudyConfig.Objective.maximizeAccuracy)
                    }
                }

                Section("Trials") {
                    Stepper("Max Trials: \(maxTrials)", value: $maxTrials, in: 5...200, step: 5)
                    Stepper("Parallel Trials: \(parallelTrials)", value: $parallelTrials, in: 1...4)
                }

                Section("Parameters") {
                    ForEach(HyperparameterTuner.commonParameters) { param in
                        Toggle(param.name, isOn: Binding(
                            get: { selectedParameters.contains(param.name) },
                            set: { isSelected in
                                if isSelected {
                                    selectedParameters.insert(param.name)
                                } else {
                                    selectedParameters.remove(param.name)
                                }
                            }
                        ))
                    }
                }

                Section("Early Stopping") {
                    Toggle("Enable Early Stopping", isOn: $enableEarlyStopping)
                    if enableEarlyStopping {
                        Stepper("Patience: \(earlyStoppingPatience)", value: $earlyStoppingPatience, in: 3...20)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Button("Create Study") {
                    createStudy()
                }
                .buttonStyle(.borderedProminent)
                .disabled(studyName.isEmpty || selectedParameters.isEmpty)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
    }

    private func createStudy() {
        let parameters = HyperparameterTuner.commonParameters.filter { selectedParameters.contains($0.name) }

        let config = TuningStudyConfig(
            name: studyName,
            modelId: selectedModelId,
            objective: objective,
            searchStrategy: searchStrategy,
            parameters: parameters,
            maxTrials: maxTrials,
            parallelTrials: parallelTrials,
            earlyStoppingPatience: enableEarlyStopping ? earlyStoppingPatience : nil,
            earlyStoppingMinDelta: enableEarlyStopping ? 0.001 : nil,
            pruningEnabled: false,
            baseConfig: TrainingConfig.default
        )

        let study = tuner.createStudy(config: config)
        tuner.startStudy(study.id)
        dismiss()
    }
}
