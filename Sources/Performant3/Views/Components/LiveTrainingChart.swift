import SwiftUI
import Charts

// MARK: - Live Training Chart

struct LiveTrainingChart: View {
    let metrics: [MetricPoint]
    let isTraining: Bool
    @State private var selectedMetric: MetricPoint?
    @State private var chartType: ChartType = .line

    enum ChartType: String, CaseIterable {
        case line = "Line"
        case area = "Area"
    }

    var body: some View {
        VStack(spacing: 16) {
            // Chart header with controls
            HStack {
                Text("Training Progress")
                    .font(.headline)

                Spacer()

                if isTraining {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Live")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }

                Picker("", selection: $chartType) {
                    ForEach(ChartType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            if metrics.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Waiting for training data...")
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            } else {
                // Dual chart layout
                HStack(spacing: 16) {
                    // Loss chart
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("Loss")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            if let last = metrics.last {
                                Text(String(format: "%.4f", last.loss))
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.red)
                            }
                        }

                        Chart(metrics) { point in
                            if chartType == .area {
                                AreaMark(
                                    x: .value("Epoch", point.epoch),
                                    y: .value("Loss", point.loss)
                                )
                                .foregroundStyle(.red.opacity(0.3))
                            }

                            LineMark(
                                x: .value("Epoch", point.epoch),
                                y: .value("Loss", point.loss)
                            )
                            .foregroundStyle(.red)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)

                            if metrics.count < 50 {
                                PointMark(
                                    x: .value("Epoch", point.epoch),
                                    y: .value("Loss", point.loss)
                                )
                                .foregroundStyle(.red)
                                .symbolSize(30)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 5))
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .chartXAxisLabel("Epoch", alignment: .center)
                        .frame(height: 180)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    // Accuracy chart
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text("Accuracy")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            if let last = metrics.last {
                                Text(String(format: "%.1f%%", last.accuracy * 100))
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                        }

                        Chart(metrics) { point in
                            if chartType == .area {
                                AreaMark(
                                    x: .value("Epoch", point.epoch),
                                    y: .value("Accuracy", point.accuracy * 100)
                                )
                                .foregroundStyle(.green.opacity(0.3))
                            }

                            LineMark(
                                x: .value("Epoch", point.epoch),
                                y: .value("Accuracy", point.accuracy * 100)
                            )
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)

                            if metrics.count < 50 {
                                PointMark(
                                    x: .value("Epoch", point.epoch),
                                    y: .value("Accuracy", point.accuracy * 100)
                                )
                                .foregroundStyle(.green)
                                .symbolSize(30)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 5))
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .chartYScale(domain: 0...100)
                        .chartXAxisLabel("Epoch", alignment: .center)
                        .frame(height: 180)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
            }
        }
    }
}

// MARK: - Training Stats Bar

struct TrainingStatsBar: View {
    let run: TrainingRun

    var body: some View {
        HStack(spacing: 0) {
            StatBox(
                title: "Progress",
                value: "\(Int(run.progress * 100))%",
                icon: "chart.pie.fill",
                color: .blue
            )

            Divider().frame(height: 40)

            StatBox(
                title: "Epoch",
                value: "\(run.currentEpoch)/\(run.totalEpochs)",
                icon: "repeat",
                color: .purple
            )

            Divider().frame(height: 40)

            StatBox(
                title: "Loss",
                value: run.loss.map { String(format: "%.4f", $0) } ?? "—",
                icon: "arrow.down.right",
                color: .red
            )

            Divider().frame(height: 40)

            StatBox(
                title: "Accuracy",
                value: run.accuracy.map { String(format: "%.1f%%", $0 * 100) } ?? "—",
                icon: "target",
                color: .green
            )

            Divider().frame(height: 40)

            StatBox(
                title: "Duration",
                value: run.duration,
                icon: "clock.fill",
                color: .orange
            )

            Divider().frame(height: 40)

            StatBox(
                title: "ETA",
                value: calculateETA(run),
                icon: "hourglass",
                color: .cyan
            )
        }
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func calculateETA(_ run: TrainingRun) -> String {
        guard run.status == .running,
              run.currentEpoch > 0,
              run.progress > 0 else { return "—" }

        let elapsed = Date().timeIntervalSince(run.startedAt)
        let estimatedTotal = elapsed / run.progress
        let remaining = estimatedTotal - elapsed

        if remaining < 60 {
            return "\(Int(remaining))s"
        } else if remaining < 3600 {
            return "\(Int(remaining / 60))m"
        } else {
            return String(format: "%.1fh", remaining / 3600)
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.headline, design: .monospaced))
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - GPU Monitor

struct GPUMonitorView: View {
    @StateObject private var monitor = GPUMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu.fill")
                    .foregroundColor(.purple)
                Text("System Resources")
                    .font(.headline)
                Spacer()
                Button(action: { monitor.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 16) {
                // GPU Usage
                ResourceGauge(
                    title: "GPU",
                    value: monitor.gpuUsage,
                    maxValue: 100,
                    unit: "%",
                    color: .purple
                )

                // Memory
                ResourceGauge(
                    title: "Memory",
                    value: Double(monitor.memoryUsed) / 1_000_000_000,
                    maxValue: Double(monitor.memoryTotal) / 1_000_000_000,
                    unit: "GB",
                    color: .blue
                )

                // Neural Engine
                VStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.title2)
                        .foregroundColor(monitor.neuralEngineActive ? .green : .gray)
                    Text("ANE")
                        .font(.caption)
                    Text(monitor.neuralEngineActive ? "Active" : "Idle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct ResourceGauge: View {
    let title: String
    let value: Double
    let maxValue: Double
    let unit: String
    let color: Color

    var percentage: Double {
        guard maxValue > 0 else { return 0 }
        return min(value / maxValue, 1.0)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: percentage)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: percentage)

                VStack(spacing: 0) {
                    Text(String(format: "%.1f", value))
                        .font(.system(.headline, design: .rounded))
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 70, height: 70)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - GPU Monitor Model

@MainActor
class GPUMonitor: ObservableObject {
    @Published var gpuUsage: Double = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = 0
    @Published var neuralEngineActive: Bool = false

    private var timer: Timer?

    init() {
        refresh()
        startMonitoring()
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        // Get memory info
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            memoryUsed = info.resident_size
        }

        // Get total system memory
        memoryTotal = ProcessInfo.processInfo.physicalMemory

        // Simulate GPU usage (in real app, would use Metal Performance Shaders to query)
        // For now, estimate based on memory pressure
        let memoryPressure = Double(memoryUsed) / Double(memoryTotal)
        gpuUsage = min(memoryPressure * 100 * 1.5, 100)

        // Check if Neural Engine might be active (heuristic)
        neuralEngineActive = gpuUsage > 30
    }

    deinit {
        timer?.invalidate()
    }
}
