import Foundation

/// Voice Activity Detection (VAD) events
public enum VADEvent: Equatable {
    case speechStarted
    case speechOngoing(level: Float)
    case speechEnded(durationSeconds: Double)
    case silenceTimeout
}

public protocol VADDetectorDelegate: AnyObject {
    func vadDetector(_ detector: VADDetector, didEmitEvent event: VADEvent)
}

/// Voice Activity Detector for evaluating speech start and end boundaries
public final class VADDetector {
    public weak var delegate: VADDetectorDelegate?
    
    public var energyThreshold: Float = 0.02 // Silence energy threshold
    public var silenceDurationThreshold: TimeInterval = 0.8 // 800ms silence considered end of speech
    public var maxSpeechDuration: TimeInterval = 30.0 // Max 30s per speech segment
    
    private var isSpeaking: Bool = false
    private var speechStartTime: Date?
    private var lastSpeechTime: Date?
    
    public init(
        energyThreshold: Float = 0.02,
        silenceDurationThreshold: TimeInterval = 0.8
    ) {
        self.energyThreshold = energyThreshold
        self.silenceDurationThreshold = silenceDurationThreshold
    }
    
    public func reset() {
        isSpeaking = false
        speechStartTime = nil
        lastSpeechTime = nil
    }
    
    /// Process incoming audio level frame and evaluate speech transitions
    public func processAudioLevel(_ level: Float, at time: Date = Date()) {
        if level >= energyThreshold {
            // Speech detected
            if !isSpeaking {
                isSpeaking = true
                speechStartTime = time
                delegate?.vadDetector(self, didEmitEvent: .speechStarted)
            }
            lastSpeechTime = time
            delegate?.vadDetector(self, didEmitEvent: .speechOngoing(level: level))
        } else {
            // Silence
            if isSpeaking, let lastSpeech = lastSpeechTime {
                let silenceDuration = time.timeIntervalSince(lastSpeech)
                if silenceDuration >= silenceDurationThreshold {
                    isSpeaking = false
                    let totalDuration = time.timeIntervalSince(speechStartTime ?? time)
                    delegate?.vadDetector(self, didEmitEvent: .speechEnded(durationSeconds: totalDuration))
                }
            }
        }
        
        // Timeout check
        if isSpeaking, let start = speechStartTime, time.timeIntervalSince(start) >= maxSpeechDuration {
            isSpeaking = false
            delegate?.vadDetector(self, didEmitEvent: .silenceTimeout)
        }
    }
}
