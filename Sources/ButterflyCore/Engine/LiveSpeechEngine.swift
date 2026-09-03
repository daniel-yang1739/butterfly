import Foundation
import AVFoundation
import Speech

/// Real-time live microphone speech recognition engine
public final class LiveSpeechEngine: NSObject, @unchecked Sendable, SFSpeechRecognizerDelegate {
    public static let shared = LiveSpeechEngine()
    
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    public private(set) var isListening: Bool = false
    public private(set) var latestFullTranscript: String = ""
    
    public var onTranscriptUpdate: (@Sendable (String) -> Void)?
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
        
        latestFullTranscript = ""
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let inputNode = audioEngine.inputNode
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw ButterflyError.audioCaptureFailed("Failed to create speech recognition request")
        }
        
        // Continuous dictation task hint
        recognitionRequest.taskHint = .dictation
        
        // Inject comprehensive engineering lexicon for accurate code-switching
        recognitionRequest.contextualStrings = TechDictionary.engineeringVocabulary
        
        // Enable automatic punctuation on macOS 13+
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
                
                // Directly convert to Traditional Chinese (OpenCC s2twp) and format
                let traditional = OpenCCTranslator.shared.convert(raw)
                let formatted = TextFormatter.shared.format(traditional)
                
                self.latestFullTranscript = formatted
                self.onTranscriptUpdate?(formatted)
            }
            
            if let error = error {
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 209) {
                    return
                }
                self.onError?(error)
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
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
    
    /// Stop microphone recording and asynchronously drain final recognition buffer
    @discardableResult
    public func stopLiveListening() async -> String {
        guard isListening else { return latestFullTranscript }
        isListening = false
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Signal audio end and allow pipeline to drain pending buffers
        recognitionRequest?.endAudio()
        
        // 200ms grace period for final recognition callback
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        return latestFullTranscript
    }
}
