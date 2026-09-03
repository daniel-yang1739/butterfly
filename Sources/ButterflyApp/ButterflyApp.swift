import AppKit
import SwiftUI
import ButterflyCore

/// Operating mode for Butterfly
public enum ButterflyMode: String, CaseIterable {
    case liveStreaming = "live"       // Mode 1: Live Streaming Dictation (real-time live typing into cursor)
    case recordAndPolish = "polish"   // Mode 2: Record & Smart Polish (deep filler cleaning, paragraphs, bullet points on Esc)
    
    public var title: String {
        switch self {
        case .liveStreaming:
            return "Live Streaming Dictation"
        case .recordAndPolish:
            return "Record & Smart Polish"
        }
    }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isRecording: Bool = false
    private var isDownloadingModel: Bool = false
    private var activeMode: ButterflyMode = .liveStreaming
    private var activeModelSpec: ModelSpec = ModelManager.shared.getBestAvailableModel()
    
    private var streamingInjectedText: String = ""
    private var latestTranscript: String = ""
    private let liveEngine = LiveSpeechEngine.shared
    private var globalEventMonitor: Any?
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        setupGlobalHotkey()
        
        // Listen for live speech recognition updates
        liveEngine.onTranscriptUpdate = { [weak self] formattedText in
            Task { @MainActor in
                guard let self = self, self.isRecording else { return }
                self.latestTranscript = formattedText
                
                if self.activeMode == .liveStreaming {
                    // Mode 1: Direct real-time streaming typing into active focused cursor (Append-Only)
                    InputInjector.shared.injectStreamingDelta(
                        newText: formattedText,
                        previousText: &self.streamingInjectedText
                    )
                    
                    let preview = formattedText.count > 12 ? "..." + String(formattedText.suffix(12)) : formattedText
                    self.statusItem.button?.title = " 🎙️ \(preview)"
                } else {
                    // Mode 2: Record audio quietly and display preview in menu bar
                    let preview = formattedText.count > 12 ? "..." + String(formattedText.suffix(12)) : formattedText
                    self.statusItem.button?.title = " 🔴 \(preview)"
                }
            }
        }
        
        liveEngine.onError = { error in
            Task { @MainActor in
                print("Recognition Engine Info: \(error.localizedDescription)")
            }
        }
        
