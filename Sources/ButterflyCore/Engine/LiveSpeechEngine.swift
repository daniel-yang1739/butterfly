import Foundation
import os
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Real-time live microphone speech recognition engine with monotonic transcript accumulation
public final class LiveSpeechEngine: NSObject, @unchecked Sendable, SFSpeechRecognizerDelegate {
    public static let shared = LiveSpeechEngine()
    
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    public private(set) var isListening: Bool = false
    public private(set) var latestFullTranscript: String = ""
    
    public var onTranscriptUpdate: (@Sendable (String) -> Void)?
    public var onFullTranscriptUpdate: (@Sendable (String) -> Void)?
    public var onAudioLevelUpdate: (@Sendable (Float) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?
    
    public override init() {
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
        self.speechRecognizer?.delegate = self
    }
    
    /// Request microphone and speech recognition permissions
    public func requestPermissions() async -> Bool {
        let speechAuth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
        let micAuth = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        
        return speechAuth && micAuth
    }
    
    /// Start live microphone capture and continuous speech recognition
    public func startLiveListening() throws {
        guard !isListening else { return }
        
        TranscriptAccumulator.shared.reset()
        latestFullTranscript = ""
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw ButterflyError.audioCaptureFailed("Failed to create speech recognition request")
        }
        
        recognitionRequest.taskHint = .dictation
        recognitionRequest.contextualStrings = TechDictionary.engineeringVocabulary + [
            "Typeless", "Record", "Smart Polish", "Polish", "Live Streaming", "Dictation",
            "Esc", "Option", "Space", "Command", "Shift", "Bullet", "Markdown"
        ]
        
        if #available(macOS 13.0, *) {
            recognitionRequest.addsPunctuation = true
        }
        
        recognitionRequest.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let raw = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return }
                
                let traditional = OpenCCTranslator.shared.convert(raw)
                let formatted = TextFormatter.shared.format(traditional)
                
                // Monotonically accumulate full text across pauses and sliding windows
                let full = TranscriptAccumulator.shared.append(rawText: formatted)
                self.latestFullTranscript = full
                
                self.onTranscriptUpdate?(formatted)
                self.onFullTranscriptUpdate?(full)
            }
            
            if let error = error {
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 209) {
                    return
                }
                self.onError?(error)
            }
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0.0
                for i in 0..<frameLength {
                    sum += channelData[i] * channelData[i]
                }
                let rms = sqrt(sum / Float(max(frameLength, 1)))
                let level = min(max(rms * 5.0, 0.0), 1.0)
                DispatchQueue.main.async {
                    self?.onAudioLevelUpdate?(level)
                }
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
    }
    
    /// Stop microphone recording and return 100% complete accumulated transcript
    @discardableResult
    public func stopLiveListening() async -> String {
        guard isListening else { return TranscriptAccumulator.shared.getFullText() }
        isListening = false
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        
        // 150ms grace period for final recognition callback
        try? await Task.sleep(nanoseconds: 150_000_000)
        
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let completeMonologue = TranscriptAccumulator.shared.getFullText()
        latestFullTranscript = completeMonologue
        
        return completeMonologue
    }
}
