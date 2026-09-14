import Foundation

@MainActor
public final class AppleDictationSource: DictationSpeechSource {
    private let engine: LiveSpeechEngine
    public init(engine: LiveSpeechEngine) { self.engine = engine }

    public func start(
        onTranscript: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws {
        guard await engine.requestPermissions() else {
            throw ButterflyError.audioCaptureFailed("Enable Microphone and Speech Recognition permissions in System Settings > Privacy & Security.")
        }
        engine.onTranscriptUpdate = onTranscript
        engine.onAudioLevelUpdate = onAudioLevel
        engine.onError = onError
        try engine.startLiveListening()
    }
    public func stop() async -> String { await engine.stopLiveListening() }
}

@MainActor
public final class WhisperDictationSource: DictationSpeechSource {
    private let engine: LocalWhisperStreamEngine
    private let modelPath: String
    public init(engine: LocalWhisperStreamEngine, modelPath: String) {
        self.engine = engine
        self.modelPath = modelPath
    }
    public func start(
        onTranscript: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws {
        guard await engine.requestMicrophonePermission() else {
            throw ButterflyError.audioCaptureFailed("Enable Microphone permission in System Settings > Privacy & Security.")
        }
        engine.onTranscriptUpdate = onTranscript
        engine.onAudioLevelUpdate = onAudioLevel
        engine.onError = onError
        try await engine.startListening(modelPath: modelPath)
    }
    public func stop() async -> String { await engine.stopListening() }
}
