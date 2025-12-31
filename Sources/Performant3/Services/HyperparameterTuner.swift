import Foundation
import Combine

// MARK: - Hyperparameter Types

/// Defines a hyperparameter and its search space
struct HyperparameterSpec: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: ParameterType
    let scale: ParameterScale

    enum ParameterType: String, Codable, Hashable {
        case continuous
        case discrete
        case categorical
    }

    enum ParameterScale: String, Codable, Hashable {
        case linear
        case log
    }

    // For continuous/discrete
    var minValue: Double?
    var maxValue: Double?
    var stepSize: Double?

    // For categorical
    var categories: [String]?

    init(
        id: String = UUID().uuidString,
        name: String,
        minValue: Double,
        maxValue: Double,
        scale: ParameterScale = .linear,
        stepSize: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.type = stepSize != nil ? .discrete : .continuous
        self.scale = scale
        self.minValue = minValue
        self.maxValue = maxValue
        self.stepSize = stepSize
        self.categories = nil
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        categories: [String]
    ) {
        self.id = id
        self.name = name
        self.type = .categorical
        self.scale = .linear
        self.minValue = nil
        self.maxValue = nil
        self.stepSize = nil
        self.categories = categories
    }

    /// Sample a value from this parameter's space
    func sample() -> ParameterValue {
        switch type {
        case .continuous:
            guard let min = minValue, let max = maxValue else {
                return .double(0)
            }
            let value: Double
            switch scale {
            case .linear:
                value = Double.random(in: min...max)
            case .log:
                let logMin = log(min)
                let logMax = log(max)
                value = exp(Double.random(in: logMin...logMax))
            }
            return .double(value)

        case .discrete:
            guard let min = minValue, let max = maxValue else {
                return .int(0)
            }
            let step = stepSize ?? 1.0
            let steps = Int((max - min) / step)
            let randomStep = Int.random(in: 0...steps)
            return .int(Int(min) + randomStep * Int(step))

        case .categorical:
            guard let cats = categories, !cats.isEmpty else {
                return .string("")
            }
            return .string(cats.randomElement()!)
        }
    }

    /// Get all discrete values for grid search
    func gridValues() -> [ParameterValue] {
        switch type {
        case .continuous:
            guard let min = minValue, let max = maxValue else { return [] }
            let step = stepSize ?? (max - min) / 10
            var values: [ParameterValue] = []
            var current = min
            while current <= max {
                values.append(.double(current))
                current += step
            }
            return values

        case .discrete:
            guard let min = minValue, let max = maxValue else { return [] }
            let step = stepSize ?? 1.0
            var values: [ParameterValue] = []
            var current = min
            while current <= max {
                values.append(.int(Int(current)))
                current += step
            }
            return values

        case .categorical:
            return (categories ?? []).map { .string($0) }
        }
    }
}

/// A parameter value that can be different types
enum ParameterValue: Codable, Hashable, CustomStringConvertible {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)

    var description: String {
        switch self {
        case .int(let v): return "\(v)"
        case .double(let v): return String(format: "%.4g", v)
        case .string(let v): return v
        case .bool(let v): return v ? "true" : "false"
        }
    }

    var doubleValue: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .double(let v): return v
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(v)
        default: return nil
        }
    }
}

// MARK: - Trial

/// Represents a single hyperparameter tuning trial
struct HyperparameterTrial: Identifiable, Codable {
    let id: String
    let studyId: String
    let trialNumber: Int
    let parameters: [String: ParameterValue]
    var status: TrialStatus
    var score: Double?
    var metrics: [String: Double]
    var startTime: Date?
    var endTime: Date?
    var trainingRunId: String?
    var error: String?

    enum TrialStatus: String, Codable {
        case pending
        case running
        case completed
        case failed
        case pruned
    }

    var duration: TimeInterval? {
        guard let start = startTime else { return nil }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }

    init(
        id: String = UUID().uuidString,
        studyId: String,
        trialNumber: Int,
        parameters: [String: ParameterValue]
    ) {
        self.id = id
        self.studyId = studyId
        self.trialNumber = trialNumber
        self.parameters = parameters
        self.status = .pending
        self.score = nil
        self.metrics = [:]
        self.startTime = nil
        self.endTime = nil
        self.trainingRunId = nil
        self.error = nil
    }
}

