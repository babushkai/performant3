import SwiftUI

// MARK: - Animated Transitions

extension AnyTransition {
    /// Slide in from trailing edge, slide out to leading edge with fade
    static var slideAndFade: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    /// Scale up with fade for insertion, scale down with fade for removal
    static var scaleAndFade: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        )
    }

    /// Pop in from center with bounce
    static var popIn: AnyTransition {
        .scale(scale: 0.5)
        .combined(with: .opacity)
    }

    /// Slide up from bottom with fade
    static var slideUp: AnyTransition {
        .move(edge: .bottom)
        .combined(with: .opacity)
    }
}

// MARK: - Pulse Animation for Active Status

struct PulseEffect: ViewModifier {
    @State private var isPulsing = false
    let isActive: Bool
    let intensity: CGFloat

    init(isActive: Bool, intensity: CGFloat = 1.05) {
        self.isActive = isActive
        self.intensity = intensity
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing && isActive ? intensity : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .onChange(of: isActive) { _, newValue in
                if !newValue { isPulsing = false }
            }
    }
}

extension View {
    /// Adds a pulsing scale effect when active
    func pulseEffect(when active: Bool, intensity: CGFloat = 1.05) -> some View {
        modifier(PulseEffect(isActive: active, intensity: intensity))
    }
}

// MARK: - Glow Effect for Active Items

struct GlowEffect: ViewModifier {
    @State private var isGlowing = false
    let isActive: Bool
    let color: Color

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isActive ? color.opacity(isGlowing ? 0.6 : 0.2) : .clear,
                radius: isGlowing ? 8 : 4
            )
            .animation(
                isActive ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .default,
                value: isGlowing
            )
            .onAppear { isGlowing = true }
    }
}

extension View {
    /// Adds a glowing shadow effect when active
    func glowEffect(when active: Bool, color: Color = .accentColor) -> some View {
        modifier(GlowEffect(isActive: active, color: color))
    }
}

// MARK: - Shimmer Loading Effect

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.4), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase * 300 - 150)
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Adds a shimmer loading effect
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

// MARK: - Animated Progress Ring

struct AnimatedProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let color: Color
    let backgroundColor: Color

    @State private var animatedProgress: Double = 0

    init(
        progress: Double,
        lineWidth: CGFloat = 8,
        color: Color = .accentColor,
        backgroundColor: Color? = nil
    ) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.color = color
        self.backgroundColor = backgroundColor ?? color.opacity(0.2)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(backgroundColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animatedProgress)
        }
        .onChange(of: progress) { _, newValue in
            animatedProgress = newValue
        }
        .onAppear {
            // Slight delay for entrance animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                animatedProgress = progress
            }
        }
    }
}

// MARK: - Animated Counter

struct AnimatedCounter: View {
    let value: Int
    let font: Font
    let color: Color

    @State private var animatedValue: Int = 0

    init(value: Int, font: Font = .title, color: Color = .primary) {
        self.value = value
        self.font = font
        self.color = color
    }

    var body: some View {
        Text("\(animatedValue)")
            .font(font)
            .foregroundColor(color)
            .contentTransition(.numericText())
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: animatedValue)
            .onAppear {
                animatedValue = value
            }
            .onChange(of: value) { _, newValue in
                animatedValue = newValue
            }
    }
}

// MARK: - Animated Percentage

struct AnimatedPercentage: View {
    let value: Double
    let font: Font
    let color: Color
    let decimalPlaces: Int

    @State private var animatedValue: Double = 0

    init(
        value: Double,
        font: Font = .body,
        color: Color = .primary,
        decimalPlaces: Int = 1
    ) {
        self.value = value
        self.font = font
        self.color = color
        self.decimalPlaces = decimalPlaces
    }

    var body: some View {
        Text(String(format: "%.\(decimalPlaces)f%%", animatedValue * 100))
            .font(font)
            .foregroundColor(color)
            .contentTransition(.numericText())
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: animatedValue)
            .onAppear {
                animatedValue = value
            }
            .onChange(of: value) { _, newValue in
                animatedValue = newValue
            }
    }
}

// MARK: - Bouncy Button Style

struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BouncyButtonStyle {
    static var bouncy: BouncyButtonStyle { BouncyButtonStyle() }
}

// MARK: - Animated Icon

struct AnimatedIcon: View {
    let systemName: String
    let isAnimating: Bool
    let animation: Animation

    @State private var rotation: Double = 0

    init(
        systemName: String,
        isAnimating: Bool,
        animation: Animation = .linear(duration: 1).repeatForever(autoreverses: false)
    ) {
        self.systemName = systemName
        self.isAnimating = isAnimating
        self.animation = animation
    }

    var body: some View {
        Image(systemName: systemName)
            .rotationEffect(.degrees(isAnimating ? rotation : 0))
            .onAppear {
                if isAnimating {
                    withAnimation(animation) {
                        rotation = 360
                    }
                }
            }
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    withAnimation(animation) {
                        rotation = 360
                    }
                } else {
                    rotation = 0
                }
            }
    }
}

// MARK: - Staggered Appearance

struct StaggeredAppearance: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .animation(
                .spring(response: 0.4, dampingFraction: 0.8)
                .delay(Double(index) * baseDelay),
                value: isVisible
            )
            .onAppear {
                isVisible = true
            }
    }
}

extension View {
    /// Adds a staggered appearance animation based on index
    func staggeredAppearance(index: Int, baseDelay: Double = 0.05) -> some View {
        modifier(StaggeredAppearance(index: index, baseDelay: baseDelay))
    }
}

// MARK: - Skeleton Loading View

struct SkeletonView: View {
    let width: CGFloat?
    let height: CGFloat

    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(
                LinearGradient(
                    colors: [
                        Color.secondary.opacity(0.2),
                        Color.secondary.opacity(0.1),
                        Color.secondary.opacity(0.2)
                    ],
                    startPoint: isAnimating ? .trailing : .leading,
                    endPoint: isAnimating ? .leading : .trailing
                )
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Animated Checkmark

struct AnimatedCheckmark: View {
    let isChecked: Bool
    let color: Color
    let size: CGFloat

    @State private var trimEnd: CGFloat = 0

    init(isChecked: Bool, color: Color = .green, size: CGFloat = 24) {
        self.isChecked = isChecked
        self.color = color
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(isChecked ? color.opacity(0.15) : Color.clear)
                .frame(width: size, height: size)

            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundColor(color)
                    .scaleEffect(trimEnd)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: trimEnd)
            }
        }
        .onChange(of: isChecked) { _, newValue in
            if newValue {
                trimEnd = 1
            } else {
                trimEnd = 0
            }
        }
        .onAppear {
            if isChecked {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    trimEnd = 1
                }
            }
        }
    }
}
