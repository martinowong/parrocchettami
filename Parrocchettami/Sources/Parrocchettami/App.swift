import SwiftUI

@main
struct ParrocchettamiApp: App {
    @StateObject private var transcriber = Transcriber()
    @StateObject private var appUpdater = AppUpdater()
    @StateObject private var interfaceZoom = InterfaceZoomController()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(transcriber)
                .environmentObject(appUpdater)
                .environmentObject(interfaceZoom)
                .frame(minWidth: 860, minHeight: 580)
                .onAppear { Task { await transcriber.locateCLI() } }
        }
        .commands {
            ParrocchettamiCommands(interfaceZoom: interfaceZoom)

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appUpdater.checkForUpdates()
                }
                .disabled(!appUpdater.canCheckForUpdates)
            }
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
    }
}
