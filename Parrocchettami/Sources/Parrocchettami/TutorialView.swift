import AppKit
import SwiftUI

enum TutorialStep: Int, CaseIterable, Identifiable {
    case splash
    case input
    case processing
    case review
    case finish

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .splash: "Meet Parrocchettami"
        case .input: "Start with an audio file"
        case .processing: "Follow the transcription"
        case .review: "Check uncertain words"
        case .finish: "Export when you’re ready"
        }
    }

    var message: String {
        switch self {
        case .splash:
            "Private, offline transcription with a little help from your new feathered guide."
        case .input:
            "Choose a recording here, or drag one directly onto the card. You can record from the microphone beside it too."
        case .processing:
            "The real progress card shows what Parrocchettami is doing while everything stays on your Mac."
        case .review:
            "Tap the warning control to reveal words the model was less sure about. They appear in orange in the transcript."
        case .finish:
            "Choose a format, then export the finished transcript from this button. Your copy also stays in History."
        }
    }

    var mascot: TutorialMascotPose {
        switch self {
        case .splash, .finish: .waving
        case .input: .flying
        case .processing: .base
        case .review: .thinking
        }
    }

    var target: TutorialTarget? {
        switch self {
        case .splash: nil
        case .input: .input
        case .processing: .processing
        case .review: .confidence
        case .finish: .export
        }
    }
}

enum TutorialTarget: Hashable {
    case input
    case processing
    case confidence
    case export
}

struct TutorialTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [TutorialTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TutorialTarget: Anchor<CGRect>],
        nextValue: () -> [TutorialTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func tutorialTarget(_ target: TutorialTarget) -> some View {
        anchorPreference(key: TutorialTargetPreferenceKey.self, value: .bounds) {
            [target: $0]
        }
    }
}

enum TutorialMascotPose: String {
    case base = "parrocchetto-base"
    case flying = "parrocchetto-flying"
    case thinking = "parrocchetto-thinking"
    case waving = "parrocchetto-waving"

    var image: NSImage? {
        TutorialAssetLoader.image(named: rawValue)
    }
}

private enum TutorialAssetLoader {
    static func image(named name: String) -> NSImage? {
        candidateDirectories
            .map { $0.appendingPathComponent("\(name).png") }
            .compactMap(NSImage.init(contentsOf:))
            .first
    }

    private static var candidateDirectories: [URL] {
        var directories: [URL] = []

        if let resources = Bundle.main.resourceURL {
            directories.append(resources.appendingPathComponent("Tutorial", isDirectory: true))
        }

        if let projectRoot = ProcessInfo.processInfo.environment["PARROCCHETTAMI_HOME"] {
            directories.append(
                URL(fileURLWithPath: projectRoot, isDirectory: true)
                    .appendingPathComponent("Assets/Tutorial", isDirectory: true)
            )
        }

        let workingDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        directories.append(workingDirectory.appendingPathComponent("Assets/Tutorial", isDirectory: true))
        directories.append(workingDirectory.deletingLastPathComponent().appendingPathComponent("Assets/Tutorial", isDirectory: true))
        return directories
    }
}

private enum TutorialSound {
    case arrive
    case move
    case complete

