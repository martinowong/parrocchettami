import AppKit
import SwiftUI

private struct InterfaceZoomKey: EnvironmentKey {
    static let defaultValue = 1.0
}

extension EnvironmentValues {
    var interfaceZoom: Double {
        get { self[InterfaceZoomKey.self] }
        set { self[InterfaceZoomKey.self] = newValue }
    }
}

@MainActor
final class InterfaceZoomController: ObservableObject {
    @Published private(set) var scale: Double

    init() {
        let savedScale = UserDefaults.standard.double(forKey: "interfaceScale")
        scale = savedScale == 0 ? 1.0 : min(1.4, max(0.8, savedScale))
    }


    func zoomIn() {
        setScale(scale + 0.1)
    }

    func zoomOut() {
        setScale(scale - 0.1)
    }

    func reset() {
        setScale(1.0)
    }

    private func setScale(_ newScale: Double) {
        scale = min(1.4, max(0.8, (newScale * 10).rounded() / 10))
        UserDefaults.standard.set(scale, forKey: "interfaceScale")
    }
}

// MARK: - Focused Scene Value Keys

struct OpenFileActionKey: FocusedValueKey { typealias Value = () -> Void }
struct ToggleRecordingActionKey: FocusedValueKey { typealias Value = () -> Void }
struct StopRecordingActionKey: FocusedValueKey { typealias Value = () -> Void }
struct ClearFileActionKey: FocusedValueKey { typealias Value = () -> Void }
struct FindInTranscriptActionKey: FocusedValueKey { typealias Value = () -> Void }
struct ToggleDiagnosticsActionKey: FocusedValueKey { typealias Value = () -> Void }
struct ShowTutorialActionKey: FocusedValueKey { typealias Value = () -> Void }

struct IsRecordingKey: FocusedValueKey { typealias Value = Bool }
struct IsPausedKey: FocusedValueKey { typealias Value = Bool }
struct IsTranscribingKey: FocusedValueKey { typealias Value = Bool }
struct IsReadyKey: FocusedValueKey { typealias Value = Bool }
struct HasResultKey: FocusedValueKey { typealias Value = Bool }
struct HasFileKey: FocusedValueKey { typealias Value = Bool }

extension FocusedValues {
    var openFileAction: (() -> Void)? {
        get { self[OpenFileActionKey.self] }
        set { self[OpenFileActionKey.self] = newValue }
    }
    var toggleRecordingAction: (() -> Void)? {
        get { self[ToggleRecordingActionKey.self] }
        set { self[ToggleRecordingActionKey.self] = newValue }
    }
    var stopRecordingAction: (() -> Void)? {
        get { self[StopRecordingActionKey.self] }
        set { self[StopRecordingActionKey.self] = newValue }
    }
    var clearFileAction: (() -> Void)? {
        get { self[ClearFileActionKey.self] }
        set { self[ClearFileActionKey.self] = newValue }
    }
    var findInTranscriptAction: (() -> Void)? {
        get { self[FindInTranscriptActionKey.self] }
        set { self[FindInTranscriptActionKey.self] = newValue }
    }
    var toggleDiagnosticsAction: (() -> Void)? {
        get { self[ToggleDiagnosticsActionKey.self] }
        set { self[ToggleDiagnosticsActionKey.self] = newValue }
    }
    var showTutorialAction: (() -> Void)? {
        get { self[ShowTutorialActionKey.self] }
        set { self[ShowTutorialActionKey.self] = newValue }
    }

    var isRecording: Bool? {
        get { self[IsRecordingKey.self] }
        set { self[IsRecordingKey.self] = newValue }
    }
    var isPaused: Bool? {
        get { self[IsPausedKey.self] }
        set { self[IsPausedKey.self] = newValue }
    }
    var isTranscribing: Bool? {
        get { self[IsTranscribingKey.self] }
        set { self[IsTranscribingKey.self] = newValue }
    }
    var isReady: Bool? {
        get { self[IsReadyKey.self] }
        set { self[IsReadyKey.self] = newValue }
    }
    var hasResult: Bool? {
        get { self[HasResultKey.self] }
        set { self[HasResultKey.self] = newValue }
    }
    var hasFile: Bool? {
        get { self[HasFileKey.self] }
        set { self[HasFileKey.self] = newValue }
    }
}

