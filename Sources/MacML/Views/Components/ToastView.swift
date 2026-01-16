import SwiftUI

// MARK: - Toast Type

enum ToastType {
    case success
    case error
    case warning
    case info
    case loading

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .loading: return "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .loading: return .secondary
        }
    }
}

// MARK: - Toast Item

struct ToastItem: Identifiable, Equatable {
    let id: UUID
    let message: String
    let type: ToastType
    let duration: Double
    let action: ToastAction?

    init(
        id: UUID = UUID(),
        message: String,
        type: ToastType = .success,
        duration: Double = 3.0,
        action: ToastAction? = nil
    ) {
        self.id = id
        self.message = message
        self.type = type
        self.duration = duration
        self.action = action
    }

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct ToastAction {
    let label: String
    let handler: () -> Void
}

// MARK: - Toast View

struct ToastView: View {
    let toast: ToastItem
    let onDismiss: () -> Void

    @State private var offset: CGFloat = -100
    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Group {
                if toast.type == .loading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: toast.type.icon)
                        .font(.title3)
                        .foregroundColor(toast.type.color)
                }
            }

            // Message
            Text(toast.message)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            // Action button
            if let action = toast.action {
                Spacer()

                Button(action.label) {
                    action.handler()
                    onDismiss()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(toast.type.color)
            }

            // Close button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(toast.type.color.opacity(0.3), lineWidth: 1)
        )
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                offset = 0
                opacity = 1
            }
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.3)) {
            offset = -100
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            completion()
        }
    }
}

// MARK: - Toast Manager

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var toasts: [ToastItem] = []

    private init() {}

    // MARK: - Show Methods

    func show(
        _ message: String,
        type: ToastType = .success,
        duration: Double = 3.0,
        action: ToastAction? = nil
    ) {
        let toast = ToastItem(
            message: message,
            type: type,
            duration: duration,
            action: action
        )

        toasts.append(toast)

        // Auto-dismiss if not loading type
        if type != .loading && duration > 0 {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                dismiss(toast.id)
            }
        }
    }

    func success(_ message: String, duration: Double = 3.0) {
        show(message, type: .success, duration: duration)
    }

    func error(_ message: String, duration: Double = 5.0) {
        show(message, type: .error, duration: duration)
    }

    func warning(_ message: String, duration: Double = 4.0) {
        show(message, type: .warning, duration: duration)
    }

    func info(_ message: String, duration: Double = 3.0) {
        show(message, type: .info, duration: duration)
    }

    func loading(_ message: String) -> UUID {
        let toast = ToastItem(
            message: message,
            type: .loading,
            duration: 0
        )
        toasts.append(toast)
        return toast.id
    }

    // MARK: - Dismiss Methods

    func dismiss(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.3)) {
            toasts.removeAll { $0.id == id }
        }
    }

    func dismissAll() {
        withAnimation(.easeOut(duration: 0.3)) {
            toasts.removeAll()
        }
    }

    // MARK: - Update Methods

    func update(_ id: UUID, message: String? = nil, type: ToastType? = nil) {
        if let index = toasts.firstIndex(where: { $0.id == id }) {
            let current = toasts[index]
            toasts[index] = ToastItem(
                id: id,
                message: message ?? current.message,
                type: type ?? current.type,
                duration: current.duration,
                action: current.action
            )
        }
    }

    /// Complete a loading toast with success or error
    func complete(_ id: UUID, success: Bool, message: String? = nil) {
        if let index = toasts.firstIndex(where: { $0.id == id }) {
            let newType: ToastType = success ? .success : .error
            let newMessage = message ?? (success ? "Completed" : "Failed")

            toasts[index] = ToastItem(
                id: id,
                message: newMessage,
                type: newType,
                duration: 3.0
            )

            // Auto-dismiss after delay
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                dismiss(id)
            }
        }
    }
}

// MARK: - Toast Container View

struct ToastContainerView: View {
    @ObservedObject var toastManager: ToastManager

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toastManager.toasts) { toast in
                ToastView(toast: toast) {
                    toastManager.dismiss(toast.id)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastManager.toasts)
    }
}

// MARK: - View Extension

extension View {
    /// Adds toast overlay to the view
    func toastOverlay() -> some View {
        overlay(alignment: .top) {
            ToastContainerView(toastManager: ToastManager.shared)
                .padding(.top, 8)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ToastView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ToastView(
                toast: ToastItem(message: "Model saved successfully", type: .success),
                onDismiss: {}
            )

            ToastView(
                toast: ToastItem(message: "Training failed: Out of memory", type: .error),
                onDismiss: {}
            )

            ToastView(
                toast: ToastItem(
                    message: "Run deleted",
                    type: .warning,
                    action: ToastAction(label: "Undo") { print("Undo") }
                ),
                onDismiss: {}
            )

            ToastView(
                toast: ToastItem(message: "Processing data...", type: .loading),
                onDismiss: {}
            )
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
#endif
