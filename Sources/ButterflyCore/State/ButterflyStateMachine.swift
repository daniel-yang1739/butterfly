import Foundation
import Combine

/// Butterfly core state definitions
public enum ButterflyState: Equatable {
    case idle
    case listening(audioLevel: Float)
    case processing
    case injecting(text: String)
    case completed(text: String)
    case error(String)
}

public protocol ButterflyStateMachineDelegate: AnyObject {
    func stateMachine(_ stateMachine: ButterflyStateMachine, didTransitionTo state: ButterflyState)
    func stateMachine(_ stateMachine: ButterflyStateMachine, didProduceTranscription text: String)
}

/// Butterfly main state machine coordinator
public final class ButterflyStateMachine: AudioCaptureDelegate, VADDetectorDelegate {
    public weak var delegate: ButterflyStateMachineDelegate?
    
    public private(set) var currentState: ButterflyState = .idle {
        didSet {
            delegate?.stateMachine(self, didTransitionTo: currentState)
        }
    }
    
    public let backend: SpeechInferenceBackend
    public let translator: OpenCCTranslator
    public let formatter: TextFormatter
    public let audioCapture: AudioCaptureManager
    public let vad: VADDetector
    public let injector: InputInjector
    
    public init(
        backend: SpeechInferenceBackend = AppleSiliconInferenceBackend(),
        translator: OpenCCTranslator = .shared,
        formatter: TextFormatter = .shared,
        audioCapture: AudioCaptureManager = AudioCaptureManager(),
        vad: VADDetector = VADDetector(),
        injector: InputInjector = .shared
    ) {
        self.backend = backend
        self.translator = translator
        self.formatter = formatter
        self.audioCapture = audioCapture
        self.vad = vad
        self.injector = injector
        
        self.audioCapture.delegate = self
        self.vad.delegate = self
    }
    
    /// Toggle listening state
    public func toggleListening() async {
        switch currentState {
        case .idle, .completed, .error:
            await startListening()
        case .listening:
            await stopAndProcess()
        case .processing, .injecting:
            break
        }
    }
    
    /// Start microphone audio capture
    public func startListening() async {
        do {
            vad.reset()
            try audioCapture.startRecording()
            currentState = .listening(audioLevel: 0.0)
        } catch {
            currentState = .error(error.localizedDescription)
        }
    }
    
    /// Stop listening and execute inference, translation, and injection pipeline
    public func stopAndProcess() async {
        guard case .listening = currentState else { return }
        
        let samples = audioCapture.stopRecording()
        currentState = .processing
        
        do {
            // 1. Local AI inference (Apple Silicon / NPU)
            let result = try await backend.transcribe(audioSamples: samples)
            
            // 2. OpenCC Traditional Chinese conversion (s2twp standard)
            let traditionalText = translator.convert(result.rawText)
            
            // 3. Spacing and text formatting
            let finalText = formatter.format(traditionalText)
            
            guard !finalText.isEmpty else {
                currentState = .idle
                return
            }
            
            // 4. Inject into active focused input
            currentState = .injecting(text: finalText)
            delegate?.stateMachine(self, didProduceTranscription: finalText)
            await injector.inject(text: finalText)
            
            currentState = .completed(text: finalText)
            
            // Return to idle after short delay
            try? await Task.sleep(nanoseconds: 300_000_000)
            currentState = .idle
        } catch {
            currentState = .error(error.localizedDescription)
        }
    }
    
    // MARK: - AudioCaptureDelegate
    public func audioCaptureManager(_ manager: AudioCaptureManager, didCaptureSamples samples: [Float]) {}
    
    public func audioCaptureManager(_ manager: AudioCaptureManager, didUpdateAudioLevel level: Float) {
        if case .listening = currentState {
            currentState = .listening(audioLevel: level)
            vad.processAudioLevel(level)
        }
    }
    
    public func audioCaptureManager(_ manager: AudioCaptureManager, didFailWithError error: Error) {
        currentState = .error(error.localizedDescription)
    }
    
    // MARK: - VADDetectorDelegate
    public func vadDetector(_ detector: VADDetector, didEmitEvent event: VADEvent) {
        switch event {
        case .speechEnded, .silenceTimeout:
            Task {
                await stopAndProcess()
            }
        default:
            break
        }
    }
}
