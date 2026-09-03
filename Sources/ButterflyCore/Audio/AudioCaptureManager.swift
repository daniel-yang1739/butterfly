import Foundation
import AVFoundation

/// Delegate protocol for audio capture callbacks
public protocol AudioCaptureDelegate: AnyObject {
    func audioCaptureManager(_ manager: AudioCaptureManager, didCaptureSamples samples: [Float])
    func audioCaptureManager(_ manager: AudioCaptureManager, didUpdateAudioLevel level: Float)
    func audioCaptureManager(_ manager: AudioCaptureManager, didFailWithError error: Error)
}

/// Microphone audio capture and 16kHz resampling manager
public final class AudioCaptureManager {
    public weak var delegate: AudioCaptureDelegate?
    
    public private(set) var isRecording: Bool = false
    public static let targetSampleRate: Double = 16000.0 // Standard 16kHz for Whisper / NPU
    
    private var recordedSamples: [Float] = []
    private let sampleQueue = DispatchQueue(label: "com.butterfly.audio.queue")
    
    public init() {}
    
    /// Start recording audio
    public func startRecording() throws {
        guard !isRecording else { return }
        
        recordedSamples.removeAll()
        isRecording = true
    }
    
    /// Stop recording and return the captured 16kHz PCM Float array
    public func stopRecording() -> [Float] {
        guard isRecording else { return [] }
        isRecording = false
        
        let samples = sampleQueue.sync {
            let copy = self.recordedSamples
            self.recordedSamples.removeAll()
            return copy
        }
        return samples
    }
    
    /// Append audio sample buffers (supports unit testing and hardware stream injection)
    public func appendSamples(_ samples: [Float]) {
        guard isRecording else { return }
        
        sampleQueue.async {
            self.recordedSamples.append(contentsOf: samples)
        }
        
        let level = calculateRMS(samples)
        delegate?.audioCaptureManager(self, didCaptureSamples: samples)
        delegate?.audioCaptureManager(self, didUpdateAudioLevel: level)
    }
    
    /// Calculate Root Mean Square (RMS) energy and normalized audio level
    public func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        var sum: Float = 0.0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(samples.count))
        // Normalize to 0.0 ~ 1.0 range
        return min(max(rms * 5.0, 0.0), 1.0)
    }
    
    /// Resample audio from any input sample rate to target sample rate (default 16kHz Mono Float)
    public static func resample(
        inputSamples: [Float],
        fromSampleRate: Double,
        toSampleRate: Double = 16000.0
    ) -> [Float] {
        guard fromSampleRate > 0, toSampleRate > 0 else { return inputSamples }
        if abs(fromSampleRate - toSampleRate) < 1.0 {
            return inputSamples
        }
        
        let ratio = toSampleRate / fromSampleRate
        let outputLength = Int(Double(inputSamples.count) * ratio)
        var outputSamples = [Float](repeating: 0, count: outputLength)
        
        for i in 0..<outputLength {
            let sourceIndex = Double(i) / ratio
            let indexLow = Int(floor(sourceIndex))
            let indexHigh = min(indexLow + 1, inputSamples.count - 1)
            let fraction = Float(sourceIndex - Double(indexLow))
            
            if indexLow < inputSamples.count {
                let sampleLow = inputSamples[indexLow]
                let sampleHigh = inputSamples[indexHigh]
                // Linear interpolation resampling
                outputSamples[i] = sampleLow + fraction * (sampleHigh - sampleLow)
            }
        }
        
        return outputSamples
    }
}
