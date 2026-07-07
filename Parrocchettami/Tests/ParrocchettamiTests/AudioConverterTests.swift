import XCTest
@testable import Parrocchettami

final class AudioConverterTests: XCTestCase {
    func testOpusConversionUsesBundledOpusdecThenAfconvert() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("parrocchettami-audio-converter-tests-\(UUID().uuidString)", isDirectory: true)
        let binDir = tempDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let opusdecURL = binDir.appendingPathComponent("opusdec")
        FileManager.default.createFile(atPath: opusdecURL.path, contents: Data(), attributes: [
            .posixPermissions: 0o755
        ])

        let sourceURL = tempDir.appendingPathComponent("voice.opus")
        let destinationURL = tempDir.appendingPathComponent("transcribe_input.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("opus".utf8))

        let runner = MockAudioProcessRunner()

        try await convertAudioTo16kHzMonoWAV(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            processRunner: runner,
            resourceBaseDir: tempDir.path
        )

        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0].executableURL.path, opusdecURL.path)
        XCTAssertEqual(runner.calls[0].arguments.prefix(3), ["--quiet", "--rate", "16000"])
        XCTAssertEqual(runner.calls[0].arguments[3], sourceURL.path)
        XCTAssertEqual(runner.calls[1].executableURL.path, "/usr/bin/afconvert")
        XCTAssertEqual(runner.calls[1].arguments.prefix(6), ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testOpusConversionFailsWhenOpusdecIsUnavailable() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("parrocchettami-audio-converter-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("voice.opus")
        let destinationURL = tempDir.appendingPathComponent("transcribe_input.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("opus".utf8))

        do {
            try await convertAudioTo16kHzMonoWAV(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            processRunner: MockAudioProcessRunner(),
            resourceBaseDir: tempDir.path,
            allowSystemOpusDecoderFallback: false
        )
            XCTFail("Expected Opus conversion to fail without opusdec")
        } catch AudioConversionError.opusDecoderNotFound {
            // Expected.
        } catch {
            XCTFail("Expected opusDecoderNotFound, got \(error)")
        }
    }
}

private final class MockAudioProcessRunner: ProcessRunning {
    struct Call {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
    }

    private(set) var calls: [Call] = []

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessOutput {
        calls.append(Call(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment
        ))

        if let outputPath = arguments.last {
            let header = Data(repeating: 0, count: 44)
            let payload = Data(repeating: 1, count: 16)
            FileManager.default.createFile(
                atPath: outputPath,
                contents: header + payload
            )
        }

        return ProcessOutput(terminationStatus: 0, data: Data())
    }
}
