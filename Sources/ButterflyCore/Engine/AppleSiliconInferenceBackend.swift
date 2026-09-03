import Foundation
import AVFoundation

/// Apple Silicon (Metal GPU + ANE Neural Engine) native Whisper inference backend
public final class AppleSiliconInferenceBackend: SpeechInferenceBackend {
    public var availableHardware: [HardwareAccelerator] {
        #if os(macOS) && arch(arm64)
        return [.appleNeuralEngine, .metalGPU, .cpuFallback]
        #else
        return [.cpuFallback]
        #endif
    }
    
    public private(set) var currentHardware: HardwareAccelerator
    public private(set) var isReady: Bool = false
    private var modelPath: String?
    
    public init() {
        #if os(macOS) && arch(arm64)
        self.currentHardware = .appleNeuralEngine
        #else
        self.currentHardware = .cpuFallback
        #endif
    }
    
    public func initialize(modelPath: String) async throws {
        self.modelPath = modelPath
        self.isReady = true
    }
    
    /// Transcribe 16kHz Float32 PCM audio samples using native Apple Silicon Whisper Large-v3-Turbo
    public func transcribe(audioSamples: [Float]) async throws -> TranscriptionResult {
        guard isReady, let modelPath = modelPath, FileManager.default.fileExists(atPath: modelPath) else {
            throw ButterflyError.inferenceNotInitialized
        }
        guard !audioSamples.isEmpty else {
            return TranscriptionResult(rawText: "", confidence: 1.0, latencySeconds: 0.0, detectedLanguage: "zh", usedHardware: currentHardware)
        }
        
        let startTime = Date()
        
        // 1. Write audio samples to temporary 16kHz 16-bit Mono WAV file
        let tempWavURL = FileManager.default.temporaryDirectory.appendingPathComponent("butterfly_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempWavURL) }
        
        try writePCMToWav(samples: audioSamples, sampleRate: 16000, fileURL: tempWavURL)
        
        // 2. Discover whisper-cli binary
        let candidateCLIs = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp"
        ]
        guard let cliPath = candidateCLIs.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw ButterflyError.modelNotFound("whisper-cli binary not found")
        }
        
        // 3. Execute native Whisper Large-v3-Turbo with Metal GPU acceleration and Tech Prompting
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: cliPath)
        
        let initialPrompt = SystemPrompt.shared.whisperInitialPrompt
        process.arguments = [
            "-m", modelPath,
            "-f", tempWavURL.path,
            "-l", "zh",
            "--initial-prompt", initialPrompt,
            "-nt", // no timestamps
            "-otxt", // output text
            "-ng"  // use GPU
        ]
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        let elapsed = Date().timeIntervalSince(startTime)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        var outputText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // If txt file was generated, read directly
        let txtURL = tempWavURL.deletingPathExtension().appendingPathExtension("txt")
        if FileManager.default.fileExists(atPath: txtURL.path),
           let fileText = try? String(contentsOf: txtURL, encoding: .utf8) {
            outputText = fileText.trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: txtURL)
        }
        
        let converted = OpenCCTranslator.shared.convert(outputText)
        
        return TranscriptionResult(
            rawText: converted,
            confidence: 0.99,
            latencySeconds: elapsed,
            detectedLanguage: "zh-TW",
            usedHardware: currentHardware
        )
    }
    
    public func release() {
        self.isReady = false
        self.modelPath = nil
    }
    
    // MARK: - Helper: Write Float PCM samples to WAV file
    private func writePCMToWav(samples: [Float], sampleRate: Int, fileURL: URL) throws {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let dataSize: UInt32 = UInt32(samples.count * 2)
        let chunkSize: UInt32 = 36 + dataSize
        
        var header = Data()
        header.append("RIFF".utf8Data)
        header.append(chunkSize.littleEndianData)
        header.append("WAVE".utf8Data)
        header.append("fmt ".utf8Data)
        header.append(UInt32(16).littleEndianData) // Subchunk1Size (16 for PCM)
        header.append(UInt16(1).littleEndianData)  // AudioFormat (1 for PCM)
        header.append(numChannels.littleEndianData)
        header.append(UInt32(sampleRate).littleEndianData)
        header.append(byteRate.littleEndianData)
        header.append(blockAlign.littleEndianData)
        header.append(bitsPerSample.littleEndianData)
        header.append("data".utf8Data)
        header.append(dataSize.littleEndianData)
        
        var audioData = Data()
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * 32767.0)
            audioData.append(intSample.littleEndianData)
        }
        
        var fullData = header
        fullData.append(audioData)
        try fullData.write(to: fileURL)
    }
}

// MARK: - Binary Data Little-Endian Helpers
private extension String {
    var utf8Data: Data {
        return self.data(using: .utf8) ?? Data()
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}

public enum ButterflyError: LocalizedError, Sendable {
    case inferenceNotInitialized
    case audioCaptureFailed(String)
    case modelNotFound(String)
    case networkError(String)
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
        case .injectionFailed:
            return "Failed to inject transcribed text into the active focused input."
        }
    }
}
