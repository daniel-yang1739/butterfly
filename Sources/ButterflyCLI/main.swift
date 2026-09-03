import Foundation
import ButterflyCore

print("🦋 Butterfly CLI - On-Device Real-Time Speech-to-Text & Note Polisher (Apple Silicon / NPU Optimized)")

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "listen"

switch command {
case "models":
    print("\nSupported Local Models:")
    for model in ModelManager.defaultModels {
        let downloaded = ModelManager.shared.isModelDownloaded(model) ? "Downloaded" : "Not Downloaded"
        print("  • \(model.displayName) [\(model.parameterCount) params, \(model.formattedSize)] - \(downloaded)")
        print("    Description: \(model.description)")
        print("    Recommended Accelerator: \(model.recommendedHardware.rawValue)\n")
    }

case "download":
    let modelId = args.count > 2 ? args[2] : "whisper-small"
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
    print("\nSystem Hardware & Storage Information:")
    print("  • Recommended Accelerator: \(hardware.rawValue)")
    print("  • Model Cache Directory: \(ModelManager.shared.cacheDirectory.path)")
    print("  • Total Cache Used: \(formattedTotal)")
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
    let inputText = args.dropFirst(2).joined(separator: " ")
    let testString = inputText.isEmpty ? "呃我想說就是說，我們現在有兩種模式需求，第一點就是希望像voice一樣可以即時live streaming講話邊講邊出字，然後呢第二點就是可以錄一段長音，然後按下結束之後，它會幫我把呃啊哦那些贅詞去掉，然後自動分段跟列點整理好。" : inputText
    
    print("\n[Spoken Input]:\n\(testString)")
    let liveResult = TextPolisher.shared.polish(testString, mode: .liveStream)
    print("\n[Mode 1: Live Dictation Polished]:\n\(liveResult)")
    let polishResult = TextPolisher.shared.polish(testString, mode: .structuredNote)
    print("\n[Mode 2: Smart Note Polished (Paragraphs / Bullet Points)]:\n\(polishResult)")
    print("--------------------------------------------------")

case "listen":
    let isPolishMode = args.contains("--polish")
    let modeTitle = isPolishMode ? "Mode 2: Record & Smart Polish (Paragraphs / Bullets / Filler Removal)" : "Mode 1: Live Streaming Dictation"
    print("\nStarting \(modeTitle)...")
    let liveEngine = LiveSpeechEngine.shared
    
    Task {
        let granted = await liveEngine.requestPermissions()
        if !granted {
            print("Warning: Please ensure Microphone and Speech Recognition permissions are granted in macOS System Settings.")
        }
        
        do {
            liveEngine.onTranscriptUpdate = { transcript in
                let display = isPolishMode ? transcript : TextPolisher.shared.polish(transcript, mode: .liveStream)
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
                let finalText = isPolishMode
                    ? TextPolisher.shared.polish(fullTranscript, mode: .structuredNote)
                    : TextPolisher.shared.polish(fullTranscript, mode: .liveStream)
                
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
      butterfly-cli listen            - Start Mode 1: Live streaming dictation
      butterfly-cli listen --polish   - Start Mode 2: Record & smart note polishing
      butterfly-cli test-polish       - Test text polishing, filler removal & bullet structuring
      butterfly-cli test-convert      - Test Simplified-to-Traditional conversion
      butterfly-cli models            - List supported local models and download status
      butterfly-cli download <id>     - Download a model to local cache (e.g. whisper-small)
      butterfly-cli delete <id>       - Delete a downloaded model from cache
      butterfly-cli clean             - Clear all downloaded model cache
      butterfly-cli info              - Display system hardware accelerator and storage info
    
    """)
}
