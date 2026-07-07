import Combine
import Foundation
import Sparkle

final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private var cancellable: AnyCancellable?

    init() {
        let shouldStartUpdater = Bundle.main.bundleURL.pathExtension == "app"
        updaterController = SPUStandardUpdaterController(
            startingUpdater: shouldStartUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        cancellable = updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
