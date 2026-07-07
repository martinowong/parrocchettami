import Foundation

protocol ProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessOutput
}

extension ProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String]
    ) async throws -> ProcessOutput {
        try await run(
            executableURL: executableURL,
            arguments: arguments,
            environment: minimalSubprocessEnvironment()
        )
    }
}

func minimalSubprocessEnvironment() -> [String: String] {
    var env: [String: String] = [:]
    if let home = ProcessInfo.processInfo.environment["PARROCCHETTAMI_HOME"] {
        env["PARROCCHETTAMI_HOME"] = home
    }
    env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    if let dyldFallback = ProcessInfo.processInfo.environment["DYLD_FALLBACK_LIBRARY_PATH"] {
        env["DYLD_FALLBACK_LIBRARY_PATH"] = dyldFallback
    }
    return env
}

struct ProcessOutput {
    let terminationStatus: Int32
    let data: Data

    var text: String {
        String(data: data, encoding: .utf8) ?? "(binary output)"
    }
}

enum ProcessRunnerError: LocalizedError {
    case cancelled
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return nil
        case .launchFailed(let message):
            return message
        }
    }
}

final class ProcessRunner: ProcessRunning {
    private let lock = NSLock()
    private var currentProcess: Process?
    private var cancellationRequested = false

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let process = currentProcess
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> ProcessOutput {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let outputBuffer = LockedDataBuffer()
                let pipe = Pipe()

                process.executableURL = executableURL
                process.arguments = arguments
                process.environment = environment
                process.standardOutput = pipe
                process.standardError = pipe

                lock.lock()
                currentProcess = process
                cancellationRequested = false
                lock.unlock()

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    outputBuffer.append(handle.availableData)
                }

                process.terminationHandler = { [weak self] proc in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    outputBuffer.append(pipe.fileHandleForReading.readDataToEndOfFile())

                    if self?.finishProcess() == true {
                        continuation.resume(throwing: ProcessRunnerError.cancelled)
                    } else {
                        continuation.resume(returning: ProcessOutput(
                            terminationStatus: proc.terminationStatus,
                            data: outputBuffer.snapshot()
                        ))
                    }
                }

                do {
                    try process.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    _ = finishProcess()
                    continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            cancel()
        }
    }

    private func finishProcess() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasCancelled = cancellationRequested
        currentProcess = nil
        cancellationRequested = false
        return wasCancelled
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
