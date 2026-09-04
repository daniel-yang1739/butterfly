import Foundation
import ButterflyCore

print("🦋 Butterfly CLI - On-Device Real-Time Speech-to-Text & Note Polisher (Apple Silicon / NPU Optimized)")

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "listen"

switch command {
case "test", "test-all", "test-logic":
    Task {
        await TestRunner.runAllTests()
        exit(0)
    }
    RunLoop.main.run()

case "models":
    print("\n🎙️ Speech Recognition Models (ASR Whitelist):")
    for model in ModelManager.defaultASRModels {
        let isSelected = model.id == ModelManager.shared.activeASRModel.id ? " [Active ✓]" : ""
        let downloaded = ModelManager.shared.isModelDownloaded(model) ? "Downloaded" : "Not Downloaded"
        print("  • \(model.displayName) [\(model.parameterCount), \(model.formattedSize)] - \(downloaded)\(isSelected)")
        print("    ID: \(model.id)")
        print("    Description: \(model.description)\n")
    }

case "download":
    let modelId = args.count > 2 ? args[2] : "whisper-large-v3-turbo"
    guard let spec = ModelManager.defaultModels.first(where: { $0.id == modelId }) else {
        print("Model '\(modelId)' not found. Run 'butterfly-cli models' to view available IDs.")
        exit(1)
    }
    
    if ModelManager.shared.isModelDownloaded(spec) {
        print("Model '\(spec.displayName)' is already downloaded at: \(ModelManager.shared.localPath(for: spec).path)")
        exit(0)
    }
    
    print("Downloading \(spec.displayName) (\(spec.formattedSize))...")
    Task {
        do {
            let path = try await ModelManager.shared.downloadModel(spec) { progress in
                let percent = Int(progress * 100)
                print("\r  Progress: \(percent)%               ", terminator: "")
                fflush(stdout)
            }
            print("\nDownload complete! Saved to: \(path.path)")
            exit(0)
        } catch {
            print("\nDownload failed: \(error.localizedDescription)")
            exit(1)
        }
    }
    RunLoop.main.run()

case "delete", "remove", "uninstall":
    let modelId = args.count > 2 ? args[2] : ""
    guard let spec = ModelManager.defaultModels.first(where: { $0.id == modelId }) else {
        print("Please specify a model ID to delete, e.g.: butterfly-cli delete whisper-small")
        print("Run 'butterfly-cli models' to see all IDs.")
        exit(1)
    }
    
    do {
        try ModelManager.shared.deleteModel(spec)
        print("Successfully deleted model '\(spec.displayName)' from cache.")
    } catch {
        print("Failed to delete model: \(error.localizedDescription)")
    }

case "clean", "clear-cache":
    do {
        try ModelManager.shared.clearAllCache()
        print("Successfully cleared all model files from cache directory.")
    } catch {
        print("Failed to clear cache: \(error.localizedDescription)")
    }

case "cache", "info":
    let hardware = ModelManager.shared.detectPlatformHardware()
    let totalBytes = ModelManager.shared.getTotalCacheSizeBytes()
    let formattedTotal = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    let userVocab = TechDictionary.loadUserVocabulary()
    print("\nSystem Hardware & Storage Information:")
    print("  • Default Whisper Accelerator: \(hardware.rawValue)")
    print("  • Model Cache Directory: \(ModelManager.shared.cacheDirectory.path)")
    print("  • Total Cache Used: \(formattedTotal)")
    print("  • Active Speech Model: \(ModelManager.shared.activeASRModel.displayName)")
    if ModelManager.shared.activeASRModel.id != "apple-speech-native" {
        let modelPath = ModelManager.shared.localPath(for: ModelManager.shared.activeASRModel).path
        let encoderURL = AppleSiliconInferenceBackend.coreMLEncoderURL(forModelPath: modelPath)
        let encoderStatus = AppleSiliconInferenceBackend.hasCoreMLEncoder(forModelPath: modelPath) ? "Ready" : "Missing"
        print("  • Core ML ANE Encoder: \(encoderStatus)")
        print("  • Expected Encoder Path: \(encoderURL.path)")
    }
    print("  • Custom Dictionary Path: \(TechDictionary.userDictionaryURL.path)")
    print("  • Custom Dictionary Words Loaded: \(userVocab.count) terms (\(userVocab.prefix(5).joined(separator: ", "))...)")
    print("  • Total Recognition Vocabulary: \(TechDictionary.allVocabulary.count) terms")
    print("  • Traditional Chinese Standard: OpenCC s2twp (Taiwan standard)")

case "test-convert":
    let inputText = args.dropFirst(2).joined(separator: " ")
    if inputText.isEmpty {
        print("Please provide a string to test conversion, e.g.: butterfly-cli test-convert \"服务器内存不足，请帮我review这段React代码\"")
    } else {
        let converted = OpenCCTranslator.shared.convert(inputText)
        let formatted = TextFormatter.shared.format(converted)
        print("\nConversion Test Results:")
        print("  [Input]:  \(inputText)")
        print("  [Output]: \(formatted)")
        let hasSimplified = OpenCCTranslator.shared.containsSimplified(formatted)
        print("  [Traditional Verification]: \(hasSimplified ? "Simplified characters detected" : "100% Traditional Chinese")")
    }

case "test-polish":
    let useSmartPolish = args.contains("--smart")
    let inputText = args.dropFirst(2).filter { $0 != "--smart" }.joined(separator: " ")
    let testString = inputText.isEmpty ? "好我們今天開會主要討論了三件事情，一個是關於前端游標注入的邏輯，我們要確保說輸入框不會出現雪崩效應。再來是錯字要修復像是 System Prompt 或者 Model 等詞彙我們要把它修復。第三個是排版的部分希望段落不要太碎適當的幫我列成 Markdown 清單整理好這樣謝謝。" : inputText

    if useSmartPolish {
        Task {
            print("\n[Spoken Input]:\n\(testString)")
            let result = await SmartPolishEngine.shared.polish(testString)
            let engineName = result.usedFallback ? "Rule-Based Fallback" : "Apple Foundation Models"
            print("\n[Smart Polish Output - \(engineName)]:\n\(result.text)")
            print("--------------------------------------------------")
            exit(0)
        }
        RunLoop.main.run()
    } else {
        print("\n[Spoken Input]:\n\(testString)")
        let liveResult = TextPolisher.shared.polish(testString, mode: .liveStream)
        print("\n[Live Dictation Polished]:\n\(liveResult)")
        print("--------------------------------------------------")
    }

case "listen":
    print("\nStarting Butterfly Real-Time Voice Dictation...")
    let liveEngine = LiveSpeechEngine.shared
    
    Task {
        let granted = await liveEngine.requestPermissions()
        if !granted {
            print("Warning: Please ensure Microphone and Speech Recognition permissions are granted in macOS System Settings.")
        }
        
        do {
            liveEngine.onTranscriptUpdate = { transcript in
                let display = TextPolisher.shared.polish(transcript, mode: .liveStream)
                print("\r  Transcribing: \(display)                    ", terminator: "")
                fflush(stdout)
            }
            
            liveEngine.onError = { error in
                print("\nRecognition info: \(error.localizedDescription)")
            }
            
            try liveEngine.startLiveListening()
            print("Microphone active! Speak into your computer (supports continuous multi-sentence speech)...")
            print("Press [Enter] to finish and inject into active cursor, or [Ctrl+C] to exit:\n")
            
            _ = readLine()
            
            let fullTranscript = await liveEngine.stopLiveListening()
            
            if !fullTranscript.isEmpty {
                let finalText = TextPolisher.shared.polish(fullTranscript, mode: .liveStream)
                print("\n\nFinal Polished Result:\n--------------------------------------------------\n\(finalText)\n--------------------------------------------------")
                print("Injecting into active window...")
                await InputInjector.shared.inject(text: finalText)
                print("Successfully injected!")
            } else {
                print("\n(No speech detected)")
            }
            
            exit(0)
        } catch {
            print("\nFailed to start microphone: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    RunLoop.main.run()

default:
    print("""
    
    Usage:
      butterfly-cli listen            - Start real-time live voice dictation
      butterfly-cli test              - Run complete 36-assertion automated test suite
      butterfly-cli test-polish       - Test real-time acoustic typo restoration
      butterfly-cli test-polish --smart - Test deferred Apple Intelligence polishing
      butterfly-cli test-convert      - Test Simplified-to-Traditional conversion
      butterfly-cli models            - List supported local speech recognition models
      butterfly-cli download <id>     - Download a model to local cache (e.g. whisper-large-v3-turbo)
      butterfly-cli delete <id>       - Delete a downloaded model from cache
      butterfly-cli clean             - Clear all downloaded model cache
      butterfly-cli info              - Display system hardware accelerator and storage info
    
    """)
}
