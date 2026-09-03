import AppKit
import SwiftUI
import ButterflyCore

/// Operating mode for Butterfly
public enum ButterflyMode: String, CaseIterable {
    case liveStreaming = "live"       // Real-time zero-latency speech-to-text dictation
    
    public var title: String {
        return "Live Voice Dictation"
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
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var animationIndex: Int = 0
    private let slidingWindowBuffer = SlidingWindowBuffer()
    private var pauseTimer: Timer?
    
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
                
                let elapsed = Int(Date().timeIntervalSince(self.recordingStartTime ?? Date()))
                let minutes = String(format: "%02d", elapsed / 60)
                let seconds = String(format: "%02d", elapsed % 60)
                let timeStr = "[\(minutes):\(seconds)]"
                
                // Phase 1: Continuous Acoustic Streaming (Append-Only Fast Path)
                let action = self.slidingWindowBuffer.appendStreamingText(formattedText)
                InputInjector.shared.applySlidingDelta(action)
                
                // Update Floating HUD with Tri-Color Cognitive Model (White: Locked, Gold: AI Refined, Gray: Raw Speech)
                FloatingHUDWindow.shared.update(
                    frozenText: self.slidingWindowBuffer.frozenText,
                    polishedText: self.slidingWindowBuffer.polishedText,
                    activeTail: self.slidingWindowBuffer.activeTail,
                    timeStr: timeStr,
                    mode: .liveStreaming
                )
                
                // Phase 2: Reset 0.8s Pause-Gated Refinement Timer (Pure Swift Zero-Hallucination)
                self.pauseTimer?.invalidate()
                self.pauseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self, self.isRecording else { return }
                        
                        let action = self.slidingWindowBuffer.onPauseTriggered()
                        InputInjector.shared.applySlidingDelta(action)
                        
                        // Re-sync Floating HUD with updated Tri-Color regions
                        FloatingHUDWindow.shared.update(
                            frozenText: self.slidingWindowBuffer.frozenText,
                            polishedText: self.slidingWindowBuffer.polishedText,
                            activeTail: self.slidingWindowBuffer.activeTail,
                            timeStr: timeStr,
                            mode: .liveStreaming
                        )
                    }
                }
                
                let preview = formattedText.count > 10 ? "..." + String(formattedText.suffix(10)) : formattedText
                self.statusItem.button?.title = " 🎙️ \(timeStr) \(preview)"
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
          • [Option + Space]         -> Toggle Live Voice Dictation (types live as you speak)
          • [Enter] / [Esc]          -> Stop Dictation (swallows first Enter key safely)
        
        Active Speech Model: \(ModelManager.shared.activeASRModel.displayName)
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
        
        let titleItem = NSMenuItem(title: "Butterfly Voice Dictation", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        if isRecording {
            let stopItem = NSMenuItem(
                title: "Stop Dictation (Enter / Esc)",
                action: #selector(stopCurrentRecording),
                keyEquivalent: "\r"
            )
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let liveItem = NSMenuItem(
                title: "Start Voice Dictation (Option+Space)",
                action: #selector(startLiveStreamingMode),
                keyEquivalent: ""
            )
            liveItem.target = self
            menu.addItem(liveItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Track A: Speech Recognition (ASR) Submenu
        let asrMenu = NSMenu()
        for model in ModelManager.defaultASRModels {
            let isSelected = model.id == ModelManager.shared.activeASRModel.id
            let isDownloaded = ModelManager.shared.isModelDownloaded(model)
            
            let selectionMark = isSelected ? "✓ " : "   "
            let downloadStatus = isDownloaded ? " [Ready]" : " [Click to Download]"
            let sizeDesc = model.sizeBytes > 0 ? " (\(model.formattedSize))" : " (Built-in)"
            
            let itemTitle = "\(selectionMark)\(model.displayName)\(sizeDesc)\(downloadStatus)"
            let modelItem = NSMenuItem(
                title: itemTitle,
                action: #selector(selectASRModelSpec(_:)),
                keyEquivalent: ""
            )
            modelItem.target = self
            modelItem.representedObject = model
            asrMenu.addItem(modelItem)
        }
        let asrParentItem = NSMenuItem(title: "🎙️ Speech Model: \(ModelManager.shared.activeASRModel.displayName)", action: nil, keyEquivalent: "")
        asrParentItem.submenu = asrMenu
        menu.addItem(asrParentItem)
        
        // Manage Model Storage & Uninstall Submenu
        let cacheMenu = NSMenu()
        let downloadedModels = ModelManager.defaultASRModels.filter { $0.id != "apple-speech-native" && ModelManager.shared.isModelDownloaded($0) }
        
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
        
        let cacheParentItem = NSMenuItem(title: "💾 Model Storage", action: nil, keyEquivalent: "")
        cacheParentItem.submenu = cacheMenu
        menu.addItem(cacheParentItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: "Quit Butterfly",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        statusItem.button?.performClick(nil)
    }
    
    @objc private func selectASRModelSpec(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? ModelSpec else { return }
        
        if ModelManager.shared.isModelDownloaded(spec) {
            ModelManager.shared.activeASRModel = spec
            updateMenu()
            print("Butterfly: Switched active speech model to \(spec.displayName)")
            return
        }
        
        downloadModelSpec(spec)
    }
    
    private func downloadModelSpec(_ spec: ModelSpec) {
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
                
                ModelManager.shared.activeASRModel = spec
                
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
            updateMenu()
            print("Butterfly: Deleted model \(spec.displayName)")
        } catch {
            print("Failed to delete model: \(error.localizedDescription)")
        }
    }
    
    @objc private func clearAllModelCache() {
        do {
            try ModelManager.shared.clearAllCache()
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
    
    @objc private func stopCurrentRecording() {
        Task { @MainActor in
            await stopAndInject()
        }
    }
    
    /// Start listening with live streaming dictation
    private func startListening(mode: ButterflyMode = .liveStreaming) async {
        guard !isRecording else { return }
        
        let granted = await liveEngine.requestPermissions()
        guard granted else {
            print("Warning: Microphone or Speech Recognition permission not granted")
            return
        }
        
        do {
            latestTranscript = ""
            streamingInjectedText = ""
            activeMode = .liveStreaming
            isRecording = true
            recordingStartTime = Date()
            animationIndex = 0
            slidingWindowBuffer.reset()
            pauseTimer?.invalidate()
            pauseTimer = nil
            
            self.statusItem.button?.title = " 🎙️ [00:00] Streaming ·"
            self.updateMenu()
            
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isRecording else { return }
                    self.animationIndex = (self.animationIndex + 1) % 4
                    let dots = String(repeating: "·", count: self.animationIndex + 1)
                    let elapsed = Int(Date().timeIntervalSince(self.recordingStartTime ?? Date()))
                    let timeStr = String(format: "[%02d:%02d]", elapsed / 60, elapsed % 60)
                    
                    if self.latestTranscript.isEmpty {
                        self.statusItem.button?.title = " 🎙️ \(timeStr) Streaming \(dots)"
                    }
                }
            }
            
            try liveEngine.startLiveListening()
            FloatingHUDWindow.shared.show(mode: .liveStreaming)
            print("Butterfly: Started Live Voice Dictation [ASR: \(ModelManager.shared.activeASRModel.displayName)]...")
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
            isRecording = false
            FloatingHUDWindow.shared.hide()
            recordingTimer?.invalidate()
            recordingTimer = nil
            pauseTimer?.invalidate()
            pauseTimer = nil
            self.statusItem.button?.title = ""
            self.updateMenu()
        }
    }
    
    /// Stop listening and finalize text
    private func stopAndInject() async {
        guard isRecording else { return }
        isRecording = false
        FloatingHUDWindow.shared.hide()
        recordingTimer?.invalidate()
        recordingTimer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        
        self.statusItem.button?.title = " ⏳ Finalizing..."
        self.updateMenu()
        
        // Asynchronously flush audio buffers and retrieve full finalized transcript
        let fullRawTranscript = await liveEngine.stopLiveListening()
        
        // Final clause refinement flush & complete freeze
        let finalAction = slidingWindowBuffer.onPauseTriggered()
        InputInjector.shared.applySlidingDelta(finalAction)
        slidingWindowBuffer.finalizeAll()
        print("\n[Butterfly: Live Dictation Completed]: \(fullRawTranscript)")
        
        streamingInjectedText = ""
        self.statusItem.button?.title = ""
        self.updateMenu()
    }
    
    private var eventTapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    /// Handle low-level CGEvent from Event Tap to allow swallowing Enter/Esc and hotkeys
    fileprivate func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = eventTapPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // 1. Enter (36 / 76) or Esc (53) during active recording -> Stop recording & SWALLOW keypress
        if (keyCode == 36 || keyCode == 76 || keyCode == 53) && isRecording {
            print("\n[CGEventTap: Enter/Esc Intercepted] -> Stopping recording & SWALLOWING Enter key (chat safe)!")
            Task { @MainActor in
                await self.stopAndInject()
            }
            // RETURNING NIL SWALLOWS THE KEY EVENT SO TARGET APP NEVER SEES ENTER!
            return nil
        }
        
        // 2. Option + Space (49) -> Toggle Live Streaming Dictation
        if keyCode == 49 && flags.contains(.maskAlternate) {
            Task { @MainActor in
                if self.isRecording {
                    print("\n[CGEventTap: Toggle Stop]")
                    await self.stopAndInject()
                } else {
                    print("\n[CGEventTap: Option + Space] -> Starting Live Voice Dictation...")
                    await self.startListening(mode: .liveStreaming)
                }
            }
            return nil // Swallow Space key so it doesn't type a space
        }
        
        return Unmanaged.passRetained(event)
    }
    
    /// Register global and local system-wide hotkeys
    private func setupGlobalHotkey() {
        // 1. Setup high-level Event Tap for global swallowing
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                return appDelegate.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) {
            self.eventTapPort = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("Butterfly: Low-level EventTap registered successfully (Enter swallowing active).")
        }
        
        // 2. Local monitor for fallback
        let fallbackHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            guard let self = self else { return event }
            if (event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 53) && self.isRecording {
                Task { @MainActor in
                    await self.stopAndInject()
                }
                return nil
            }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: fallbackHandler)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
