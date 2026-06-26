import CryptoKit
import Foundation

final class ModelInstaller: NSObject, ObservableObject {
    static let modelFileName = "tdt-0.6b-v3-q5_k.gguf"
    static let modelURL = URL(string: "https://huggingface.co/mudler/parakeet-cpp-gguf/resolve/main/tdt-0.6b-v3-q5_k.gguf")!
    static let expectedSHA256 = "5ebd1d55609b5ad9dac1c457eeb87a9904f199d6fbbb738453182d010646c2e4"

    @Published private(set) var isInstalled: Bool
    @Published private(set) var isDownloading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var errorMessage: String?

    private var downloadTask: URLSessionDownloadTask?
    private lazy var session = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: nil
    )

    override init() {
        isInstalled = FileManager.default.fileExists(atPath: Self.installedModelURL.path)
        super.init()
    }

    static var installedModelURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Parrocchettami", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(modelFileName)
    }

    func startDownload() {
        guard !isDownloading else { return }
        errorMessage = nil
        progress = 0
        isDownloading = true

        let task = session.downloadTask(with: Self.modelURL)
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        progress = 0
    }

    private func installDownloadedFile(from temporaryURL: URL) throws {
        let checksum = try Self.sha256(of: temporaryURL)
        guard checksum == Self.expectedSHA256 else {
            throw InstallerError.invalidChecksum
        }

        let destination = Self.installedModelURL
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ModelInstaller: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.progress = value }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try installDownloadedFile(from: location)
            DispatchQueue.main.async {
                self.downloadTask = nil
                self.progress = 1
                self.isDownloading = false
                self.isInstalled = true
                self.errorMessage = nil
            }
        } catch {
            DispatchQueue.main.async {
                self.downloadTask = nil
                self.isDownloading = false
                self.progress = 0
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async {
            self.downloadTask = nil
            self.isDownloading = false
            self.progress = 0
            self.errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }
}

private enum InstallerError: LocalizedError {
    case invalidChecksum

    var errorDescription: String? {
        "The downloaded model failed its integrity check. Please try again."
    }
}
