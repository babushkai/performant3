import SwiftUI
import Charts

// MARK: - Run Comparison View

struct RunComparisonView: View {
    let runs: [TrainingRun]
    @Environment(\.dismiss) var dismiss
    @State private var selectedMetric: MetricType = .loss
    @State private var selectedChartType: ChartType = .line
    @State private var showTable = true

    enum MetricType: String, CaseIterable {
        case loss = "Loss"
        case accuracy = "Accuracy"
        case precision = "Precision"
        case recall = "Recall"
        case f1Score = "F1 Score"
    }

    enum ChartType: String, CaseIterable {
        case line = "Line"
        case radar = "Radar"
        case parallel = "Parallel"

        var icon: String {
            switch self {
            case .line: return "chart.xyaxis.line"
            case .radar: return "chart.pie"
            case .parallel: return "chart.bar.xaxis"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Comparing \(runs.count) Runs")
                    .font(.headline)

                Spacer()

                // Chart type selector
                Picker("Chart", selection: $selectedChartType) {
                    ForEach(ChartType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                if selectedChartType == .line {
                    Picker("Metric", selection: $selectedMetric) {
                        ForEach(MetricType.allCases, id: \.self) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                Toggle(isOn: $showTable) {
                    Image(systemName: "tablecells")
                }
                .toggleStyle(.button)

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            HSplitView {
                // Chart
                Group {
                    switch selectedChartType {
                    case .line:
                        ComparisonChart(runs: runs, metricType: selectedMetric)
                    case .radar:
                        RadarComparisonChart(runs: runs)
                    case .parallel:
                        ParallelCoordinatesChart(runs: runs)
                    }
                }
                .frame(minWidth: 400)
                .padding()

                // Table
                if showTable {
                    ComparisonTable(runs: runs)
                        .frame(minWidth: 300, maxWidth: 400)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

// MARK: - Comparison Chart

struct ComparisonChart: View {
    let runs: [TrainingRun]
    let metricType: RunComparisonView.MetricType

    var body: some View {
        VStack(alignment: .leading) {
            Text(metricType.rawValue)
                .font(.headline)

            Chart {
                ForEach(runs) { run in
                    ForEach(run.metrics) { metric in
                        let value = valueForMetric(metric)
                        if let value = value {
                            LineMark(
                                x: .value("Epoch", metric.epoch),
                                y: .value(metricType.rawValue, value)
                            )
                            .foregroundStyle(by: .value("Run", run.name))

                            PointMark(
                                x: .value("Epoch", metric.epoch),
                                y: .value(metricType.rawValue, value)
                            )
                            .foregroundStyle(by: .value("Run", run.name))
                        }
                    }
                }
            }
            .chartXAxisLabel("Epoch")
            .chartYAxisLabel(metricType.rawValue)
            .chartLegend(position: .bottom)
            .frame(minHeight: 300)
        }
    }

    private func valueForMetric(_ metric: MetricPoint) -> Double? {
        switch metricType {
        case .loss:
            return metric.loss
        case .accuracy:
            return metric.accuracy
        case .precision:
            return metric.precision
        case .recall:
            return metric.recall
        case .f1Score:
            return metric.f1Score
        }
    }
}

// MARK: - Comparison Table

struct ComparisonTable: View {
    let runs: [TrainingRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Run Parameters")
                .font(.headline)
                .padding()

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Header row
                    HStack {
                        Text("Parameter")
                            .frame(width: 100, alignment: .leading)
                            .fontWeight(.semibold)

                        ForEach(runs) { run in
                            Text(run.name)
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Data rows
                    ParameterRow(label: "Status", values: runs.map { $0.status.rawValue })
                    ParameterRow(label: "Epochs", values: runs.map { "\($0.totalEpochs)" })
                    ParameterRow(label: "Batch Size", values: runs.map { "\($0.batchSize)" })
                    ParameterRow(label: "Learning Rate", values: runs.map { String(format: "%.5f", $0.learningRate) })
                    ParameterRow(label: "Final Loss", values: runs.map { $0.loss.map { String(format: "%.4f", $0) } ?? "—" })
                    ParameterRow(label: "Final Accuracy", values: runs.map { $0.accuracy.map { String(format: "%.2f%%", $0 * 100) } ?? "—" })
                    ParameterRow(label: "Precision", values: runs.map { $0.precision.map { String(format: "%.2f%%", $0 * 100) } ?? "—" })
                    ParameterRow(label: "Recall", values: runs.map { $0.recall.map { String(format: "%.2f%%", $0 * 100) } ?? "—" })
                    ParameterRow(label: "F1 Score", values: runs.map { $0.f1Score.map { String(format: "%.2f%%", $0 * 100) } ?? "—" })
                    ParameterRow(label: "Duration", values: runs.map { $0.duration })
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ParameterRow: View {
    let label: String
    let values: [String]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .frame(width: 100, alignment: .leading)
                    .foregroundColor(.secondary)

                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text(value)
                        .frame(maxWidth: .infinity)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()
        }
    }
}

// MARK: - Radar Comparison Chart

struct RadarComparisonChart: View {
    let runs: [TrainingRun]

    private let metrics = ["Accuracy", "F1", "Precision", "Recall", "Loss"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Multi-Metric Comparison")
                .font(.headline)

            if runs.isEmpty {
                ContentUnavailableView("No Runs", systemImage: "chart.pie")
            } else {
                GeometryReader { geometry in
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    let radius = min(geometry.size.width, geometry.size.height) / 2 - 60

                    ZStack {
                        // Draw grid circles
                        ForEach(1...5, id: \.self) { level in
                            let r = radius * CGFloat(level) / 5
                            RadarGridShape(sides: metrics.count, radius: r)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                .position(center)
                        }

                        // Draw axes
                        ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                            let angle = angleFor(index: index, total: metrics.count)
                            let labelPoint = pointOnCircle(center: center, radius: radius + 30, angle: angle)
                            let axisEnd = pointOnCircle(center: center, radius: radius, angle: angle)

                            Path { path in
                                path.move(to: center)
                                path.addLine(to: axisEnd)
                            }
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

                            Text(metric)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .position(labelPoint)
                        }

                        // Draw run polygons
                        ForEach(Array(runs.enumerated()), id: \.offset) { runIndex, run in
                            let color = colorFor(index: runIndex, total: runs.count)
                            let values = normalizedValues(for: run)

                            RadarPolygonShape(values: values, center: center, radius: radius)
                                .fill(color.opacity(0.15))

                            RadarPolygonShape(values: values, center: center, radius: radius)
                                .stroke(color, lineWidth: 2)

                            // Draw points
                            ForEach(Array(values.enumerated()), id: \.offset) { valueIndex, value in
                                let angle = angleFor(index: valueIndex, total: values.count)
                                let point = pointOnCircle(center: center, radius: radius * value, angle: angle)

                                Circle()
                                    .fill(color)
                                    .frame(width: 8, height: 8)
                                    .position(point)
                            }
                        }
                    }
                }
                .frame(minHeight: 350)

                // Legend
                HStack(spacing: 16) {
                    ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(colorFor(index: index, total: runs.count))
                                .frame(width: 10, height: 10)
                            Text(run.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func angleFor(index: Int, total: Int) -> Double {
        -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(total)
    }

    private func pointOnCircle(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }

    private func colorFor(index: Int, total: Int) -> Color {
        let hue = Double(index) / Double(max(total, 1))
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }

    private func normalizedValues(for run: TrainingRun) -> [Double] {
        return [
            run.accuracy ?? 0,  // Already 0-1
            run.f1Score ?? 0,   // Already 0-1
            run.precision ?? 0, // Already 0-1
            run.recall ?? 0,    // Already 0-1
            1 - min(1, (run.loss ?? 0) / 2)  // Invert loss so higher is better
        ]
    }
}

struct RadarGridShape: Shape {
    let sides: Int
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)

        for i in 0..<sides {
            let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(sides)
            let point = CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )

            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct RadarPolygonShape: Shape {
    let values: [Double]
    let center: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for (index, value) in values.enumerated() {
            let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(values.count)
            let r = radius * CGFloat(value)
            let point = CGPoint(
                x: center.x + r * CGFloat(cos(angle)),
                y: center.y + r * CGFloat(sin(angle))
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Parallel Coordinates Chart

struct ParallelCoordinatesChart: View {
    let runs: [TrainingRun]

    private let parameters: [(name: String, getValue: (TrainingRun) -> Double)] = [
        ("Accuracy", { $0.accuracy ?? 0 }),
        ("Precision", { $0.precision ?? 0 }),
        ("Recall", { $0.recall ?? 0 }),
        ("F1", { $0.f1Score ?? 0 }),
        ("Loss", { 1 - min(1, ($0.loss ?? 0) / 2.0) })  // Inverted so higher is better
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Parallel Coordinates")
                .font(.headline)

            if runs.isEmpty {
                ContentUnavailableView("No Runs", systemImage: "chart.bar.xaxis")
            } else {
                GeometryReader { geometry in
                    let width = geometry.size.width - 40
                    let height = geometry.size.height - 60
                    let axisSpacing = width / CGFloat(parameters.count - 1)

                    ZStack {
                        // Draw axes
                        ForEach(Array(parameters.enumerated()), id: \.offset) { index, param in
                            let x = 20 + CGFloat(index) * axisSpacing

                            // Axis line
                            Path { path in
                                path.move(to: CGPoint(x: x, y: 20))
                                path.addLine(to: CGPoint(x: x, y: height + 20))
                            }
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)

                            // Axis label
                            Text(param.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .position(x: x, y: height + 45)

                            // Scale labels
                            Text("1")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .position(x: x - 15, y: 20)

                            Text("0")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .position(x: x - 15, y: height + 20)
                        }

                        // Draw run lines
                        ForEach(Array(runs.enumerated()), id: \.offset) { runIndex, run in
                            let color = colorFor(index: runIndex, total: runs.count)

                            Path { path in
                                for (paramIndex, param) in parameters.enumerated() {
                                    let x = 20 + CGFloat(paramIndex) * axisSpacing
                                    let normalizedValue = min(1, max(0, param.getValue(run)))
                                    let y = 20 + height * (1 - CGFloat(normalizedValue))

                                    if paramIndex == 0 {
                                        path.move(to: CGPoint(x: x, y: y))
                                    } else {
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                            }
                            .stroke(color, lineWidth: 2)

                            // Draw points at each axis
                            ForEach(Array(parameters.enumerated()), id: \.offset) { paramIndex, param in
                                let x = 20 + CGFloat(paramIndex) * axisSpacing
                                let normalizedValue = min(1, max(0, param.getValue(run)))
                                let y = 20 + height * (1 - CGFloat(normalizedValue))

                                Circle()
                                    .fill(color)
                                    .frame(width: 8, height: 8)
                                    .position(x: x, y: y)
                            }
                        }
                    }
                }
                .frame(minHeight: 350)

                // Legend
                HStack(spacing: 16) {
                    ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorFor(index: index, total: runs.count))
                                .frame(width: 16, height: 3)
                            Text(run.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func colorFor(index: Int, total: Int) -> Color {
        let hue = Double(index) / Double(max(total, 1))
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }
}

// MARK: - Metrics Dashboard View

struct MetricsDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedRuns: [TrainingRun] = []
    @State private var timeRange: TimeRange = .all

    enum TimeRange: String, CaseIterable {
        case day = "24h"
        case week = "7d"
        case month = "30d"
        case all = "All"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary Cards
                HStack(spacing: 16) {
                    MetricSummaryCard(
                        title: "Total Runs",
                        value: "\(appState.runs.count)",
                        icon: "play.circle",
                        color: .blue
                    )

                    MetricSummaryCard(
                        title: "Completed",
                        value: "\(appState.completedRuns.count)",
                        icon: "checkmark.circle",
                        color: .green
                    )

                    MetricSummaryCard(
                        title: "Best Accuracy",
                        value: bestAccuracyString,
                        icon: "chart.line.uptrend.xyaxis",
                        color: .purple
                    )

                    MetricSummaryCard(
                        title: "Avg Duration",
                        value: averageDurationString,
                        icon: "clock",
                        color: .orange
                    )
                }
                .padding(.horizontal)

                // Time filter
                HStack {
                    Text("Time Range:")
                        .foregroundColor(.secondary)

                    Picker("", selection: $timeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)

                    Spacer()
                }
                .padding(.horizontal)

                // Charts
                HStack(spacing: 20) {
                    // Loss over time chart
                    ChartCard(title: "Loss Over Time") {
                        LossTimelineChart(runs: filteredRuns)
                    }

                    // Accuracy distribution chart
                    ChartCard(title: "Accuracy Distribution") {
                        AccuracyDistributionChart(runs: filteredRuns)
                    }
                }
                .padding(.horizontal)

                // Runs per day chart
                ChartCard(title: "Training Activity") {
                    TrainingActivityChart(runs: filteredRuns)
                }
                .padding(.horizontal)

                // Recent runs table
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Runs")
                        .font(.headline)
                        .padding(.horizontal)

                    RecentRunsTable(runs: Array(filteredRuns.prefix(10)))
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Metrics Dashboard")
    }

    var filteredRuns: [TrainingRun] {
        let now = Date()
        let cutoff: Date

        switch timeRange {
        case .day:
            cutoff = now.addingTimeInterval(-24 * 60 * 60)
        case .week:
            cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .month:
            cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        case .all:
            return appState.runs
        }

        return appState.runs.filter { $0.startedAt >= cutoff }
    }

    var bestAccuracyString: String {
        let best = appState.completedRuns.compactMap { $0.accuracy }.max()
        return best.map { String(format: "%.1f%%", $0 * 100) } ?? "—"
    }

    var averageDurationString: String {
        let completed = appState.completedRuns.compactMap { $0.finishedAt }
        guard !completed.isEmpty else { return "—" }

        let durations = zip(appState.completedRuns, completed).map { run, end in
            end.timeIntervalSince(run.startedAt)
        }
        let avg = durations.reduce(0, +) / Double(durations.count)

        return formatDuration(avg)
    }
}

// MARK: - Metric Summary Card

struct MetricSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Chart Card

struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
                .frame(minHeight: 200)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Loss Timeline Chart

struct LossTimelineChart: View {
    let runs: [TrainingRun]

    var body: some View {
        if runs.isEmpty {
            ContentUnavailableView("No Data", systemImage: "chart.line.downtrend.xyaxis")
        } else {
            Chart {
                ForEach(runs.filter { $0.status == .completed }) { run in
                    if let loss = run.loss {
                        PointMark(
                            x: .value("Date", run.startedAt),
                            y: .value("Loss", loss)
                        )
                        .foregroundStyle(by: .value("Model", run.modelName))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
        }
    }
}

// MARK: - Accuracy Distribution Chart

struct AccuracyDistributionChart: View {
    let runs: [TrainingRun]

    var accuracyBuckets: [(String, Int)] {
        var buckets: [String: Int] = [
            "0-50%": 0,
            "50-70%": 0,
            "70-85%": 0,
            "85-95%": 0,
            "95-100%": 0
        ]

        for run in runs {
            guard let acc = run.accuracy else { continue }
            let bucket: String
            switch acc {
            case 0..<0.5: bucket = "0-50%"
            case 0.5..<0.7: bucket = "50-70%"
            case 0.7..<0.85: bucket = "70-85%"
            case 0.85..<0.95: bucket = "85-95%"
            default: bucket = "95-100%"
            }
            buckets[bucket, default: 0] += 1
        }

        return [
            ("0-50%", buckets["0-50%"]!),
            ("50-70%", buckets["50-70%"]!),
            ("70-85%", buckets["70-85%"]!),
            ("85-95%", buckets["85-95%"]!),
            ("95-100%", buckets["95-100%"]!)
        ]
    }

    var body: some View {
        Chart(accuracyBuckets, id: \.0) { bucket in
            BarMark(
                x: .value("Accuracy", bucket.0),
                y: .value("Count", bucket.1)
            )
            .foregroundStyle(Color.blue.gradient)
        }
    }
}

// MARK: - Training Activity Chart

struct TrainingActivityChart: View {
    let runs: [TrainingRun]

    var dailyCounts: [(Date, Int)] {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]

        for run in runs {
            let day = calendar.startOfDay(for: run.startedAt)
            counts[day, default: 0] += 1
        }

        return counts.sorted { $0.key < $1.key }
    }

    var body: some View {
        Chart(dailyCounts, id: \.0) { item in
            BarMark(
                x: .value("Date", item.0, unit: .day),
                y: .value("Runs", item.1)
            )
            .foregroundStyle(Color.green.gradient)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
    }
}

// MARK: - Recent Runs Table

struct RecentRunsTable: View {
    let runs: [TrainingRun]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Name").frame(width: 150, alignment: .leading)
                Text("Model").frame(width: 100, alignment: .leading)
                Text("Status").frame(width: 80)
                Text("Accuracy").frame(width: 80)
                Text("Loss").frame(width: 80)
                Text("Duration").frame(width: 80)
                Spacer()
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ForEach(runs) { run in
                HStack {
                    Text(run.name)
                        .frame(width: 150, alignment: .leading)
                        .lineLimit(1)

                    Text(run.modelName)
                        .frame(width: 100, alignment: .leading)
                        .lineLimit(1)

                    StatusBadge(text: run.status.rawValue, color: run.status.color)
                        .frame(width: 80)

                    Text(run.accuracy.map { String(format: "%.1f%%", $0 * 100) } ?? "—")
                        .frame(width: 80)
                        .monospacedDigit()

                    Text(run.loss.map { String(format: "%.4f", $0) } ?? "—")
                        .frame(width: 80)
                        .monospacedDigit()

                    Text(run.duration)
                        .frame(width: 80)
                        .monospacedDigit()

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                Divider()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}
