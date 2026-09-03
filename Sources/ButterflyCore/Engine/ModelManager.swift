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
        self.formattedSize = sizeBytes > 0 ? ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) : "Built-in"
        self.downloadURL = downloadURL
        self.recommendedHardware = recommendedHardware
        self.description = description
    }
}

/// Local model manager, cache manager, and platform hardware detector
public final class ModelManager: @unchecked Sendable {
    public static let shared = ModelManager()
    
    /// Whitelist sorted by strength from STRONGEST (Rank 1) to WEAKEST fallback (Rank 6)
    public static let prioritizedWhitelist: [ModelSpec] = [
        ModelSpec(
            id: "whisper-large-v3-turbo",
            displayName: "Whisper Large-v3-Turbo (Flagship)",
            parameterCount: "809M",
            sizeBytes: 809 * 1024 * 1024,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"),
            recommendedHardware: .appleNeuralEngine,
            description: "Rank 1: State-of-the-art flagship accuracy (809 MB), highest precision for complex speech"
        ),
        ModelSpec(
            id: "whisper-small",
            displayName: "Whisper Small (Code-Switching)",
            parameterCount: "244M",
            sizeBytes: 466 * 1024 * 1024,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"),
            recommendedHardware: .appleNeuralEngine,
            description: "Rank 2: High accuracy (466 MB), optimized for mixed Chinese-English programming jargon"
        ),
        ModelSpec(
            id: "sensevoice-small",
            displayName: "SenseVoice Small (FunASR)",
            parameterCount: "234M",
            sizeBytes: 220 * 1024 * 1024,
            downloadURL: URL(string: "https://huggingface.co/FunAudioLLM/SenseVoiceSmall/resolve/main/model.onnx"),
            recommendedHardware: .metalGPU,
            description: "Rank 3: Ultra-low latency (<0.03s, 220 MB) fast Chinese/English speech recognition"
        ),
        ModelSpec(
            id: "whisper-base",
            displayName: "Whisper Base (Balanced)",
            parameterCount: "74M",
            sizeBytes: 142 * 1024 * 1024,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"),
            recommendedHardware: .metalGPU,
            description: "Rank 4: Balanced everyday dictation (142 MB)"
        ),
        ModelSpec(
            id: "whisper-tiny",
            displayName: "Whisper Tiny (Lightweight)",
            parameterCount: "39M",
            sizeBytes: 75 * 1024 * 1024,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"),
            recommendedHardware: .metalGPU,
            description: "Rank 5: Ultra lightweight (75 MB), low latency"
        ),
        ModelSpec(
            id: "apple-speech-native",
            displayName: "Apple Speech (Native Fallback)",
            parameterCount: "Built-in",
            sizeBytes: 0,
            downloadURL: nil,
            recommendedHardware: .appleNeuralEngine,
            description: "Rank 6: Apple Silicon built-in baseline fallback (0 MB, instantaneous)"
        )
    ]
    
    public static var defaultModels: [ModelSpec] {
        return prioritizedWhitelist
    }
    
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
    
    /// Returns the highest-ranked (strongest) model available locally in the cache.
    /// Scans the whitelist from Rank 1 down to Rank 6.
    public func getBestAvailableModel() -> ModelSpec {
        for model in ModelManager.prioritizedWhitelist {
            if model.id == "apple-speech-native" {
                continue
            }
            if isModelDownloaded(model) {
                return model
            }
        }
        // Baseline fallback (Apple Speech Native)
        return ModelManager.prioritizedWhitelist.last!
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
        
        let destinationURL = localPath(for: spec)
        let temporaryURL = cacheDirectory.appendingPathComponent("\(destinationURL.lastPathComponent).downloading")
        
        // Remove existing temp file if any
        try? FileManager.default.removeItem(at: temporaryURL)
        
        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 300 // 5 minute timeout for large models
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ButterflyError.networkError("Server returned HTTP \(statusCode)")
        }
        
        let expectedLength = response.expectedContentLength
        var receivedLength: Int64 = 0
        
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: temporaryURL)
        
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        
        for try await byte in bytes {
            buffer.append(byte)
            receivedLength += 1
            
            if buffer.count >= 64 * 1024 {
                fileHandle.write(buffer)
                buffer.removeAll(keepingCapacity: true)
                
                if expectedLength > 0 {
                    let progressFraction = Double(receivedLength) / Double(expectedLength)
                    progress?(progressFraction)
                }
            }
        }
        
        if !buffer.isEmpty {
            fileHandle.write(buffer)
        }
        
        try fileHandle.close()
        
        // Atomically replace destination file
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        
        progress?(1.0)
        return destinationURL
    }
    
    /// Delete a downloaded model from the cache directory
    public func deleteModel(_ spec: ModelSpec) throws {
        guard spec.id != "apple-speech-native" else { return }
        let path = localPath(for: spec)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
    
    /// Clear all cached models from disk
    public func clearAllCache() throws {
        let contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for file in contents {
            try FileManager.default.removeItem(at: file)
        }
    }
    
    /// Calculate total bytes of all cached models
    public func getTotalCacheSizeBytes() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for url in contents {
            if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = resources.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    /// Detect available Apple Silicon / hardware accelerators
    public func detectPlatformHardware() -> HardwareAccelerator {
        #if arch(arm64)
        return .appleNeuralEngine
        #else
        return .cpu
        #endif
    }
}
