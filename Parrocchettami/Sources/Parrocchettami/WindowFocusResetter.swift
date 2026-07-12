import AppKit
import SwiftUI

/// Clears SwiftUI's automatically chosen first responder when the app window activates.
/// Once the user navigates with the keyboard, AppKit can still focus controls normally.
struct WindowFocusResetter: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusResetView {
        FocusResetView()
    }

    func updateNSView(_ nsView: FocusResetView, context: Context) {}
}

final class FocusResetView: NSView {
    private var keyWindowObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }

        guard let window else { return }

        clearAutomaticFocus(in: window)
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.clearAutomaticFocus(in: window)
        }
    }

    deinit {
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
    }

    private func clearAutomaticFocus(in window: NSWindow) {
        DispatchQueue.main.async {
            guard window.isKeyWindow else { return }
            window.makeFirstResponder(nil)
        }
    }
}
