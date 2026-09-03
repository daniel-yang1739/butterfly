import Foundation
import os
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Real-time live microphone speech recognition engine with authentic single-source transcription
public final class LiveSpeechEngine: NSObject, @unchecked Sendable, SFSpeechRecognizerDelegate {
    public static let shared = LiveSpeechEngine()
    
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    public private(set) var isListening: Bool = false
    public var latestFullTranscript: String = ""
    
    private struct TranscriptState: Sendable {
        var committed: [String] = []
        var active: String = ""
        var full: String = ""
    }
    private let stateLock = OSAllocatedUnfairLock(initialState: TranscriptState())
    
    public var onTranscriptUpdate: (@Sendable (String) -> Void)?
    public var onFullTranscriptUpdate: (@Sendable (String) -> Void)?
    public var onAudioLevelUpdate: (@Sendable (Float) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?
    
    public override init() {
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
        self.speechRecognizer?.delegate = self
    }
    
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
    
    /// Start live microphone capture and continuous speech recognition
    public func startLiveListening() throws {
        guard !isListening else { return }
        
        stateLock.withLock { state in
            state.committed.removeAll()
            state.active = ""
            state.full = ""
        }
        latestFullTranscript = ""
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        audioEngine.reset()
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw ButterflyError.audioCaptureFailed("Failed to create speech recognition request")
        }
        
        recognitionRequest.taskHint = .dictation
        recognitionRequest.contextualStrings = TechDictionary.engineeringVocabulary + [
            "System Prompt", "Prompt", "Typeless", "Record", "Smart Polish", "Polish",
            "Live Streaming", "Dictation", "Speech-to-Text", "Context", "Local", "Source Code",
            "Hardcode", "Whitelist", "Blacklist", "Esc", "Option", "Space", "Command",
            "Shift", "Bullet", "Markdown", "MB", "GB", "TB", "kg", "Mode 1", "Mode 2"
        ]
        
        if #available(macOS 13.0, *) {
            recognitionRequest.addsPunctuation = true
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let raw = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return }
                
                let traditional = OpenCCTranslator.shared.convert(raw)
                let formatted = TextPolisher.shared.polish(traditional, mode: .liveStream)
                
                let currentFull = self.stateLock.withLock { state -> String in
                    if result.isFinal {
                        state.committed.append(formatted)
                        state.active = ""
                    } else {
                        state.active = formatted
                    }
                    
                    var all = state.committed
                    if !state.active.isEmpty {
                        all.append(state.active)
                    }
                    state.full = all.joined(separator: "，")
                    return state.full
                }
                
                self.latestFullTranscript = currentFull
                self.onTranscriptUpdate?(formatted)
                self.onFullTranscriptUpdate?(currentFull)
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
        guard isListening else {
            return stateLock.withLock { $0.full }
        }
        isListening = false
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        
        // 200ms grace period for final recognition callback
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let completeMonologue = stateLock.withLock { state -> String in
            var all = state.committed
            if !state.active.isEmpty {
                all.append(state.active)
            }
            state.full = all.joined(separator: "，")
            return state.full
        }
        
        latestFullTranscript = completeMonologue
        return completeMonologue
    }
}