// MARK: - Study Configuration

/// Configuration for a hyperparameter tuning study
struct TuningStudyConfig: Codable {
    let name: String
    let modelId: String
    let objective: Objective
    let searchStrategy: SearchStrategy
    let parameters: [HyperparameterSpec]
    let maxTrials: Int
    let parallelTrials: Int
    let earlyStoppingPatience: Int?
    let earlyStoppingMinDelta: Double?
    let pruningEnabled: Bool
    let baseConfig: TrainingConfig

    enum Objective: String, Codable {
        case minimizeLoss = "minimize_loss"
        case maximizeAccuracy = "maximize_accuracy"
        case minimizeValidationLoss = "minimize_val_loss"
        case maximizeF1 = "maximize_f1"

        var isMaximize: Bool {
            switch self {
            case .maximizeAccuracy, .maximizeF1: return true
            case .minimizeLoss, .minimizeValidationLoss: return false
            }
        }

        var metricName: String {
            switch self {
            case .minimizeLoss: return "loss"
            case .maximizeAccuracy: return "accuracy"
            case .minimizeValidationLoss: return "val_loss"
            case .maximizeF1: return "f1"
            }
        }
    }

    enum SearchStrategy: String, Codable, CaseIterable {
        case grid = "Grid Search"
        case random = "Random Search"
        case bayesian = "Bayesian Optimization"
        case hyperband = "Hyperband"

        var description: String {
            switch self {
            case .grid:
                return "Exhaustively tries all combinations. Best for small search spaces."
            case .random:
                return "Randomly samples parameters. Efficient for large spaces."
            case .bayesian:
                return "Uses probabilistic model to guide search. Most efficient for expensive evaluations."
            case .hyperband:
                return "Dynamically allocates resources. Fast at finding good configurations."
            }
        }
    }
}

// MARK: - Tuning Study

/// Represents a hyperparameter tuning study
struct TuningStudy: Identifiable, Codable {
    let id: String
    let config: TuningStudyConfig
    var trials: [HyperparameterTrial]
    var status: StudyStatus
    var bestTrialId: String?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?

    enum StudyStatus: String, Codable {
        case created
        case running
        case paused
        case completed
        case failed
    }

    var completedTrials: [HyperparameterTrial] {
        trials.filter { $0.status == .completed }
    }

    var bestTrial: HyperparameterTrial? {
        guard let bestId = bestTrialId else { return nil }
        return trials.first { $0.id == bestId }
    }

    var progress: Double {
        guard config.maxTrials > 0 else { return 0 }
        return Double(completedTrials.count) / Double(config.maxTrials)
    }

    init(config: TuningStudyConfig) {
        self.id = UUID().uuidString
        self.config = config
        self.trials = []
        self.status = .created
        self.bestTrialId = nil
        self.createdAt = Date()
        self.startedAt = nil
        self.completedAt = nil
    }
}

// MARK: - Hyperparameter Tuner

/// Main service for hyperparameter tuning
@MainActor
class HyperparameterTuner: ObservableObject {
    static let shared = HyperparameterTuner()

    @Published var studies: [TuningStudy] = []
    @Published var activeStudyId: String?

    private var studyTasks: [String: Task<Void, Never>] = [:]
    private var cancellationTokens: [String: Bool] = [:]

    // Bayesian optimization state
    private var bayesianObservations: [String: [(parameters: [Double], score: Double)]] = [:]

    private init() {
        Task { await loadStudies() }
    }

    // MARK: - Study Management

    /// Create a new tuning study
    func createStudy(config: TuningStudyConfig) -> TuningStudy {
        let study = TuningStudy(config: config)
        studies.append(study)
        Task { await saveStudies() }
        return study
    }

    /// Start a tuning study
    func startStudy(_ studyId: String) {
        guard let index = studies.firstIndex(where: { $0.id == studyId }) else { return }

        studies[index].status = .running
        studies[index].startedAt = Date()
        activeStudyId = studyId
        cancellationTokens[studyId] = false

        let task = Task {
            await runStudy(studyId)
        }
        studyTasks[studyId] = task
    }

    /// Pause a running study
    func pauseStudy(_ studyId: String) {
        cancellationTokens[studyId] = true
        studyTasks[studyId]?.cancel()

        if let index = studies.firstIndex(where: { $0.id == studyId }) {
            studies[index].status = .paused
        }

        if activeStudyId == studyId {
            activeStudyId = nil
        }
    }

