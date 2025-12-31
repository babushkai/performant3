import Foundation
import SwiftUI

/// Centralized error handling and recovery service
@MainActor
class ErrorRecoveryService: ObservableObject {
    static let shared = ErrorRecoveryService()

    @Published var currentError: AppError?
    @Published var isShowingError = false
    @Published var recoveryInProgress = false

    // Error history for debugging
    private var errorHistory: [ErrorRecord] = []
    private let maxErrorHistory = 100

    struct ErrorRecord {
        let error: AppError
        let timestamp: Date
        let context: String
        let recovered: Bool
    }

    // MARK: - Error Handling

    func handle(_ error: Error, context: String, recoverable: Bool = true) {
        let appError = AppError(from: error, context: context, recoverable: recoverable)
        currentError = appError
        isShowingError = true

        // Log error
        errorHistory.append(ErrorRecord(
            error: appError,
            timestamp: Date(),
            context: context,
            recovered: false
        ))

        if errorHistory.count > maxErrorHistory {
            errorHistory.removeFirst()
        }

        // Log to system
        logError(appError)

        // Attempt auto-recovery for known issues
        if recoverable {
            Task {
                await attemptAutoRecovery(for: appError)
            }
        }
    }

    func dismiss() {
        currentError = nil
        isShowingError = false
    }

    // MARK: - Auto Recovery

    private func attemptAutoRecovery(for error: AppError) async {
        recoveryInProgress = true
        defer { recoveryInProgress = false }

        switch error.category {
        case .pythonEnvironment:
            await recoverPythonEnvironment()

        case .database:
            await recoverDatabase()

        case .training:
            // Training errors usually require user intervention
            break

        case .network:
            // Network errors might resolve themselves
            break

        case .fileSystem:
            await recoverFileSystem(error)

        case .unknown:
            break
        }
    }

    private func recoverPythonEnvironment() async {
        do {
            try await PythonEnvironmentManager.shared.ensureReady { progress in
                // Could emit progress notifications here
            }
            markRecovered()
        } catch {
            // Recovery failed
        }
    }

    private func recoverDatabase() async {
        do {
            try await DatabaseManager.shared.setup()
            markRecovered()
        } catch {
            // Recovery failed
        }
    }

    private func recoverFileSystem(_ error: AppError) async {
        // Attempt to create missing directories
        if let path = error.details["path"] {
            let url = URL(fileURLWithPath: path)
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func markRecovered() {
        if let index = errorHistory.indices.last {
            errorHistory[index] = ErrorRecord(
                error: errorHistory[index].error,
                timestamp: errorHistory[index].timestamp,
                context: errorHistory[index].context,
                recovered: true
            )
        }
        dismiss()
    }

    // MARK: - Logging

    private func logError(_ error: AppError) {
        #if DEBUG
        print("❌ [\(error.category.rawValue)] \(error.title): \(error.message)")
        if !error.details.isEmpty {
            print("   Details: \(error.details)")
        }
        if let suggestion = error.recoverySuggestion {
            print("   Suggestion: \(suggestion)")
        }
        #endif
    }

    // MARK: - Error Export

    func exportErrorLog() -> String {
        var log = "Performant3 Error Log\n"
        log += "Generated: \(Date())\n"
        log += "Total errors: \(errorHistory.count)\n\n"

        for record in errorHistory.reversed() {
            log += "---\n"
            log += "Time: \(record.timestamp)\n"
            log += "Context: \(record.context)\n"
            log += "Category: \(record.error.category.rawValue)\n"
            log += "Error: \(record.error.title)\n"
            log += "Message: \(record.error.message)\n"
            log += "Recovered: \(record.recovered)\n"
        }

        return log
    }

    func clearHistory() {
        errorHistory.removeAll()
    }
}

// MARK: - App Error Type

struct AppError: Identifiable, Error {
    let id = UUID()
    let category: Category
    let title: String
    let message: String
    let underlyingError: Error?
    let recoverySuggestion: String?
    let recoverable: Bool
    var details: [String: String] = [:]

    enum Category: String {
        case pythonEnvironment = "Python Environment"
        case database = "Database"
        case training = "Training"
        case network = "Network"
        case fileSystem = "File System"
        case unknown = "Unknown"
    }

    init(from error: Error, context: String, recoverable: Bool = true) {
        self.underlyingError = error
        self.recoverable = recoverable

        // Categorize error
        switch error {
        case is PythonEnvironmentError:
            self.category = .pythonEnvironment
            self.title = "Python Environment Error"
            self.message = error.localizedDescription
            self.recoverySuggestion = "The app will attempt to fix this automatically. If the problem persists, try reinstalling Python or contact support."

        case is DatabaseError:
            self.category = .database
            self.title = "Database Error"
            self.message = error.localizedDescription
            self.recoverySuggestion = "Try restarting the app. If the problem persists, the database may need to be reset."

        case is PythonExecutorError:
            self.category = .training
            self.title = "Training Error"
            self.message = error.localizedDescription
            self.recoverySuggestion = "Check the training logs for more details. You may need to adjust your training configuration."

        case let nsError as NSError where nsError.domain == NSURLErrorDomain:
            self.category = .network
            self.title = "Network Error"
            self.message = error.localizedDescription
            self.recoverySuggestion = "Check your internet connection and try again."

        case let nsError as NSError where nsError.domain == NSCocoaErrorDomain:
            if [NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileWriteNoPermissionError].contains(nsError.code) {
                self.category = .fileSystem
                self.title = "File System Error"
                self.message = error.localizedDescription
                self.recoverySuggestion = "Check that the file exists and you have permission to access it."
            } else {
                self.category = .unknown
                self.title = "Error"
                self.message = error.localizedDescription
                self.recoverySuggestion = nil
            }

        default:
            self.category = .unknown
            self.title = "Error"
            self.message = error.localizedDescription
            self.recoverySuggestion = "Please try again. If the problem persists, contact support."
        }
    }

    init(category: Category, title: String, message: String, recoverySuggestion: String? = nil, recoverable: Bool = true) {
        self.category = category
        self.title = title
        self.message = message
        self.underlyingError = nil
        self.recoverySuggestion = recoverySuggestion
        self.recoverable = recoverable
    }
}

// MARK: - Error Alert View

struct ErrorAlertView: View {
    @ObservedObject var errorService = ErrorRecoveryService.shared

    var body: some View {
        EmptyView()
            .alert(
                errorService.currentError?.title ?? "Error",
                isPresented: $errorService.isShowingError,
                presenting: errorService.currentError
            ) { error in
                Button("Dismiss") {
                    errorService.dismiss()
                }
                if error.recoverable {
                    Button("Retry") {
                        // Retry action would be passed in
                        errorService.dismiss()
                    }
                }
            } message: { error in
                VStack {
                    Text(error.message)
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
    }
}

// MARK: - Error Boundary View Modifier

struct ErrorBoundary: ViewModifier {
    @ObservedObject var errorService = ErrorRecoveryService.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                ErrorAlertView()
            }
    }
}

extension View {
    func withErrorHandling() -> some View {
        modifier(ErrorBoundary())
    }
}

// MARK: - Convenient Error Throwing

extension View {
    func handleError(_ error: Error, context: String) {
        ErrorRecoveryService.shared.handle(error, context: context)
    }
}
