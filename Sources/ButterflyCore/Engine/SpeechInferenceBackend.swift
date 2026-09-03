import Foundation

/// Supported hardware accelerator chip architectures
public enum HardwareAccelerator: String, Codable, CaseIterable, Sendable {
    case appleNeuralEngine = "Apple Neural Engine (ANE)"
    case metalGPU          = "Apple Metal GPU"
    case qualcommNPU       = "Qualcomm Hexagon NPU"
    case intelOpenVINO     = "Intel AI Boost NPU"
    case directML          = "DirectML / ONNX Runtime"
    case cpuFallback       = "CPU (Fallback)"
}

/// Data capsule for transcription results
public struct TranscriptionResult: Equatable {
    public let rawText: String
    public let confidence: Float
    public let latencySeconds: Double
    public let detectedLanguage: String
    public let usedHardware: HardwareAccelerator
    
    public init(
        rawText: String,
        confidence: Float = 0.95,
        latencySeconds: Double = 0.1,
        detectedLanguage: String = "auto",
        usedHardware: HardwareAccelerator = .metalGPU
    ) {
        self.rawText = rawText
        self.confidence = confidence
        self.latencySeconds = latencySeconds
        self.detectedLanguage = detectedLanguage
        self.usedHardware = usedHardware
    }
}

/// Core inference abstraction protocol
public protocol SpeechInferenceBackend: AnyObject {
    var availableHardware: [HardwareAccelerator] { get }
    var currentHardware: HardwareAccelerator { get }
    
    func initialize(modelPath: String) async throws
    func transcribe(audioSamples: [Float]) async throws -> TranscriptionResult
    func release()
}

/// Mock inference backend for automated testing
public final class MockInferenceBackend: SpeechInferenceBackend {
    public var availableHardware: [HardwareAccelerator] = [.metalGPU, .appleNeuralEngine, .cpuFallback]
    public var currentHardware: HardwareAccelerator = .metalGPU
    
    public var mockResult: TranscriptionResult
    public var isInitialized: Bool = false
    public var transcribedSamplesHistory: [[Float]] = []
    
    public init(mockResult: TranscriptionResult = TranscriptionResult(rawText: "Mock transcription result")) {
        self.mockResult = mockResult
    }
    
    public func initialize(modelPath: String) async throws {
        self.isInitialized = true
    }
    
    public func transcribe(audioSamples: [Float]) async throws -> TranscriptionResult {
        transcribedSamplesHistory.append(audioSamples)
        return mockResult
    }
    
    public func release() {
        self.isInitialized = false
    }
}
