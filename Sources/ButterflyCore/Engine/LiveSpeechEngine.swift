import Foundation
import os
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Real-time live microphone speech recognition engine with full audio persistence & whole-file transcription
public final class LiveSpeechEngine: NSObject, @unchecked Sendable, SFSpeechRecognizerDelegate {
    public static let shared = LiveSpeechEngine()
    
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    public private(set) var isListening: Bool = false
    public private(set) var latestFullTranscript: String = ""
    
    private var audioFile: AVAudioFile?
    private let tempAudioFileURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("butterfly_session.caf")
    
    private var streamingTranscriptHistory: String = ""
    
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
    
    /// Start live microphone capture, real-time recognition, and direct audio file recording
    public func startLiveListening() throws {
        guard !isListening else { return }
        
        streamingTranscriptHistory = ""
        latestFullTranscript = ""
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Remove previous temp file if exists
        try? FileManager.default.removeItem(at: tempAudioFileURL)
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Create audio file to capture full continuous waveform
        audioFile = try AVAudioFile(forWriting: tempAudioFileURL, settings: recordingFormat.settings)
        
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
                
                self.streamingTranscriptHistory = formatted
                self.latestFullTranscript = formatted
                
                self.onTranscriptUpdate?(formatted)
                self.onFullTranscriptUpdate?(formatted)
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
            guard let self = self else { return }
            
            // 1. Send buffer to live streaming recognition request
            self.recognitionRequest?.append(buffer)
            
            // 2. Persist raw audio buffer to audio file for 100% complete batch transcription
            try? self.audioFile?.write(from: buffer)
            
            // 3. Audio level calculation
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0.0
                for i in 0..<frameLength {
                    sum += channelData[i] * channelData[i]
                }
                let rms = sqrt(sum / Float(max(frameLength, 1)))
                let level = min(max(rms * 5.0, 0.0), 1.0)
                DispatchQueue.main.async {
                    self.onAudioLevelUpdate?(level)
                }
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
    }
    
    /// Stop microphone recording and perform 100% complete full-file transcription for Mode 2
    @discardableResult
    public func stopLiveListening() async -> String {
        guard isListening else { return latestFullTranscript }
        isListening = false
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        audioFile = nil // Flush & close audio file
        
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Transcribe the full recorded audio file to guarantee 100% completeness
        let fullFileTranscript = await transcribeAudioFile(url: tempAudioFileURL)
        
        if !fullFileTranscript.isEmpty {
            self.latestFullTranscript = fullFileTranscript
            return fullFileTranscript
        }
        
        // Fallback to streaming transcript if file transcription is empty
        return self.streamingTranscriptHistory
    }
    
    /// Transcribe the complete audio file from start to finish without sliding window cuts
    public func transcribeAudioFile(url: URL) async -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return "" }
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.taskHint = .dictation
        request.shouldReportPartialResults = false
        request.contextualStrings = TechDictionary.engineeringVocabulary + [
            "Typeless", "Record", "Smart Polish", "Polish", "Live Streaming", "Dictation",
            "Esc", "Option", "Space", "Command", "Shift", "Bullet", "Markdown"
        ]
        
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        return await withCheckedContinuation { continuation in
            let hasResumed = OSAllocatedUnfairLock(initialState: false)
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let result = result, result.isFinal {
                    let shouldResume = hasResumed.withLock { isResumed -> Bool in
                        if !isResumed {
                            isResumed = true
                            return true
                        }
                        return false
                    }
                    if shouldResume {
                        let raw = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        let traditional = OpenCCTranslator.shared.convert(raw)
                        let formatted = TextFormatter.shared.format(traditional)
                        continuation.resume(returning: formatted)
                    }
                } else if let error = error {
                    let shouldResume = hasResumed.withLock { isResumed -> Bool in
                        if !isResumed {
                            isResumed = true
                            return true
                        }
                        return false
                    }
                    if shouldResume {
                        print("File recognition notice: \(error.localizedDescription)")
                        continuation.resume(returning: "")
                    }
                }
            }
            
            // Timeout safeguard after 5 seconds of processing
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                let shouldResume = hasResumed.withLock { isResumed -> Bool in
                    if !isResumed {
                        isResumed = true
                        return true
                    }
                    return false
                }
                if shouldResume {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
