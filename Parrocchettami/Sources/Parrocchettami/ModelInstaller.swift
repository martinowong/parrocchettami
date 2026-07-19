import CryptoKit
import Foundation

final class ModelInstaller: NSObject, ObservableObject {
    static let modelFileName = "tdt-0.6b-v3-q5_k.gguf"
    static let modelURL = URL(string: "https://huggingface.co/mudler/parakeet-cpp-gguf/resolve/main/tdt-0.6b-v3-q5_k.gguf")!
    static let expectedSHA256 = "5ebd1d55609b5ad9dac1c457eeb87a9904f199d6fbbb738453182d010646c2e4"
    private static let validationCacheLock = NSLock()
    private static var validationCache: [String: CachedModelValidation] = [:]

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

    private var resumeDataURL: URL {
        Self.installedModelURL
            .deletingLastPathComponent()
            .appendingPathComponent("download-resume-data")
    }

    override init() {
        isInstalled = Self.modelFileIsValid(at: Self.installedModelURL)
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

        let task: URLSessionDownloadTask
        if let resumeData = try? Data(contentsOf: resumeDataURL) {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: Self.modelURL)
        }
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel { [self] resumeData in
            if let resumeData {
                saveResumeData(resumeData)
            } else {
                try? FileManager.default.removeItem(at: resumeDataURL)
            }
        }
        downloadTask = nil
        isDownloading = false
        progress = 0
    }

    private func saveResumeData(_ data: Data) {
        let url = resumeDataURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
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

    static func modelFileIsValid(
        at url: URL,
        expectedSHA256: String = ModelInstaller.expectedSHA256
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let cacheKey = "\(url.path)|\(expectedSHA256)"
        let cached = cachedValidation(for: cacheKey)
        if cached?.fileSize == values?.fileSize,
           cached?.modificationDate == values?.contentModificationDate {
            return cached?.isValid == true
        }

        let isValid = (try? sha256(of: url)) == expectedSHA256
        cacheValidation(
            CachedModelValidation(
                fileSize: values?.fileSize,
                modificationDate: values?.contentModificationDate,
                isValid: isValid
            ),
            for: cacheKey
        )
        return isValid
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func cachedValidation(for key: String) -> CachedModelValidation? {
        validationCacheLock.lock()
        defer { validationCacheLock.unlock() }
        return validationCache[key]
    }

    private static func cacheValidation(_ validation: CachedModelValidation, for key: String) {
        validationCacheLock.lock()
        validationCache[key] = validation
        validationCacheLock.unlock()
    }
}

private struct CachedModelValidation {
    let fileSize: Int?
    let modificationDate: Date?
    let isValid: Bool
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
            try? FileManager.default.removeItem(at: resumeDataURL)
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
        let nsError = error as NSError
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            saveResumeData(resumeData)
        }
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
