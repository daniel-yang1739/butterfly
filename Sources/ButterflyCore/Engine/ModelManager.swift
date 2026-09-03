import Foundation

/// Specification definition for on-device ASR models
public struct ModelSpec: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let parameterCount: String
    public let sizeBytes: Int64
    public let formattedSize: String
    public let downloadURL: URL?
    public let recommendedHardware: HardwareAccelerator
    public let description: String
    
    public init(
        id: String,
        displayName: String,
        parameterCount: String,
        sizeBytes: Int64,
        downloadURL: URL?,
        recommendedHardware: HardwareAccelerator,
        description: String
    ) {
        self.id = id
        self.displayName = displayName
        self.parameterCount = parameterCount
        self.sizeBytes = sizeBytes
        self.formattedSize = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        self.downloadURL = downloadURL
        self.recommendedHardware = recommendedHardware
        self.description = description
    }
}

/// Local model manager, cache manager, and platform hardware detector
public final class ModelManager: @unchecked Sendable {
    public static let shared = ModelManager()
    
    public static let defaultModels: [ModelSpec] = [
        ModelSpec(
            id: "apple-speech-native",
            displayName: "Apple Speech (Native On-Device)",
            parameterCount: "Built-in",
            sizeBytes: 0,
            downloadURL: nil,
            recommendedHardware: .appleNeuralEngine,
            description: "Apple Silicon built-in on-device dictation engine (0 MB, instantaneous)"
        ),
        ModelSpec(
            id: "whisper-tiny",
            displayName: "Whisper Tiny (OpenAI)",
            parameterCount: "39M",
            sizeBytes: 75 * 1024 * 1024,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"),
            recommendedHardware: .metalGPU,
            description: "Ultra lightweight (75 MB), ideal for fast commands and low latency"
        ),
        ModelSpec(
            id: "whisper-base",
            displayName: "Whisper Base (OpenAI)",
            parameterCount: "74M",
            sizeBytes: 142 * 1024 * 1024,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"),
            recommendedHardware: .metalGPU,
            description: "Lightweight (142 MB), balanced for everyday dictation and phrases"
        ),
        ModelSpec(
            id: "whisper-small",
            displayName: "Whisper Small (OpenAI - Code-Switching)",
            parameterCount: "244M",
            sizeBytes: 466 * 1024 * 1024,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"),
            recommendedHardware: .appleNeuralEngine,
            description: "High accuracy (466 MB), excellent for mixed Chinese-English programming jargon"
        ),
        ModelSpec(
            id: "whisper-large-v3-turbo",
            displayName: "Whisper Large-v3-Turbo (Flagship)",
            parameterCount: "809M",
            sizeBytes: 809 * 1024 * 1024,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"),
            recommendedHardware: .appleNeuralEngine,
            description: "Top-tier flagship accuracy (809 MB), state-of-the-art multilingual recognition"
        ),
        ModelSpec(
            id: "sensevoice-small",
            displayName: "SenseVoice Small (FunASR)",
            parameterCount: "234M",
            sizeBytes: 220 * 1024 * 1024,
            downloadURL: URL(string: "https://huggingface.co/FunAudioLLM/SenseVoiceSmall/resolve/main/model.onnx"),
            recommendedHardware: .metalGPU,
            description: "Ultra-low latency (<0.03s, 220 MB) multilingual fast speech recognition"
        )
    ]
    
    public let cacheDirectory: URL
    
    public init(customCacheDir: URL? = nil) {
        if let customCacheDir = customCacheDir {
            self.cacheDirectory = customCacheDir
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.cacheDirectory = home.appendingPathComponent(".cache/butterfly/models", isDirectory: true)
        }
        
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Get the local cache file path for a model specification
    public func localPath(for spec: ModelSpec) -> URL {
        let filename = spec.downloadURL?.lastPathComponent ?? "\(spec.id).bin"
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    /// Check if a model is downloaded locally
    public func isModelDownloaded(_ spec: ModelSpec) -> Bool {
        if spec.id == "apple-speech-native" {
            return true
        }
        let path = localPath(for: spec)
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    /// Download a model specification to local cache directory with progress reporting
    public func downloadModel(_ spec: ModelSpec, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        guard let downloadURL = spec.downloadURL else {
            if spec.id == "apple-speech-native" {
                return cacheDirectory
            }
            throw ButterflyError.modelNotFound("No download URL provided for model \(spec.id)")
        }
        
        let destination = localPath(for: spec)
        if isModelDownloaded(spec) {
            progress?(1.0)
            return destination
        }
        
        let session = URLSession.shared
        let (asyncBytes, response) = try await session.bytes(from: downloadURL)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ButterflyError.networkError("Failed to download model from \(downloadURL)")
        }
        
        let totalBytes = response.expectedContentLength > 0 ? response.expectedContentLength : spec.sizeBytes
        let tempDestination = destination.deletingLastPathComponent().appendingPathComponent("\(spec.id).downloading")
        
        try? FileManager.default.removeItem(at: tempDestination)
        FileManager.default.createFile(atPath: tempDestination.path, contents: nil)
        
        guard let fileHandle = try? FileHandle(forWritingTo: tempDestination) else {
            throw ButterflyError.networkError("Failed to create temporary file for \(spec.displayName)")
        }
        
        var bytesWritten: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(65536)
        
        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 65536 {
                try fileHandle.write(contentsOf: buffer)
                bytesWritten += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                
                if totalBytes > 0 {
                    let currentProgress = min(Double(bytesWritten) / Double(totalBytes), 1.0)
                    progress?(currentProgress)
                }
            }
        }
        
        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
            bytesWritten += Int64(buffer.count)
        }
        try fileHandle.close()
        
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempDestination, to: destination)
        
        progress?(1.0)
        return destination
    }
    
    /// Delete / Uninstall a cached model from local disk
    public func deleteModel(_ spec: ModelSpec) throws {
        guard spec.id != "apple-speech-native" else { return }
        let path = localPath(for: spec)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
    
    /// Clear all downloaded models in the cache directory
    public func clearAllCache() throws {
        let contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for file in contents {
            try FileManager.default.removeItem(at: file)
        }
    }
    
    /// Calculate the total size of all cached models
    public func getTotalCacheSizeBytes() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for file in contents {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }
    
    /// Detect the current operating platform and optimal hardware accelerator
    public func detectPlatformHardware() -> HardwareAccelerator {
        #if os(macOS)
        #if arch(arm64)
        return .appleNeuralEngine // Apple Silicon M-series with ANE and Metal GPU
        #else
        return .cpuFallback // Intel Mac
        #endif
        #elseif os(Windows)
        return .directML // Windows DirectML / QNN
        #elseif os(Linux)
        return .cpuFallback
        #else
        return .cpuFallback
        #endif
    }
}