    /// Resume a paused study
    func resumeStudy(_ studyId: String) {
        guard let index = studies.firstIndex(where: { $0.id == studyId }),
              studies[index].status == .paused else { return }

        startStudy(studyId)
    }

    /// Delete a study
    func deleteStudy(_ studyId: String) {
        pauseStudy(studyId)
        studies.removeAll { $0.id == studyId }
        bayesianObservations.removeValue(forKey: studyId)
        Task { await saveStudies() }
    }

    // MARK: - Study Execution

    private func runStudy(_ studyId: String) async {
        guard let study = studies.first(where: { $0.id == studyId }) else { return }

        let config = study.config
        var trialNumber = study.trials.count

        while trialNumber < config.maxTrials {
            // Check for cancellation
            if cancellationTokens[studyId] == true {
                break
            }

            // Generate next trial parameters
            let parameters = await suggestParameters(for: studyId)

            // Create and run trial
            var trial = HyperparameterTrial(
                studyId: studyId,
                trialNumber: trialNumber,
                parameters: parameters
            )

            // Add trial to study
            if let index = studies.firstIndex(where: { $0.id == studyId }) {
                studies[index].trials.append(trial)
            }

            // Run the trial
            trial = await runTrial(trial, config: config)

            // Update trial in study
            if let studyIndex = studies.firstIndex(where: { $0.id == studyId }),
               let trialIndex = studies[studyIndex].trials.firstIndex(where: { $0.id == trial.id }) {
                studies[studyIndex].trials[trialIndex] = trial

                // Update best trial if needed
                if trial.status == .completed, let score = trial.score {
                    updateBestTrial(studyId: studyId, trial: trial, score: score)
                }
            }

            // Save progress
            await saveStudies()

            trialNumber += 1
        }

        // Mark study as completed
        if let index = studies.firstIndex(where: { $0.id == studyId }) {
            if cancellationTokens[studyId] != true {
                studies[index].status = .completed
                studies[index].completedAt = Date()
            }
        }

        if activeStudyId == studyId {
            activeStudyId = nil
        }

        await saveStudies()
    }

    private func runTrial(_ trial: HyperparameterTrial, config: TuningStudyConfig) async -> HyperparameterTrial {
        var trial = trial
        trial.status = .running
        trial.startTime = Date()

        // Build training config from trial parameters
        var trainingConfig = config.baseConfig

        // Apply hyperparameters
        for (paramName, value) in trial.parameters {
            switch paramName {
            case "learningRate":
                if let v = value.doubleValue {
                    trainingConfig.learningRate = v
                }
            case "batchSize":
                if let v = value.intValue {
                    trainingConfig.batchSize = v
                }
            case "epochs":
                if let v = value.intValue {
                    trainingConfig.epochs = v
                }
            case "optimizer":
                if case .string(let v) = value {
                    if let opt = Optimizer(rawValue: v) {
                        trainingConfig.optimizer = opt
                    }
                }
            case "validationSplit":
                if let v = value.doubleValue {
                    trainingConfig.validationSplit = v
                }
            case "patience":
                if let v = value.intValue {
                    trainingConfig.patience = v
                }
            default:
                break
            }
        }

        // Run training (simplified - in real impl would use TrainingService)
        do {
            // Simulate training for demo purposes
            // In production, this would call the actual training service
            try await Task.sleep(for: .seconds(2))

            // Simulate results based on parameters
            let score = simulateTrainingScore(parameters: trial.parameters, objective: config.objective)

            trial.status = .completed
            trial.score = score
            trial.metrics = [
                config.objective.metricName: score,
                "epochs_completed": Double(trainingConfig.epochs)
            ]
            trial.endTime = Date()

            // Update Bayesian observations
            if config.searchStrategy == .bayesian {
                await updateBayesianObservations(studyId: trial.studyId, trial: trial)
            }

        } catch {
            trial.status = .failed
            trial.error = error.localizedDescription
            trial.endTime = Date()
        }

        return trial
    }