    @MainActor
    func play() {
        let name: NSSound.Name = switch self {
        case .arrive: NSSound.Name("Tink")
        case .move: NSSound.Name("Pop")
        case .complete: NSSound.Name("Glass")
        }

        if let sound = NSSound(named: name) {
            sound.stop()
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}

struct TutorialView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var step: TutorialStep
    let targetFrame: CGRect?
    let canvasSize: CGSize
    let onFinish: () -> Void
    let onSkip: () -> Void

    @State private var pulse = false
    @State private var splashMascotVisible = false
    @State private var splashCopyVisible = false

    var body: some View {
        ZStack {
            if step == .splash {
                splash
                    .transition(.opacity)
            } else {
                guidedOverlay
                    .transition(.opacity)
            }
        }
        .onAppear {
            TutorialSound.arrive.play()
            animateSplashIn()
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: step) { _, newStep in
            if newStep == .splash {
                splashMascotVisible = false
                splashCopyVisible = false
                animateSplashIn()
            }
        }
        .onExitCommand(perform: skip)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Parrocchettami tutorial")
    }

    private var splash: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color.accentColor.opacity(0.24), Color.green.opacity(0.12), .clear],
                center: .center,
                startRadius: 30,
                endRadius: min(canvasSize.width, canvasSize.height) * 0.62
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [Color.accentColor.opacity(0.58), Color.purple.opacity(0.35), Color.green.opacity(0.35), Color.accentColor.opacity(0.58)],
                                center: .center
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 270, height: 270)
                        .scaleEffect(reduceMotion ? 1 : (pulse ? 1.06 : 0.96))
                        .opacity(reduceMotion ? 0.45 : (pulse ? 0.68 : 0.28))

                    if let image = TutorialMascotPose.waving.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 330, height: 300)
                            .accessibilityLabel("Waving Parrocchettami parakeet")
                    }
                }
                .opacity(splashMascotVisible ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (splashMascotVisible ? 0 : 14))

                VStack(spacing: 9) {
                    Text(step.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(step.message)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 530)
                }

                HStack(spacing: 10) {
                    Label("Offline", systemImage: "lock.fill")
                    Label("25 languages", systemImage: "globe")
                    Label("Editable", systemImage: "text.badge.checkmark")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.quaternary.opacity(0.7), in: Capsule())

                HStack(spacing: 12) {
                    Button("Skip", action: skip)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                    Button("Start quick tour") {
                        goForward()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(40)
            .opacity(splashCopyVisible ? 1 : 0)
        }
    }

    @ViewBuilder
    private var guidedOverlay: some View {
        let spotlight = expandedTargetFrame

        ZStack {
            SpotlightMask(spotlightRect: spotlight)
                .fill(Color.black.opacity(0.50), style: FillStyle(eoFill: true))

            if let spotlight {
                targetGlow(around: spotlight)

                coachmark
                    .position(coachmarkPosition(for: spotlight))
                    .id(step)
                    .transition(coachmarkTransition)
            }

            progressIndicator
                .position(x: canvasSize.width / 2, y: 24)
        }
    }

    private var expandedTargetFrame: CGRect? {
        guard let targetFrame else { return nil }

        switch step.target {
        case .confidence:
            // Liquid Glass draws this compact control asymmetrically outside
            // its SwiftUI layout bounds. Follow the visible orange capsule.
            return targetFrame
                .insetBy(dx: 0, dy: 4)
                .offsetBy(dx: -6, dy: 2)
        case .export:
            // Keep the spotlight on the visible export capsule rather than
            // the button style's larger interaction region.
            return targetFrame
                .insetBy(dx: 2, dy: 5)
                .offsetBy(dx: -1, dy: 3)
        case .input, .processing:
            return targetFrame.insetBy(dx: -8, dy: -8)
        case .none:
            return targetFrame
        }
    }

    private func targetGlow(around frame: CGRect) -> some View {
        RoundedRectangle(cornerRadius: targetCornerRadius, style: .continuous)
            .stroke(
                AngularGradient(
                    colors: [Color.accentColor, Color.purple.opacity(0.8), Color.orange.opacity(0.72), Color.accentColor],
                    center: .center
                ),
                lineWidth: 3
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .opacity(reduceMotion ? 0.82 : (pulse ? 1 : 0.58))
            .shadow(color: Color.accentColor.opacity(0.38), radius: pulse ? 14 : 8)
            .allowsHitTesting(false)
    }

    private var targetCornerRadius: CGFloat {
        switch step.target {
        case .input: 20
        case .processing: 14
        case .confidence: 9
        case .export: 10
        case .none: 16
        }
    }

    private var coachmark: some View {
        HStack(alignment: .top, spacing: 15) {
            if let image = step.mascot.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 108, height: 116)
                    .accessibilityLabel("Parrocchettami parakeet guide")
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(step.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))

                Text(step.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if step != .input {
                        Button("Back", action: goBack)
                    }

                    Spacer()

                    Button("Skip", action: skip)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                    Button(step == .finish ? "Done" : "Next", action: goForward)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 3)
            }
        }
        .padding(17)
        .frame(width: 410)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
    }

    private var progressIndicator: some View {
        HStack(spacing: 7) {
            ForEach(TutorialStep.allCases.dropFirst()) { candidate in
                Capsule()
                    .fill(candidate == step ? Color.white : Color.white.opacity(0.38))
                    .frame(width: candidate == step ? 22 : 7, height: 7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.34), in: Capsule())
        .accessibilityLabel("Tutorial step \(step.rawValue) of 4")
    }

    private var coachmarkTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.96))
    }

    private func coachmarkPosition(for frame: CGRect) -> CGPoint {
        let cardWidth: CGFloat = 410
        let cardHeight: CGFloat = 190
        let margin: CGFloat = 22

        let proposed: CGPoint
        switch step {
        case .input:
            proposed = CGPoint(
                x: frame.maxX + cardWidth / 2 + 18,
                y: frame.midY
            )
        case .processing:
            proposed = CGPoint(
                x: frame.midX,
                y: frame.maxY + cardHeight / 2 + 22
            )
        case .review, .finish:
            proposed = CGPoint(
                x: frame.midX,
                y: frame.maxY + cardHeight / 2 + 26
            )
        case .splash:
            proposed = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        }

        return CGPoint(
            x: min(max(proposed.x, cardWidth / 2 + margin), canvasSize.width - cardWidth / 2 - margin),
            y: min(max(proposed.y, cardHeight / 2 + margin), canvasSize.height - cardHeight / 2 - margin)
        )
    }

    private func animateSplashIn() {
        let mascotAnimation: Animation = reduceMotion
            ? .easeOut(duration: 0.16)
            : .easeOut(duration: 0.42)
        let copyAnimation: Animation = reduceMotion
            ? .easeOut(duration: 0.16)
            : .easeOut(duration: 0.30).delay(0.07)

        withAnimation(mascotAnimation) {
            splashMascotVisible = true
        }
        withAnimation(copyAnimation) {
            splashCopyVisible = true
        }
    }

    private func goForward() {
        guard let next = TutorialStep(rawValue: step.rawValue + 1) else {
            TutorialSound.complete.play()
            onFinish()
            return
        }

        TutorialSound.move.play()
        withAnimation(stepAnimation) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = TutorialStep(rawValue: step.rawValue - 1) else { return }
        TutorialSound.move.play()
        withAnimation(stepAnimation) {
            step = previous
        }
    }

    private var stepAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .easeOut(duration: 0.24)
    }

    private func skip() {
        TutorialSound.move.play()
        onSkip()
    }
}

private struct SpotlightMask: Shape {
    let spotlightRect: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if let spotlightRect {
            path.addRoundedRect(
                in: spotlightRect,
                cornerSize: CGSize(width: 18, height: 18)
            )
        }
        return path
    }
}
