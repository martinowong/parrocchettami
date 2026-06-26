import SwiftUI

@main
struct ParrocchettamiApp: App {
    @StateObject private var transcriber = Transcriber()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(transcriber)
                .frame(minWidth: 760, minHeight: 620)
                .onAppear { transcriber.locateCLI() }
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
    }
}