    /// Simulate a training score for testing
    private func simulateTrainingScore(parameters: [String: ParameterValue], objective: TuningStudyConfig.Objective) -> Double {
        // This simulates how different hyperparameters affect the objective
        // In production, this would be replaced by actual training results

        var score = 0.7 // Base score

        if let lr = parameters["learningRate"]?.doubleValue {
            // Optimal learning rate around 0.001
            let lrScore = 1.0 - abs(log10(lr) - log10(0.001)) / 3.0
            score += lrScore * 0.1
        }

        if let bs = parameters["batchSize"]?.intValue {
            // Moderate batch sizes work better
            let bsScore = 1.0 - abs(Double(bs) - 32.0) / 100.0
            score += bsScore * 0.05
        }

        if let wd = parameters["weightDecay"]?.doubleValue {
            // Small weight decay is good
            let wdScore = 1.0 - wd * 10.0
            score += wdScore * 0.03
        }

        // Add some noise
        score += Double.random(in: -0.05...0.05)

        // Clamp to valid range
        score = min(max(score, 0.0), 1.0)

        // For loss objectives, invert
        if !objective.isMaximize {
            score = 1.0 - score
        }

        return score
    }

    // MARK: - Parameter Suggestion

    private func suggestParameters(for studyId: String) async -> [String: ParameterValue] {
        guard let study = studies.first(where: { $0.id == studyId }) else {
            return [:]
        }

        switch study.config.searchStrategy {
        case .grid:
            return suggestGridParameters(study: study)
        case .random:
            return suggestRandomParameters(study: study)
        case .bayesian:
            return await suggestBayesianParameters(study: study)
        case .hyperband:
            return suggestRandomParameters(study: study) // Simplified
        }
    }

    private func suggestGridParameters(study: TuningStudy) -> [String: ParameterValue] {
        // Generate all grid combinations
        let gridValues = study.config.parameters.map { $0.gridValues() }
        let combinations = cartesianProduct(gridValues)

        // Find first untried combination
        let triedCombinations = Set(study.trials.map { trial in
            study.config.parameters.map { param in trial.parameters[param.name] }
        })

        for combo in combinations {
            let paramValues = study.config.parameters.map { $0.name }
            let comboDict = Dictionary(uniqueKeysWithValues: zip(paramValues, combo))

            let comboArray = study.config.parameters.map { comboDict[$0.name] }
            if !triedCombinations.contains(comboArray) {
                return comboDict.compactMapValues { $0 }
            }
        }

        // All combinations tried, return random
        return suggestRandomParameters(study: study)
    }

    private func suggestRandomParameters(study: TuningStudy) -> [String: ParameterValue] {
        var parameters: [String: ParameterValue] = [:]
        for param in study.config.parameters {
            parameters[param.name] = param.sample()
        }
        return parameters
    }

    private func suggestBayesianParameters(study: TuningStudy) async -> [String: ParameterValue] {
        let observations = bayesianObservations[study.id] ?? []

        // If not enough observations, use random
        if observations.count < 5 {
            return suggestRandomParameters(study: study)
        }

        // Simple acquisition function: Expected Improvement
        // Sample many random points and pick the best expected improvement
        var bestParams: [String: ParameterValue] = [:]
        var bestEI = -Double.infinity

        for _ in 0..<100 {
            let candidate = suggestRandomParameters(study: study)
            let ei = calculateExpectedImprovement(
                candidate: candidate,
                observations: observations,
                parameters: study.config.parameters,
                isMaximize: study.config.objective.isMaximize
            )

            if ei > bestEI {
                bestEI = ei
                bestParams = candidate
            }
        }

        return bestParams
    }