// MARK: - Menu Commands

struct ParrocchettamiCommands: Commands {
    @ObservedObject var interfaceZoom: InterfaceZoomController

    @FocusedValue(\.openFileAction) var openFile
    @FocusedValue(\.toggleRecordingAction) var toggleRecording
    @FocusedValue(\.stopRecordingAction) var stopRecording
    @FocusedValue(\.clearFileAction) var closeFile
    @FocusedValue(\.findInTranscriptAction) var findInTranscript
    @FocusedValue(\.toggleDiagnosticsAction) var toggleDiagnostics
    @FocusedValue(\.showTutorialAction) var showTutorial

    @FocusedValue(\.isRecording) var isRecording
    @FocusedValue(\.isPaused) var isPaused
    @FocusedValue(\.isTranscribing) var isTranscribing
    @FocusedValue(\.isReady) var isReady
    @FocusedValue(\.hasResult) var hasResult
    @FocusedValue(\.hasFile) var hasFile

    private var recordLabel: String {
        if isRecording ?? false {
            return (isPaused ?? false) ? "Resume Recording" : "Pause Recording"
        }
        return "Start Recording"
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()

            Button("Open Audio…") {
                openFile?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(isTranscribing ?? false || isRecording ?? false || !(isReady ?? false))

            Button(recordLabel) {
                toggleRecording?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(isTranscribing ?? false || !(isReady ?? false))

            Button("Stop & Transcribe") {
                stopRecording?()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!(isRecording ?? false))

            Button("Close") {
                closeFile?()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(!(hasFile ?? false) && !(hasResult ?? false))
        }

        CommandGroup(after: .textEditing) {
            Button("Find in Transcript…") {
                findInTranscript?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(!(hasResult ?? false))
        }

        CommandGroup(after: .sidebar) {
            Button("Zoom In") {
                interfaceZoom.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(interfaceZoom.scale >= 1.4)

            Button("Zoom Out") {
                interfaceZoom.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(interfaceZoom.scale <= 0.8)

            Button("Actual Size") {
                interfaceZoom.reset()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(abs(interfaceZoom.scale - 1.0) < 0.001)

            Divider()

            Button("Toggle Diagnostics") {
                toggleDiagnostics?()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Button("Show Tutorial") {
                showTutorial?()
            }

            Divider()

            Button("Parrocchettami Help") {
                NSApp.sendAction(#selector(NSApplication.showHelp(_:)), to: nil, from: nil)
            }
        }
    }
}

// MARK: - View Modifier for Focused Scene Values

struct FocusedSceneValuesModifier: ViewModifier {
    let openFileAction: () -> Void
    let toggleRecordingAction: () -> Void
    let stopRecordingAction: () -> Void
    let clearFileAction: () -> Void
    let toggleDiagnosticsAction: () -> Void
    let showTutorialAction: () -> Void
    let isRecording: Bool
    let isPaused: Bool
    let isTranscribing: Bool
    let isReady: Bool
    let hasResult: Bool
    let hasFile: Bool

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.openFileAction, openFileAction)
            .focusedSceneValue(\.toggleRecordingAction, toggleRecordingAction)
            .focusedSceneValue(\.stopRecordingAction, stopRecordingAction)
            .focusedSceneValue(\.clearFileAction, clearFileAction)
            .focusedSceneValue(\.toggleDiagnosticsAction, toggleDiagnosticsAction)
            .focusedSceneValue(\.showTutorialAction, showTutorialAction)
            .focusedSceneValue(\.isRecording, isRecording)
            .focusedSceneValue(\.isPaused, isPaused)
            .focusedSceneValue(\.isTranscribing, isTranscribing)
            .focusedSceneValue(\.isReady, isReady)
            .focusedSceneValue(\.hasResult, hasResult)
            .focusedSceneValue(\.hasFile, hasFile)
    }
}
