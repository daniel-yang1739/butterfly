import Foundation
import os
@preconcurrency import AVFoundation

/// Local microphone transcription using app-owned audio capture and whisper.cpp inference.
public final class LocalWhisperStreamEngine: @unchecked Sendable {
    public static let shared = LocalWhisperStreamEngine()

    private struct StreamState: Sendable {
        var audio = DictationAudioBuffer()
        var isListening = false
        var isTranscribing = false
        var noiseFloor: Float = 0.001
        var latestTranscript = ""
    }

    public var isListening: Bool {
        stateLock.withLock { $0.isListening }
    }

    public var onTranscriptUpdate: (@Sendable (String) -> Void)?
    public var onAudioLevelUpdate: (@Sendable (Float) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?

    private let stateLock = OSAllocatedUnfairLock(initialState: StreamState())
    private let backend: AppleSiliconInferenceBackend
    private let accumulator = TranscriptAccumulator()
    private var audioEngine: AVAudioEngine?
    private var pollingTask: Task<Void, Never>?

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
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            backend.release()
            throw ButterflyError.audioCaptureFailed("Audio hardware returned an invalid sample rate")
        }

        stateLock.withLock { state in
            state = StreamState()
            state.isListening = true
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
            self.onAudioLevelUpdate?(min(max(rms * 5, 0), 1))
            self.stateLock.withLock { state in
                guard state.isListening else { return }
                let voiceThreshold = max(Self.minimumVoiceRMS, state.noiseFloor * 3)
                let isVoiced = rms >= voiceThreshold
                if !isVoiced {
                    state.noiseFloor = (state.noiseFloor * 0.95) + (rms * 0.05)
                }
                state.audio.append(samples16k, isVoiced: isVoiced)
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
                _ = await self.transcribeLatestAudio()
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

        stateLock.withLock { $0.audio.finish() }
        // Drain every sealed utterance, including audio captured during a slow inference.
        while await transcribeLatestAudio() {}
        let finalText = stateLock.withLock { state -> String in
            let text = state.latestTranscript
            state.audio = DictationAudioBuffer()
            return text
        }
        backend.release()
        return finalText
    }

    /// Returns false when no work remains or inference fails, so finalization cannot spin.
    private func transcribeLatestAudio() async -> Bool {
        let snapshot = stateLock.withLock { state -> DictationAudioBuffer.Snapshot? in
            guard !state.isTranscribing, let snapshot = state.audio.nextSnapshot() else { return nil }
            state.isTranscribing = true
            return snapshot
        }
        guard let snapshot else { return false }

        defer {
            stateLock.withLock { $0.isTranscribing = false }
        }

        do {
            let result = try await backend.transcribe(audioSamples: snapshot.samples)
            let polishedWindow = TextPolisher.shared.polish(result.rawText, mode: .liveStream)
            let fullTranscript = accumulator.updateSegment(
                rawText: polishedWindow, segmentStartSample: snapshot.startSample
            )
            let transcriptChanged = stateLock.withLock { state -> Bool in
                state.audio.acknowledge(snapshot)
                guard fullTranscript != state.latestTranscript else {
                    return false
                }
                state.latestTranscript = fullTranscript
                return true
            }
            if transcriptChanged { onTranscriptUpdate?(fullTranscript) }
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    private static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float.zero) { $0 + ($1 * $1) }
        return sqrt(sum / Float(samples.count))
    }
}
