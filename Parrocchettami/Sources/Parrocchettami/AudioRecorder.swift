import AVFoundation
import AudioToolbox
import CoreAudio

struct MicDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var selectedMic: MicDevice?
    @Published var availableMics: [MicDevice] = []
    @Published var levels: [Float] = Array(repeating: 0.01, count: 30)
    @Published private(set) var lastError: String?

    private var engine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var rawRecordingURL: URL?
    private let recordingErrorLock = NSLock()
    private var didReportRecordingError = false

    override init() {
        super.init()
        scanMics()
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { c in
            AVCaptureDevice.requestAccess(for: .audio) { c.resume(returning: $0) }
        }
    }

    private func scanMics() {
        let previousID = selectedMic?.id
        let devices = Self.audioInputDevices()
        let defaultID = Self.defaultInputDeviceID()

        availableMics = devices
        selectedMic = devices.first(where: { $0.id == previousID })
            ?? devices.first(where: { $0.id == defaultID })
            ?? devices.first
    }

    func startRecording() -> String? {
        lastError = nil
        didReportRecordingError = false

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("parrocchettami")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return "Cannot prepare recording folder: \(error.localizedDescription)"
        }

        let rawURL = dir.appendingPathComponent("recording.caf")
        let wavURL = dir.appendingPathComponent("recording.wav")
        try? FileManager.default.removeItem(at: rawURL)
        try? FileManager.default.removeItem(at: wavURL)

        let engine = AVAudioEngine()
        let input = engine.inputNode

        if let selectedMic,
           let audioUnit = input.audioUnit {
            var deviceID = selectedMic.id
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else {
                return "Cannot use \(selectedMic.name) (Core Audio error \(status))"
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)

        guard let outputFile = try? AVAudioFile(forWriting: rawURL, settings: inputFormat.settings) else {
            return "Cannot create audio file"
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                try outputFile.write(from: buffer)
            } catch {
                self.reportRecordingErrorOnce("Recording write failed: \(error.localizedDescription)")
            }

            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            if let data = channelData {
                var peak: Float = 0
                for i in 0..<frameLength {
                    let v = abs(data[i])
                    if v > peak { peak = v }
                }
                let level = min(1.0, max(0.01, peak * 3.0))

                DispatchQueue.main.async {
                    var new = self.levels
                    new.removeFirst()
                    new.append(level)
                    self.levels = new
                }
            }
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return "Cannot start engine: \(error.localizedDescription)"
        }

        self.engine = engine
        self.outputFile = outputFile
        rawRecordingURL = rawURL
        isPaused = false
        isRecording = true
        return nil
    }

    func stopRecording(completion: @escaping (URL?, String?) -> Void) {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        outputFile = nil
        isRecording = false
        isPaused = false
        levels = Array(repeating: 0.01, count: 30)

        guard let rawURL = rawRecordingURL else {
            completion(nil, "No recording was available to convert.")
            return
        }

        rawRecordingURL = nil
        let wavURL = rawURL.deletingLastPathComponent().appendingPathComponent("recording.wav")

        Task(priority: .userInitiated) {
            do {
                try await convertAudioTo16kHzMonoWAV(sourceURL: rawURL, destinationURL: wavURL)
                try? FileManager.default.removeItem(at: rawURL)
                await MainActor.run { completion(wavURL, nil) }
            } catch {
                let message = "Recording conversion failed: \(error.localizedDescription)"
                await MainActor.run {
                    completion(nil, message)
                }
            }
        }
    }

    func discardRecording() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        outputFile = nil
        isRecording = false
        isPaused = false
        levels = Array(repeating: 0.01, count: 30)

        if let rawRecordingURL {
            try? FileManager.default.removeItem(at: rawRecordingURL)
        }
        rawRecordingURL = nil
    }

    func pauseRecording() {
        guard isRecording, !isPaused, let engine else { return }
        engine.pause()
        isPaused = true
    }

    func resumeRecording() {
        guard isRecording, isPaused, let engine else { return }
        do {
            try engine.start()
            isPaused = false
        } catch {
            lastError = "Cannot resume recording: \(error.localizedDescription)"
        }
    }

    func refreshMics() {
        scanMics()
    }

    private func reportRecordingErrorOnce(_ message: String) {
        recordingErrorLock.lock()
        guard !didReportRecordingError else {
            recordingErrorLock.unlock()
            return
        }
        didReportRecordingError = true
        recordingErrorLock.unlock()

        DispatchQueue.main.async {
            self.lastError = message
        }
    }

    private static func audioInputDevices() -> [MicDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard hasInputStreams(deviceID), let name = deviceName(deviceID) else { return nil }
            return MicDevice(id: deviceID, name: name)
        }
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize >= MemoryLayout<AudioStreamID>.size
    }

    private static func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name)
        return status == noErr ? name?.takeUnretainedValue() as String? : nil
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }
}