        print("""
        
        Butterfly macOS native desktop app successfully started!
        --------------------------------------------------
        Look for the Butterfly icon in your top menu bar.
        
        Global Hotkeys:
          • [Option + Space]         -> Start Live Streaming Dictation (type live as you speak)
          • [Option + Shift + Space] -> Start Record & Smart Polish (auto-structured notes)
          • [Enter] / [Esc]          -> Stop & Finalize (First Enter stops recording, Second Enter sends)
        
        Active Model: \(activeModelSpec.displayName)
        Model Cache Path: \(ModelManager.shared.cacheDirectory.path)
        Click the Butterfly menu bar icon to switch or manage models.
        --------------------------------------------------
        
        """)
    }
    
    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            // Load native high-contrast white outline template image for macOS menu bar
            let fileManager = FileManager.default
            let candidatePaths = [
                "docs/assets/menu_bar_icon.png",
                "docs/assets/menu_bar_icon@2x.png",
                URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("docs/assets/menu_bar_icon.png").path,
                URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("docs/assets/menu_bar_icon@2x.png").path,
                fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".cache/butterfly/assets/menu_bar_icon.png").path
            ]
            
            var loadedImage: NSImage? = nil
            for path in candidatePaths {
                if fileManager.fileExists(atPath: path), let img = NSImage(contentsOfFile: path) {
                    img.size = NSSize(width: 22, height: 22)
                    img.isTemplate = true
                    loadedImage = img
                    break
                }
            }
            
            if let img = loadedImage {
                button.image = img
                button.imagePosition = .imageLeft
                button.title = ""
            } else {
                button.title = "🦋"
            }
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        updateMenu()
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "Butterfly Voice Input", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        if isRecording {
            let stopItem = NSMenuItem(
                title: "Stop & Finalize (Enter / Esc)",
                action: #selector(stopCurrentRecording),
                keyEquivalent: "\r"
            )
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let liveItem = NSMenuItem(
                title: "Start Live Streaming (Option+Space)",
                action: #selector(startLiveStreamingMode),
                keyEquivalent: ""
            )
            liveItem.target = self
            menu.addItem(liveItem)
            
            let polishItem = NSMenuItem(
                title: "Start Record & Polish (Option+Shift+Space)",
                action: #selector(startRecordAndPolishMode),
                keyEquivalent: ""
            )
            polishItem.target = self
            menu.addItem(polishItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Mode preference submenu
        let modeMenu = NSMenu()
        for mode in ButterflyMode.allCases {
            let item = NSMenuItem(
                title: (mode == activeMode ? "✓ " : "  ") + mode.title,
                action: #selector(selectDefaultMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode
            modeMenu.addItem(item)
        }
        let modeParentItem = NSMenuItem(title: "Default Input Mode", action: nil, keyEquivalent: "")
        modeParentItem.submenu = modeMenu
        menu.addItem(modeParentItem)
        
        // Local models selector submenu (Interactive Model Switcher)
        let modelMenu = NSMenu()
        for model in ModelManager.defaultModels {
            let isSelected = model.id == activeModelSpec.id
            let isDownloaded = ModelManager.shared.isModelDownloaded(model)
            
            let selectionMark = isSelected ? "● " : "   "
            let downloadStatus = isDownloaded ? " [Downloaded]" : " [Click to Download]"
            let sizeDesc = model.sizeBytes > 0 ? " (\(model.formattedSize))" : " (Built-in)"
            
            let itemTitle = "\(selectionMark)\(model.displayName)\(sizeDesc)\(downloadStatus)"
            let modelItem = NSMenuItem(
                title: itemTitle,
                action: #selector(selectModelSpec(_:)),
                keyEquivalent: ""
            )
            modelItem.target = self
            modelItem.representedObject = model
            modelMenu.addItem(modelItem)
        }
        let modelParentItem = NSMenuItem(title: "Active Model: \(activeModelSpec.displayName)", action: nil, keyEquivalent: "")
        modelParentItem.submenu = modelMenu
        menu.addItem(modelParentItem)
        
        // Manage Model Storage & Uninstall Submenu
        let cacheMenu = NSMenu()
        let downloadedModels = ModelManager.defaultModels.filter { $0.id != "apple-speech-native" && ModelManager.shared.isModelDownloaded($0) }
        
        if downloadedModels.isEmpty {
            let emptyItem = NSMenuItem(title: "No downloaded models in cache", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            cacheMenu.addItem(emptyItem)
        } else {
            for downloaded in downloadedModels {
                let deleteItem = NSMenuItem(
                    title: "🗑️ Delete \(downloaded.displayName) (\(downloaded.formattedSize))",
                    action: #selector(uninstallModel(_:)),
                    keyEquivalent: ""
                )
                deleteItem.target = self
                deleteItem.representedObject = downloaded
                cacheMenu.addItem(deleteItem)
            }
            cacheMenu.addItem(NSMenuItem.separator())
            
            let totalBytes = ModelManager.shared.getTotalCacheSizeBytes()
            let formattedTotal = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            let clearAllItem = NSMenuItem(
                title: "🧹 Delete All Cached Models (\(formattedTotal))",
                action: #selector(clearAllModelCache),
                keyEquivalent: ""
            )
            clearAllItem.target = self
            cacheMenu.addItem(clearAllItem)
        }
        
        cacheMenu.addItem(NSMenuItem.separator())
        let openFolderItem = NSMenuItem(
            title: "📂 Open Models Folder in Finder",
            action: #selector(openModelsFolderInFinder),
            keyEquivalent: ""
        )
        openFolderItem.target = self
        cacheMenu.addItem(openFolderItem)
        
        let cacheParentItem = NSMenuItem(title: "Manage Model Storage", action: nil, keyEquivalent: "")
        cacheParentItem.submenu = cacheMenu
        menu.addItem(cacheParentItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Butterfly", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        statusItem.button?.performClick(nil)
    }
    
    @objc private func selectDefaultMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? ButterflyMode {
            self.activeMode = mode
            updateMenu()
        }
    }
    
    @objc private func selectModelSpec(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? ModelSpec else { return }
        
        if ModelManager.shared.isModelDownloaded(spec) {
            self.activeModelSpec = spec
            updateMenu()
            print("Butterfly: Switched active model to \(spec.displayName)")
            return
        }
        
        guard !isDownloadingModel else { return }
        isDownloadingModel = true
        
        Task { @MainActor in
            self.statusItem.button?.title = " ⏳ Downloading..."
            
            do {
                _ = try await ModelManager.shared.downloadModel(spec) { progress in
                    Task { @MainActor in
                        let percentage = Int(progress * 100)
                        self.statusItem.button?.title = " ⏳ \(percentage)%"
                    }
                }
                
                self.activeModelSpec = spec
                self.isDownloadingModel = false
                self.statusItem.button?.title = " ✅ Ready!"
                self.updateMenu()
                print("Butterfly: Model \(spec.displayName) downloaded successfully!")
                
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.statusItem.button?.title = ""
            } catch {
                self.isDownloadingModel = false
                self.statusItem.button?.title = " ⚠️ Failed"
                print("Failed to download model: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.statusItem.button?.title = ""
                self.updateMenu()
            }
        }
    }
    
    @objc private func uninstallModel(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? ModelSpec else { return }
        do {
            try ModelManager.shared.deleteModel(spec)
            if activeModelSpec.id == spec.id {
                activeModelSpec = ModelManager.shared.getBestAvailableModel()
            }
            updateMenu()
            print("Butterfly: Deleted model \(spec.displayName)")
        } catch {
            print("Failed to delete model: \(error.localizedDescription)")
        }
    }
    
    @objc private func clearAllModelCache() {
        do {
            try ModelManager.shared.clearAllCache()
            activeModelSpec = ModelManager.shared.getBestAvailableModel()
            updateMenu()
            print("Butterfly: Cleared all model cache")
        } catch {
            print("Failed to clear model cache: \(error.localizedDescription)")
        }
    }
    
    @objc private func openModelsFolderInFinder() {
        let url = ModelManager.shared.cacheDirectory
        NSWorkspace.shared.open(url)
    }
    
    @objc private func startLiveStreamingMode() {
        Task { @MainActor in
            await startListening(mode: .liveStreaming)
        }
    }
    
    @objc private func startRecordAndPolishMode() {
        Task { @MainActor in
            await startListening(mode: .recordAndPolish)
        }
    }
    
    @objc private func stopCurrentRecording() {
        Task { @MainActor in
            await stopAndInject()
        }
    }
    
    /// Start listening with specific mode
    private func startListening(mode: ButterflyMode) async {
        guard !isRecording else { return }
        
        let granted = await liveEngine.requestPermissions()
        guard granted else {
            print("Warning: Microphone or Speech Recognition permission not granted")
            return
        }
        
        do {
            latestTranscript = ""
            streamingInjectedText = ""
            activeMode = mode
            isRecording = true
            
            if mode == .liveStreaming {
                self.statusItem.button?.title = " 🎙️ Streaming..."
            } else {
                self.statusItem.button?.title = " 🔴 Recording..."
            }
            self.updateMenu()
            
            try liveEngine.startLiveListening()
            print("Butterfly: Started \(mode.title) using [\(activeModelSpec.displayName)]...")
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
            isRecording = false
            self.statusItem.button?.title = ""
            self.updateMenu()
        }
    }
    
    /// Stop listening and finalize text
    private func stopAndInject() async {
        guard isRecording else { return }
        isRecording = false
        
        let mode = activeMode
        self.statusItem.button?.title = (mode == .recordAndPolish) ? " ⏳ Polishing..." : " ⏳ Finalizing..."
        self.updateMenu()
        
        // Asynchronously flush audio buffers and retrieve full finalized transcript
        let fullRawTranscript = await liveEngine.stopLiveListening()
        
        if mode == .recordAndPolish {
            print("\n[Mode 2: Full Monologue Captured (\(fullRawTranscript.count) chars)]:\n\(fullRawTranscript)")
            // Mode 2: Record & Smart Polish (Paste structured note)
            let polishedText = TextPolisher.shared.polish(fullRawTranscript, mode: .structuredNote)
            if !polishedText.isEmpty {
                print("\n[Mode 2: Polished Note Result]:\n\(polishedText)\n")
                await InputInjector.shared.inject(text: polishedText)
            }
        } else {
            // Mode 1: Live Streaming text was already typed into the focused cursor in real-time.
            print("\n[Mode 1: Live Streaming Completed]: \(fullRawTranscript)")
        }
        
        streamingInjectedText = ""
        self.statusItem.button?.title = ""
        self.updateMenu()
    }
    
    /// Register global and local system-wide hotkeys
    private func setupGlobalHotkey() {
        let eventHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            guard let self = self else { return event }
            
            // 36: Return/Enter, 76: Keypad Enter, 53: Escape (Esc)
            // When recording, the first Enter or Esc stops recording and finalizes text.
            // Returning nil swallows the Enter event so it does NOT accidentally send chat messages!
            if (event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 53) && self.isRecording {
                print("\n[Hotkey Event: Enter / Esc] -> Stopping recording & injecting text (First Enter swallowed to protect message sending)...")
                Task { @MainActor in
                    await self.stopAndInject()
                }
                return nil
            }
            
            // 49: Space keycode
            if event.keyCode == 49 {
                let flags = event.modifierFlags
                let isOptionPressed = flags.contains(.option)
                let isShiftPressed = flags.contains(.shift)
                
                if isOptionPressed {
                    Task { @MainActor in
                        if self.isRecording {
                            print("\n[Hotkey Event: Stop Toggle] -> Finalizing...")
                            await self.stopAndInject()
                        } else {
                            if isShiftPressed {
                                print("\n[Hotkey Event: Option + Shift + Space] -> Starting Mode 2 (Record & Smart Polish)...")
                                await self.startListening(mode: .recordAndPolish)
                            } else {
                                print("\n[Hotkey Event: Option + Space] -> Starting Mode 1 (Live Streaming)...")
                                await self.startListening(mode: .liveStreaming)
                            }
                        }
                    }
                    return nil
                }
            }
            return event
        }
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = eventHandler(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: eventHandler)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