    private func calculateExpectedImprovement(
        candidate: [String: ParameterValue],
        observations: [(parameters: [Double], score: Double)],
        parameters: [HyperparameterSpec],
        isMaximize: Bool
    ) -> Double {
        // Convert candidate to numeric array
        let x = parameters.compactMap { param -> Double? in
            candidate[param.name]?.doubleValue
        }

        guard x.count == parameters.count else { return 0 }

        // Simple GP-like estimation using nearest neighbors
        let distances = observations.map { obs in
            zip(x, obs.parameters).reduce(0.0) { sum, pair in
                sum + pow(pair.0 - pair.1, 2)
            }
        }

        // Weighted average based on distance
        let weights = distances.map { 1.0 / (sqrt($0) + 0.01) }
        let totalWeight = weights.reduce(0, +)

        var predictedMean = 0.0
        var predictedVar = 0.0

        for (i, obs) in observations.enumerated() {
            let w = weights[i] / totalWeight
            predictedMean += w * obs.score
        }

        for (i, obs) in observations.enumerated() {
            let w = weights[i] / totalWeight
            predictedVar += w * pow(obs.score - predictedMean, 2)
        }
        predictedVar = sqrt(predictedVar + 0.01)

        // Calculate expected improvement
        let bestScore = isMaximize ? observations.map { $0.score }.max() ?? 0 : observations.map { $0.score }.min() ?? 1
        let improvement = isMaximize ? predictedMean - bestScore : bestScore - predictedMean
        let z = improvement / predictedVar

        // Simplified EI calculation
        return improvement * normalCDF(z) + predictedVar * normalPDF(z)
    }

    private func normalPDF(_ x: Double) -> Double {
        return exp(-0.5 * x * x) / sqrt(2 * .pi)
    }

    private func normalCDF(_ x: Double) -> Double {
        return 0.5 * (1 + erf(x / sqrt(2)))
    }

    private func updateBayesianObservations(studyId: String, trial: HyperparameterTrial) async {
        guard let study = studies.first(where: { $0.id == studyId }),
              let score = trial.score else { return }

        let x = study.config.parameters.compactMap { param -> Double? in
            trial.parameters[param.name]?.doubleValue
        }

        if x.count == study.config.parameters.count {
            var obs = bayesianObservations[studyId] ?? []
            obs.append((parameters: x, score: score))
            bayesianObservations[studyId] = obs
        }
    }

    // MARK: - Best Trial Update

    private func updateBestTrial(studyId: String, trial: HyperparameterTrial, score: Double) {
        guard let index = studies.firstIndex(where: { $0.id == studyId }) else { return }

        let isMaximize = studies[index].config.objective.isMaximize

        if let currentBestId = studies[index].bestTrialId,
           let currentBest = studies[index].trials.first(where: { $0.id == currentBestId }),
           let currentScore = currentBest.score {

            if isMaximize {
                if score > currentScore {
                    studies[index].bestTrialId = trial.id
                }
            } else {
                if score < currentScore {
                    studies[index].bestTrialId = trial.id
                }
            }
        } else {
            studies[index].bestTrialId = trial.id
        }
    }

    // MARK: - Helpers

    private func cartesianProduct(_ arrays: [[ParameterValue]]) -> [[ParameterValue]] {
        guard let first = arrays.first else { return [[]] }
        if arrays.count == 1 { return first.map { [$0] } }

        let rest = cartesianProduct(Array(arrays.dropFirst()))
        return first.flatMap { value in
            rest.map { [value] + $0 }
        }
    }

    // MARK: - Persistence

    private func loadStudies() async {
        let url = studiesURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            studies = try decoder.decode([TuningStudy].self, from: data)
        } catch {
            print("Failed to load tuning studies: \(error)")
        }
    }

    private func saveStudies() async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(studies)
            try data.write(to: studiesURL, options: .atomic)
        } catch {
            print("Failed to save tuning studies: \(error)")
        }
    }

    private var studiesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Performant3", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("tuning_studies.json")
    }
}

// MARK: - Predefined Parameter Sets

extension HyperparameterTuner {
    /// Common hyperparameter presets
    static let commonParameters: [HyperparameterSpec] = [
        HyperparameterSpec(
            name: "learningRate",
            minValue: 1e-5,
            maxValue: 1e-1,
            scale: .log
        ),
        HyperparameterSpec(
            name: "batchSize",
            minValue: 8,
            maxValue: 128,
            scale: .linear,
            stepSize: 8
        ),
        HyperparameterSpec(
            name: "epochs",
            minValue: 5,
            maxValue: 50,
            scale: .linear,
            stepSize: 5
        ),
        HyperparameterSpec(
            name: "validationSplit",
            minValue: 0.1,
            maxValue: 0.3,
            scale: .linear
        ),
        HyperparameterSpec(
            name: "patience",
            minValue: 2,
            maxValue: 10,
            scale: .linear,
            stepSize: 1
        ),
        HyperparameterSpec(
            name: "optimizer",
            categories: ["adam", "adamw", "sgd"]
        )
    ]
}
