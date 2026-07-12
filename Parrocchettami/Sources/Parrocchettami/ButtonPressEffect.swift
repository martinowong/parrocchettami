import SwiftUI

struct PopButtonPressEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressScale)
            .opacity(pressOpacity)
            .animation(pressAnimation, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        if isEnabled {
                            state = true
                        }
                    }
            )
    }

    private var pressScale: CGFloat {
        guard isEnabled, !reduceMotion else { return 1 }
        return isPressed ? 0.97 : 1
    }

    private var pressOpacity: Double {
        guard isEnabled, reduceMotion else { return 1 }
        return isPressed ? 0.76 : 1
    }

    private var pressAnimation: Animation? {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }
        return isPressed
            ? .easeOut(duration: 0.10)
            : .spring(response: 0.18, dampingFraction: 0.72)
    }
}

extension View {
    func popButtonPressEffect() -> some View {
        modifier(PopButtonPressEffect())
    }
}
