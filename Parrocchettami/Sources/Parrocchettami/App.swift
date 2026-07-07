import SwiftUI

@main
struct ParrocchettamiApp: App {
    @StateObject private var transcriber = Transcriber()
    @StateObject private var appUpdater = AppUpdater()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(transcriber)
                .environmentObject(appUpdater)
                .frame(minWidth: 760, minHeight: 620)
                .onAppear { Task { await transcriber.locateCLI() } }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appUpdater.checkForUpdates()
                }
                .disabled(!appUpdater.canCheckForUpdates)
            }
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
    }
}
