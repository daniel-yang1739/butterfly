import Foundation

public enum ButterflyMode: String, CaseIterable, Sendable {
    case liveStreaming = "live"
    case smartPolish = "smart-polish"

    public var title: String {
        switch self {
        case .liveStreaming: return "Live Voice Dictation"
        case .smartPolish: return "Record & Smart Polish"
        }
    }
}

public enum ButterflyState: Equatable, Sendable {
    case idle
    case starting(ButterflyMode)
    case recording(ButterflyMode)
    case processing(ButterflyMode)
}

public enum DictationProcessingStage: Sendable {
    case finalizing, polishing, inserting
}

@MainActor
public protocol DictationSpeechSource: AnyObject {
    func start(
        onTranscript: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws
    func stop() async -> String
}

@MainActor
public protocol DictationTextOutput: AnyObject {
    func update(_ text: String, previousText: inout String)
    func drain() async
    func insert(_ text: String) async -> Bool
}

/// The production recording coordinator, shared by the App and hardware-free tests.
@MainActor
public final class ButterflyStateMachine {
    public private(set) var currentState: ButterflyState = .idle {
        didSet { onStateChange?(currentState) }
    }
    public private(set) var latestTranscript = ""
    public var onStateChange: ((ButterflyState) -> Void)?
    public var onTranscript: ((String) -> Void)?
    public var onAudioLevel: ((Float) -> Void)?
    public var onProcessingStage: ((DictationProcessingStage) -> Void)?
    public var onError: ((Error) -> Void)?
    public var onPolishResult: ((SmartPolishResult) -> Void)?

    private let output: any DictationTextOutput
    private var source: (any DictationSpeechSource)?
    private var generation: UUID?
    private var injectedText = ""
    private var sessionError: Error?
    private var polish: (@MainActor (String) async -> SmartPolishResult)?

    public init(output: any DictationTextOutput) { self.output = output }

    public func start(
        mode: ButterflyMode,
        source: any DictationSpeechSource,
        polish: @escaping @MainActor (String) async -> SmartPolishResult = {
            SmartPolishResult(text: $0, usedFallback: false)
        }
    ) async {
        guard currentState == .idle else { return }
        let id = UUID()
        generation = id
        self.source = source
        self.polish = polish
        latestTranscript = ""
        injectedText = ""
        sessionError = nil
        currentState = .starting(mode)
        do {
            try await source.start(
                onTranscript: { [weak self] text in
                    Task { @MainActor in self?.receive(text, generation: id) }
                },
                onAudioLevel: { [weak self] level in
                    Task { @MainActor in
                        guard let self, self.generation == id,
                              case .recording = self.currentState else { return }
                        self.onAudioLevel?(level)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.generation == id else { return }
                        self.sessionError = self.sessionError ?? error
                        await self.stop()
                    }
                }
            )
            if let sessionError { throw sessionError }
            guard !Task.isCancelled else {
                _ = await source.stop()
                finish()
                return
            }
            currentState = .recording(mode)
            // A source can publish while its asynchronous startup is still completing.
            receive(latestTranscript, generation: id)
        } catch {
            _ = await source.stop()
            sessionError = error
            finish()
        }
    }

    public func stop() async {
        guard case .recording(let mode) = currentState, let source else { return }
        currentState = .processing(mode)
        onProcessingStage?(.finalizing)
        let finalTranscript = await source.stop()
        latestTranscript = finalTranscript
        if mode == .liveStreaming {
            // Final callbacks can arrive during processing; reconcile the returned result once.
            output.update(finalTranscript, previousText: &injectedText)
            await output.drain()
        } else if !Task.isCancelled, !finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let polish {
            onProcessingStage?(.polishing)
            let result = await polish(finalTranscript)
            onPolishResult?(result)
            if !Task.isCancelled, !result.text.isEmpty {
                onProcessingStage?(.inserting)
                if !(await output.insert(result.text)) { sessionError = ButterflyError.injectionFailed }
            }
        }
        finish()
    }

    private func receive(_ text: String, generation id: UUID) {
        guard generation == id else { return }
        switch currentState {
        case .starting:
            latestTranscript = text
        case .recording(let mode):
            latestTranscript = text
            onTranscript?(text)
            if mode == .liveStreaming { output.update(text, previousText: &injectedText) }
        case .idle, .processing:
            break
        }
    }

    private func finish() {
        let error = sessionError
        sessionError = nil
        generation = nil
        source = nil
        polish = nil
        injectedText = ""
        currentState = .idle
        // Report only after capture stops and output drains. A UI alert can change focus.
        if let error { onError?(error) }
    }
}

/// Only this production adapter posts keyboard events; tests inject a recording sink.
@MainActor
public final class CursorDictationOutput: DictationTextOutput {
    private let injector: InputInjector
    public init(injector: InputInjector = .shared) { self.injector = injector }
    public func update(_ text: String, previousText: inout String) {
        let action = injector.prepareStreamingDelta(newText: text, previousText: &previousText)
        injector.enqueueSlidingDelta(action)
    }
    public func drain() async { await injector.waitForPendingInjections() }
    public func insert(_ text: String) async -> Bool {
        await injector.injectByPaste(text: text, restoreClipboard: true)
    }
}
