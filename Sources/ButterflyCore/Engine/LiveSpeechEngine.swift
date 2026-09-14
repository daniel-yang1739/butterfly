import Foundation
import os
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Main-actor lifecycle with a synchronized audio-thread request sink.
@MainActor
public final class LiveSpeechEngine {
    public static let shared = LiveSpeechEngine()

    private var audioEngine: AVAudioEngine?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioSink = SpeechAudioSink()
    private let session = SpeechRecognitionSession()
    private var stoppingTask: Task<String, Never>?

    public private(set) var isListening = false
    public var latestFullTranscript: String { session.transcript }
    public var onTranscriptUpdate: (@Sendable (String) -> Void)?
    public var onFullTranscriptUpdate: (@Sendable (String) -> Void)?
    public var onAudioLevelUpdate: (@Sendable (Float) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?

    public init() {}

    /// Request microphone and speech recognition permissions safely
    public func requestPermissions() async -> Bool {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let speechAuth: Bool
        if speechStatus == .authorized {
            speechAuth = true
        } else {
            speechAuth = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
        
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let micAuth: Bool
        if micStatus == .authorized {
            micAuth = true
        } else {
            micAuth = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        
        return speechAuth && micAuth
    }
    
    public func startLiveListening() throws {
        guard !isListening, stoppingTask == nil else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw ButterflyError.audioCaptureFailed("Apple Speech recognition is unavailable. Select a downloaded Whisper model or try again later.")
        }
        session.reset()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw ButterflyError.audioCaptureFailed("Audio hardware returned an invalid sample rate")
        }

        isListening = true
        beginRecognitionRequest()
        let sink = audioSink
        let levelCallback = onAudioLevelUpdate
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            sink.append(buffer)
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            let rms = sqrt(samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count))
            levelCallback?(min(max(rms * 5, 0), 1))
        }
        do {
            engine.prepare()
            try engine.start()
            audioEngine = engine
        } catch {
            input.removeTap(onBus: 0)
            isListening = false
            cleanupRecognition()
            throw ButterflyError.audioCaptureFailed("Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    @discardableResult
    public func stopLiveListening() async -> String {
        if let stoppingTask { return await stoppingTask.value }
        guard isListening else { return session.transcript }
        isListening = false
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        audioSink.endAudio()

        let task = Task { @MainActor [self] in
            await session.waitForFinal()
            let transcript = session.transcript
            cleanupRecognition()
            return transcript
        }
        stoppingTask = task
        let transcript = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        stoppingTask = nil
        return transcript
    }

    private func beginRecognitionRequest() {
        // Invalidate first: cancel() can schedule callbacks from the old request.
        let id = session.beginRequest()
        recognitionTask?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.taskHint = .dictation
        request.contextualStrings = TechDictionary.allVocabulary
        request.addsPunctuation = true
        request.shouldReportPartialResults = true
        audioSink.replace(with: request)
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            // Transfer value snapshots, never framework result objects, to the main actor.
            let raw = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error.map { $0 as NSError }
            Task { @MainActor [weak self] in
                self?.receive(raw: raw, isFinal: isFinal, error: failure, requestID: id)
            }
        }
    }

    private func receive(raw: String?, isFinal: Bool, error: NSError?, requestID: UUID) {
        guard session.requestID == requestID else { return }
        if let raw {
            let formatted = TextPolisher.shared.polish(raw, mode: .liveStream)
            if session.receive(formatted, isFinal: isFinal, requestID: requestID) {
                onTranscriptUpdate?(session.transcript)
                onFullTranscriptUpdate?(session.transcript)
            }
        }
        if isFinal || error != nil {
            session.complete(requestID: requestID)
            if isListening {
                let recoverable = error == nil || (error?.domain == "kAFAssistantErrorDomain"
                    && [216, 209, 1110].contains(error?.code ?? 0))
                if recoverable { beginRecognitionRequest() }
                else if let error { onError?(error) }
            }
        }
    }

    private func cleanupRecognition() {
        session.invalidate()
        audioSink.replace(with: nil)
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

/// Audio buffers are appended under the same lock used to end or replace requests.
private final class SpeechAudioSink: @unchecked Sendable {
    private let request = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(initialState: nil)

    func append(_ buffer: AVAudioPCMBuffer) {
        request.withLock { $0?.append(buffer) }
    }

    func replace(with next: SFSpeechAudioBufferRecognitionRequest?) {
        request.withLock { current in
            current?.endAudio()
            current = next
        }
    }

    func endAudio() { replace(with: nil) }
}
