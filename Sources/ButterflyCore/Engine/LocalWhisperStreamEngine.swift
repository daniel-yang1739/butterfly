import Foundation
import os
@preconcurrency import AVFoundation

/// Local microphone transcription using app-owned audio capture and whisper.cpp inference.
public final class LocalWhisperStreamEngine: @unchecked Sendable {
    public static let shared = LocalWhisperStreamEngine()

    private struct StreamState: Sendable {
        var samples: [Float] = []
        var capturedSampleCount = 0
        var isListening = false
        var isTranscribing = false
        var lastTranscribedSampleCount = 0
        var lastVoicedSampleCount = 0
        var lastTranscribedVoicedSampleCount = 0
        var noiseFloor: Float = 0.001
        var latestTranscript = ""
    }

    private struct AudioSnapshot: Sendable {
        let samples: [Float]
        let capturedSampleCount: Int
        let lastVoicedSampleCount: Int

        var windowStartSample: Int {
            capturedSampleCount - samples.count
        }
    }

    public var isListening: Bool {
        stateLock.withLock { $0.isListening }
    }

    public var onTranscriptUpdate: (@Sendable (String) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?

    private let stateLock = OSAllocatedUnfairLock(initialState: StreamState())
    private let backend: AppleSiliconInferenceBackend
    private let accumulator = TranscriptAccumulator()
    private var audioEngine: AVAudioEngine?
    private var pollingTask: Task<Void, Never>?

    private static let sampleRate = Int(AudioCaptureManager.targetSampleRate)
    private static let inferenceWindowSampleCount = sampleRate * 5
    private static let ringBufferSampleCount = sampleRate * 8
    private static let ringBufferTrimThreshold = ringBufferSampleCount + sampleRate
    private static let minimumInitialSampleCount = sampleRate
    private static let inferenceWindowOverlapRatio = 0.5
    private static let inferenceWindowStepSampleCount = Int(
        Double(inferenceWindowSampleCount) * (1 - inferenceWindowOverlapRatio)
    )
    private static let minimumVoiceRMS: Float = 0.004

    public init(backend: AppleSiliconInferenceBackend = AppleSiliconInferenceBackend()) {
        self.backend = backend
    }

    public func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized {
            return true
        }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public func startListening(modelPath: String) async throws {
        guard !isListening else { return }
        try await backend.initialize(modelPath: modelPath)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 else {
            backend.release()
            throw ButterflyError.audioCaptureFailed("Audio hardware returned an invalid sample rate")
        }

        stateLock.withLock { state in
            state.samples.removeAll(keepingCapacity: true)
            state.samples.reserveCapacity(Self.ringBufferTrimThreshold)
            state.capturedSampleCount = 0
            state.isListening = true
            state.isTranscribing = false
            state.lastTranscribedSampleCount = 0
            state.lastVoicedSampleCount = 0
            state.lastTranscribedVoicedSampleCount = 0
            state.noiseFloor = 0.001
            state.latestTranscript = ""
        }
        accumulator.reset()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            let inputSamples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
            let samples16k = AudioCaptureManager.resample(
                inputSamples: inputSamples,
                fromSampleRate: recordingFormat.sampleRate,
                toSampleRate: AudioCaptureManager.targetSampleRate
            )
            let rms = Self.calculateRMS(samples16k)
            self.stateLock.withLock { state in
                guard state.isListening else { return }
                state.samples.append(contentsOf: samples16k)
                state.capturedSampleCount += samples16k.count
                let voiceThreshold = max(Self.minimumVoiceRMS, state.noiseFloor * 3)
                if rms >= voiceThreshold {
                    state.lastVoicedSampleCount = state.capturedSampleCount
                } else {
                    state.noiseFloor = (state.noiseFloor * 0.95) + (rms * 0.05)
                }
                if state.samples.count > Self.ringBufferTrimThreshold {
                    state.samples.removeFirst(state.samples.count - Self.ringBufferSampleCount)
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            audioEngine = engine
        } catch {
            inputNode.removeTap(onBus: 0)
            stateLock.withLock { $0.isListening = false }
            backend.release()
            throw ButterflyError.audioCaptureFailed(error.localizedDescription)
        }

        pollingTask = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, let self, self.isListening else { break }
                await self.transcribeLatestAudio(force: false)
            }
        }
    }

    @discardableResult
    public func stopListening() async -> String {
        guard isListening else { return stateLock.withLock { $0.latestTranscript } }
        stateLock.withLock { $0.isListening = false }

        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        pollingTask?.cancel()
        await pollingTask?.value
        pollingTask = nil

        await transcribeLatestAudio(force: true)
        let finalText = stateLock.withLock { state -> String in
            let text = state.latestTranscript
            state.samples.removeAll(keepingCapacity: false)
            state.capturedSampleCount = 0
            state.lastTranscribedSampleCount = 0
            state.lastVoicedSampleCount = 0
            state.lastTranscribedVoicedSampleCount = 0
            return text
        }
        backend.release()
        return finalText
    }

    private func transcribeLatestAudio(force: Bool) async {
        let snapshot = stateLock.withLock { state -> AudioSnapshot? in
            let newSampleCount = state.capturedSampleCount - state.lastTranscribedSampleCount
            let minimumNewSamples: Int
            if force {
                minimumNewSamples = 1
            } else if state.lastTranscribedSampleCount == 0 {
                minimumNewSamples = Self.minimumInitialSampleCount
            } else {
                minimumNewSamples = Self.inferenceWindowStepSampleCount
            }
            guard !state.isTranscribing,
                  (force || state.capturedSampleCount >= Self.minimumInitialSampleCount),
                  state.lastVoicedSampleCount > state.lastTranscribedVoicedSampleCount,
                  newSampleCount >= minimumNewSamples else {
                return nil
            }
            state.isTranscribing = true
            return AudioSnapshot(
                samples: Array(state.samples.suffix(Self.inferenceWindowSampleCount)),
                capturedSampleCount: state.capturedSampleCount,
                lastVoicedSampleCount: state.lastVoicedSampleCount
            )
        }
        guard let snapshot else { return }

        defer {
            stateLock.withLock { $0.isTranscribing = false }
        }

        do {
            let result = try await backend.transcribe(audioSamples: snapshot.samples)
            let polishedWindow = TextPolisher.shared.polish(result.rawText, mode: .liveStream)
            let fullTranscript = polishedWindow.isEmpty
                ? accumulator.getFullText()
                : accumulator.appendSlidingWindow(
                    rawText: polishedWindow,
                    windowStartSample: snapshot.windowStartSample
                )
            let transcriptChanged = stateLock.withLock { state -> Bool in
                state.lastTranscribedSampleCount = snapshot.capturedSampleCount
                state.lastTranscribedVoicedSampleCount = snapshot.lastVoicedSampleCount
                guard !fullTranscript.isEmpty, fullTranscript != state.latestTranscript else {
                    return false
                }
                state.latestTranscript = fullTranscript
                return true
            }
            guard transcriptChanged else { return }
            onTranscriptUpdate?(fullTranscript)
        } catch {
            onError?(error)
        }
    }

    private static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float.zero) { $0 + ($1 * $1) }
        return sqrt(sum / Float(samples.count))
    }
}
