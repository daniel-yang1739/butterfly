import Foundation
import CButterflyWhisper
import os

/// Persistent native whisper.cpp inference backend with optional Core ML encoder acceleration.
public final class AppleSiliconInferenceBackend: SpeechInferenceBackend, @unchecked Sendable {
    public var availableHardware: [HardwareAccelerator] {
        #if os(macOS) && arch(arm64)
        return [.appleNeuralEngineAndMetalGPU, .appleNeuralEngine, .metalGPU, .cpuFallback]
        #else
        return [.cpuFallback]
        #endif
    }

    public var currentHardware: HardwareAccelerator {
        stateLock.withLock { $0.hardware }
    }

    public var isReady: Bool {
        stateLock.withLock { $0.isReady }
    }

    private struct RuntimeState: Sendable {
        var hardware: HardwareAccelerator
        var isReady = false
    }

    private let stateLock: OSAllocatedUnfairLock<RuntimeState>
    private let inferenceQueue = DispatchQueue(label: "com.butterfly.whisper.inference", qos: .userInitiated)
    private var context: OpaquePointer?
    
    public init() {
        #if os(macOS) && arch(arm64)
        // Standard whisper.cpp builds use Metal by default. ANE use is only
        // reported after the process confirms that a Core ML encoder loaded.
        self.stateLock = OSAllocatedUnfairLock(initialState: RuntimeState(hardware: .metalGPU))
        #else
        self.stateLock = OSAllocatedUnfairLock(initialState: RuntimeState(hardware: .cpuFallback))
        #endif
    }
    
    public func initialize(modelPath: String) async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw ButterflyError.modelNotFound(modelPath)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            inferenceQueue.async { [self] in
                if let context {
                    butterfly_whisper_destroy(context)
                    self.context = nil
                }
                stateLock.withLock { $0.isReady = false }

                var errorPointer: UnsafeMutablePointer<CChar>?
                let newContext = modelPath.withCString { pathPointer in
                    butterfly_whisper_create(pathPointer, &errorPointer)
                }

                guard let newContext else {
                    let message = Self.consumeCString(errorPointer) ?? "Failed to initialize whisper.cpp"
                    continuation.resume(throwing: ButterflyError.inferenceFailed(message))
                    return
                }

                context = newContext
                stateLock.withLock { $0.isReady = true }
                continuation.resume()
            }
        }
    }

    /// Expected compiled Core ML encoder location used by whisper.cpp.
    public static func coreMLEncoderURL(forModelPath modelPath: String) -> URL {
        let modelURL = URL(fileURLWithPath: modelPath)
        let modelName = modelURL.deletingPathExtension().lastPathComponent
        return modelURL.deletingLastPathComponent()
            .appendingPathComponent("\(modelName)-encoder.mlmodelc", isDirectory: true)
    }

    public static func hasCoreMLEncoder(forModelPath modelPath: String) -> Bool {
        FileManager.default.fileExists(atPath: coreMLEncoderURL(forModelPath: modelPath).path)
    }
    
    /// Transcribe a fixed 16kHz Float32 PCM window using the already-loaded model.
    public func transcribe(audioSamples: [Float]) async throws -> TranscriptionResult {
        guard isReady else {
            throw ButterflyError.inferenceNotInitialized
        }
        guard !audioSamples.isEmpty else {
            return TranscriptionResult(rawText: "", confidence: 1.0, latencySeconds: 0.0, detectedLanguage: "zh", usedHardware: currentHardware)
        }

        let prompt = SystemPrompt.shared.whisperInitialPrompt
        return try await withCheckedThrowingContinuation { continuation in
            inferenceQueue.async { [self] in
                guard let context else {
                    continuation.resume(throwing: ButterflyError.inferenceNotInitialized)
                    return
                }

                let startTime = Date()
                var errorPointer: UnsafeMutablePointer<CChar>?
                let outputPointer = audioSamples.withUnsafeBufferPointer { sampleBuffer in
                    prompt.withCString { promptPointer in
                        butterfly_whisper_transcribe(
                            context,
                            sampleBuffer.baseAddress,
                            Int32(sampleBuffer.count),
                            promptPointer,
                            &errorPointer
                        )
                    }
                }

                guard let outputPointer else {
                    let message = Self.consumeCString(errorPointer) ?? "Whisper inference failed"
                    continuation.resume(throwing: ButterflyError.inferenceFailed(message))
                    return
                }

                let rawText = String(cString: outputPointer)
                butterfly_whisper_free_string(outputPointer)
                let converted = OpenCCTranslator.shared.convert(rawText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: TranscriptionResult(
                    rawText: converted,
                    confidence: 0.99,
                    latencySeconds: Date().timeIntervalSince(startTime),
                    detectedLanguage: "zh-TW",
                    usedHardware: currentHardware
                ))
            }
        }
    }
    
    public func release() {
        inferenceQueue.sync { [self] in
            if let context {
                butterfly_whisper_destroy(context)
                self.context = nil
            }
            stateLock.withLock { $0.isReady = false }
        }
    }

    static func detectHardware(fromWhisperDiagnostics diagnostics: String) -> HardwareAccelerator {
        let normalized = diagnostics.lowercased()
        let coreMLLoaded = normalized.contains("core ml model loaded")
        let gpuEnabled = normalized.contains("use gpu    = 1")
            || normalized.contains("use gpu = 1")

        if coreMLLoaded && gpuEnabled {
            return .appleNeuralEngineAndMetalGPU
        }
        if coreMLLoaded {
            return .appleNeuralEngine
        }
        if gpuEnabled {
            return .metalGPU
        }
        return .cpuFallback
    }

    private static func consumeCString(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        let value = String(cString: pointer)
        butterfly_whisper_free_string(pointer)
        return value
    }
}

public enum ButterflyError: LocalizedError, Sendable {
    case inferenceNotInitialized
    case audioCaptureFailed(String)
    case modelNotFound(String)
    case networkError(String)
    case inferenceFailed(String)
    case injectionFailed
    
    public var errorDescription: String? {
        switch self {
        case .inferenceNotInitialized:
            return "Inference engine is not initialized. Please load a model first."
        case .audioCaptureFailed(let reason):
            return "Microphone audio capture failed: \(reason)"
        case .modelNotFound(let path):
            return "Model file not found at path: \(path)"
        case .networkError(let reason):
            return "Network download error: \(reason)"
        case .inferenceFailed(let reason):
            return "Speech inference failed: \(reason)"
        case .injectionFailed:
            return "Failed to inject transcribed text into the active focused input."
        }
    }
}
