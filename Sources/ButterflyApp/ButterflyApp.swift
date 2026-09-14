import AppKit
import SwiftUI
import ButterflyCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let smartPolishStyleDefaultsKey = "smartPolishStyle"

    private var statusItem: NSStatusItem!
    private let stateMachine = ButterflyStateMachine(output: CursorDictationOutput())
    private var activity: ButterflyState { stateMachine.currentState }
    private var isDownloadingModel: Bool = false
    private var activeMode: ButterflyMode = .liveStreaming
    private var smartPolishStyle = SmartPolishStyle(
        rawValue: UserDefaults.standard.string(forKey: AppDelegate.smartPolishStyleDefaultsKey) ?? ""
    ) ?? .concise
    private var smartPolishAvailabilityText = "Checking..."
    // Menu selection is an in-process override; the JSON model remains the startup default.
    private var polishModelOverride: String?
    private var recordingPolishModel = "local/foundation"

    private var latestTranscript: String { stateMachine.latestTranscript }
    private let liveEngine = LiveSpeechEngine.shared
    private let localWhisperEngine = LocalWhisperStreamEngine.shared
    private var localEventMonitor: Any?
    private var hotkeyRetryTimer: Timer?
    private var hotkeyStatus = "Checking global hotkeys..."
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var animationIndex: Int = 0

    private var isRecording: Bool {
        if case .recording = activity { return true }
        return false
    }

    private var isBusy: Bool {
        activity != .idle
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        // Request consent once on launch if this build is not trusted. Retry checks
        // below stay silent because the permission prompt completes asynchronously.
        _ = InputInjector.checkAccessibilityPermission(prompt: true)
        setupGlobalHotkey()
        hotkeyRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.registerEventTapIfNeeded()
            }
        }
        refreshSmartPolishAvailability()

        stateMachine.onStateChange = { [weak self] state in self?.updateRecordingState(state) }
        stateMachine.onTranscript = { [weak self] text in self?.handleTranscriptUpdate(text) }
        stateMachine.onAudioLevel = { level in FloatingHUDWindow.shared.updateAudioLevel(level) }
        stateMachine.onError = { [weak self] error in self?.showRecordingError(error.localizedDescription) }
        stateMachine.onProcessingStage = { [weak self] stage in
            guard let self else { return }
            switch stage {
            case .finalizing:
                self.statusItem.button?.title = " Finalizing..."
                if self.activeMode == .smartPolish {
                    FloatingHUDWindow.shared.updateStatus(title: "Smart Polish", detail: "Finalizing transcript...")
                }
            case .polishing:
                self.statusItem.button?.title = " Polishing..."
                FloatingHUDWindow.shared.updateStatus(title: "Smart Polish", detail: "Polishing with \(self.recordingPolishModel)...")
            case .inserting:
                self.statusItem.button?.title = " Inserting..."
                FloatingHUDWindow.shared.updateStatus(title: "Smart Polish", detail: "Inserting polished text...")
            }
        }
        stateMachine.onPolishResult = { result in
            if result.usedFallback {
                print("Butterfly: Used local rules fallback: \(result.fallbackReason ?? "unknown reason")")
            }
        }

        print("""

        Butterfly macOS native desktop app successfully started!
        --------------------------------------------------
        Look for the Butterfly icon in your top menu bar.

        Global Hotkeys:
          • [Option + Space]         -> Toggle Live Voice Dictation (types live as you speak)
          • [Option + Shift + Space] -> Record, polish, then insert once
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
            let candidatePaths: [String?] = [
                Bundle.main.url(forResource: "menu_bar_icon", withExtension: "png")?.path,
                Bundle.main.url(forResource: "menu_bar_icon@2x", withExtension: "png")?.path,
                "docs/assets/menu_bar_icon.png",
                "docs/assets/menu_bar_icon@2x.png",
                URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("docs/assets/menu_bar_icon.png").path,
                URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("docs/assets/menu_bar_icon@2x.png").path,
                fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".cache/butterfly/assets/menu_bar_icon.png").path
            ]

            var loadedImage: NSImage? = nil
            for case let path? in candidatePaths {
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
        }

        updateMenu()
    }

    private func updateMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "Butterfly Voice Dictation", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let hotkeyItem = NSMenuItem(title: hotkeyStatus, action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        let permissionItem = NSMenuItem(title: "Open Accessibility Settings...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        switch activity {
        case .starting(let mode):
            let item = NSMenuItem(title: "Starting \(mode.title)...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        case .recording(let mode):
            let stopItem = NSMenuItem(
                title: "Stop \(mode.title) (Enter / Esc)",
                action: #selector(stopCurrentRecording),
                keyEquivalent: "\r"
            )
            stopItem.target = self
            menu.addItem(stopItem)
        case .processing(let mode):
            let processingItem = NSMenuItem(title: "Processing \(mode.title)...", action: nil, keyEquivalent: "")
            processingItem.isEnabled = false
            menu.addItem(processingItem)
        case .idle:
            let liveItem = NSMenuItem(
                title: "Start Voice Dictation (Option+Space)",
                action: #selector(startLiveStreamingMode),
                keyEquivalent: ""
            )
            liveItem.target = self
            menu.addItem(liveItem)

            let smartItem = NSMenuItem(
                title: "Start Smart Polish (Option+Shift+Space)",
                action: #selector(startSmartPolishMode),
                keyEquivalent: ""
            )
            smartItem.target = self
            menu.addItem(smartItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Track A: Speech Recognition (ASR) Submenu
        let asrMenu = NSMenu()
        for model in ModelManager.defaultASRModels {
            let isSelected = model.id == ModelManager.shared.activeASRModel.id
            let isDownloaded = ModelManager.shared.isModelDownloaded(model)

            let downloadStatus = isDownloaded ? " [Ready]" : " [Click to Download]"
            let sizeDesc = model.sizeBytes > 0 ? " (\(model.formattedSize))" : " (Built-in)"

            let itemTitle = "\(model.displayName)\(sizeDesc)\(downloadStatus)"
            let modelItem = NSMenuItem(
                title: itemTitle,
                action: #selector(selectASRModelSpec(_:)),
                keyEquivalent: ""
            )
            modelItem.target = self
            modelItem.representedObject = model
            modelItem.state = isSelected ? .on : .off
            modelItem.isEnabled = !isBusy && !isDownloadingModel && ModelManager.isRuntimeSupported(model)
            asrMenu.addItem(modelItem)
        }
        let asrParentItem = NSMenuItem(title: "Speech Model: \(ModelManager.shared.activeASRModel.displayName)", action: nil, keyEquivalent: "")
        asrParentItem.submenu = asrMenu
        menu.addItem(asrParentItem)

        // Track B: Model selection and availability
        let polishModelsMenu = NSMenu()
        if let configuration = try? PolishConfiguration.load() {
            let selected = polishModelOverride ?? configuration.polish.defaultModel
            for model in configuration.models {
                let item = NSMenuItem(title: model.name, action: #selector(selectPolishModel(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = model.id
                item.state = selected == model.id ? .on : .off
                item.isEnabled = !isBusy
                polishModelsMenu.addItem(item)
            }
        }
        let polishModelsItem = NSMenuItem(title: "Smart Polish Model: \(smartPolishAvailabilityText)", action: nil, keyEquivalent: "")
        polishModelsItem.submenu = polishModelsMenu
        menu.addItem(polishModelsItem)
        let reloadPolishItem = NSMenuItem(title: "Reload Polish Configuration", action: #selector(reloadPolishConfiguration), keyEquivalent: "")
        reloadPolishItem.target = self
        reloadPolishItem.isEnabled = !isBusy
        menu.addItem(reloadPolishItem)

        // Track B: Style
        let styleMenu = NSMenu()
        for style in SmartPolishStyle.allCases {
            let item = NSMenuItem(
                title: "\(style.title) — \(style.menuDescription)",
                action: #selector(selectSmartPolishStyle(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == smartPolishStyle ? .on : .off
            item.isEnabled = !isBusy
            styleMenu.addItem(item)
        }
        let styleParentItem = NSMenuItem(
            title: "Smart Polish Style: \(smartPolishStyle.title)",
            action: nil,
            keyEquivalent: ""
        )
        styleParentItem.submenu = styleMenu
        menu.addItem(styleParentItem)

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
                    title: "Delete \(downloaded.displayName) (\(downloaded.formattedSize))",
                    action: #selector(uninstallModel(_:)),
                    keyEquivalent: ""
                )
                deleteItem.target = self
                deleteItem.representedObject = downloaded
                deleteItem.isEnabled = !isBusy && !isDownloadingModel
            cacheMenu.addItem(deleteItem)
            }
            cacheMenu.addItem(NSMenuItem.separator())

            let totalBytes = ModelManager.shared.getTotalCacheSizeBytes()
            let formattedTotal = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            let clearAllItem = NSMenuItem(
                title: "Delete All Cached Models (\(formattedTotal))",
                action: #selector(clearAllModelCache),
                keyEquivalent: ""
            )
            clearAllItem.target = self
            clearAllItem.isEnabled = !isBusy && !isDownloadingModel
            cacheMenu.addItem(clearAllItem)
        }

        cacheMenu.addItem(NSMenuItem.separator())
        let openFolderItem = NSMenuItem(
            title: "Open Models Folder in Finder",
            action: #selector(openModelsFolderInFinder),
            keyEquivalent: ""
        )
        openFolderItem.target = self
        cacheMenu.addItem(openFolderItem)

        let cacheParentItem = NSMenuItem(title: "Model Storage", action: nil, keyEquivalent: "")
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

        statusItem.menu = menu
    }

    @objc private func selectASRModelSpec(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? ModelSpec else { return }
        guard !isBusy, !isDownloadingModel, ModelManager.isRuntimeSupported(spec) else { return }

        if ModelManager.shared.isModelDownloaded(spec) {
            ModelManager.shared.activeASRModel = spec
            updateMenu()
            print("Butterfly: Switched active speech model to \(spec.displayName)")
            return
        }

        downloadModelSpec(spec)
    }

    @objc private func selectPolishModel(_ sender: NSMenuItem) {
        guard activity == .idle else { return }
        guard let modelID = sender.representedObject as? String else { return }
        polishModelOverride = modelID
        refreshSmartPolishAvailability()
    }

    @objc private func reloadPolishConfiguration() {
        guard activity == .idle else { return }
        polishModelOverride = nil
        refreshSmartPolishAvailability()
    }

    @objc private func selectSmartPolishStyle(_ sender: NSMenuItem) {
        guard !isBusy,
              let rawValue = sender.representedObject as? String,
              let style = SmartPolishStyle(rawValue: rawValue) else {
            return
        }
        smartPolishStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.smartPolishStyleDefaultsKey)
        updateMenu()
        print("Butterfly: Smart Polish style changed to \(style.title)")
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
        guard !isBusy, !isDownloadingModel else { return }
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
        guard !isBusy, !isDownloadingModel else { return }
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

    @objc private func startSmartPolishMode() {
        Task { @MainActor in
            await startListening(mode: .smartPolish)
        }
    }

    @objc private func stopCurrentRecording() {
        Task { @MainActor in
            await stopAndInject()
        }
    }

    /// Configure dependencies; the Core state machine owns recording and output ordering.
    private func startListening(mode: ButterflyMode = .liveStreaming) async {
        guard activity == .idle else { return }
        let activeModel = ModelManager.shared.activeASRModel
        let source: any DictationSpeechSource
        if activeModel.id.hasPrefix("whisper-") {
            source = WhisperDictationSource(
                engine: localWhisperEngine,
                modelPath: ModelManager.shared.localPath(for: activeModel).path
            )
        } else {
            source = AppleDictationSource(engine: liveEngine)
        }
        do {
            let engine: SmartPolishEngine
            if mode == .smartPolish {
                let configuration = try PolishConfiguration.load()
                recordingPolishModel = polishModelOverride ?? configuration.polish.defaultModel
                engine = try configuration.makeEngine(model: recordingPolishModel)
            } else {
                engine = SmartPolishEngine()
            }
            let style = smartPolishStyle
            await stateMachine.start(mode: mode, source: source) { text in
                await engine.polish(text, style: style)
            }
        } catch {
            showRecordingError(error.localizedDescription)
        }
    }

    private func stopAndInject() async { await stateMachine.stop() }

    /// UI rendering follows the same state transitions exercised by Core tests.
    private func updateRecordingState(_ state: ButterflyState) {
        switch state {
        case .idle:
            recordingTimer?.invalidate()
            recordingTimer = nil
            recordingStartTime = nil
            FloatingHUDWindow.shared.hide()
            statusItem.button?.title = ""
        case .starting(let mode):
            activeMode = mode
            animationIndex = 0
            statusItem.button?.title = " Starting \(mode.title)..."
        case .recording(let mode):
            recordingStartTime = Date()
            FloatingHUDWindow.shared.show(mode: mode)
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.animationIndex = (self.animationIndex + 1) % 4
                    let dots = String(repeating: "·", count: self.animationIndex + 1)
                    let elapsed = Int(Date().timeIntervalSince(self.recordingStartTime ?? Date()))
                    let time = String(format: "[%02d:%02d]", elapsed / 60, elapsed % 60)
                    if mode == .smartPolish || self.latestTranscript.isEmpty {
                        self.statusItem.button?.title = " \(time) Recording \(dots)"
                    }
                    FloatingHUDWindow.shared.updateRecordingTime(time, mode: mode)
                }
            }
        case .processing(let mode):
            recordingTimer?.invalidate()
            recordingTimer = nil
            if mode == .liveStreaming { FloatingHUDWindow.shared.hide() }
        }
        updateMenu()
    }

    private func handleTranscriptUpdate(_ formattedText: String) {
        guard isRecording, activeMode == .liveStreaming else { return }
        let elapsed = Int(Date().timeIntervalSince(recordingStartTime ?? Date()))
        let time = String(format: "[%02d:%02d]", elapsed / 60, elapsed % 60)
        let preview = formattedText.count > 10 ? "..." + String(formattedText.suffix(10)) : formattedText
        statusItem.button?.title = " 🎙️ \(time) \(preview)"
    }

    private var eventTapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Handle low-level CGEvent from Event Tap to allow swallowing Enter/Esc and hotkeys
    fileprivate func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = eventTapPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // 1. Enter or Esc stops recording. Keep swallowing while deferred processing is active.
        if (keyCode == 36 || keyCode == 76 || keyCode == 53) && isRecording {
            print("\n[CGEventTap: Enter/Esc Intercepted] -> Stopping recording & SWALLOWING Enter key (chat safe)!")
            Task { @MainActor in
                await self.stopAndInject()
            }
            // RETURNING NIL SWALLOWS THE KEY EVENT SO TARGET APP NEVER SEES ENTER!
            return nil
        }
        if (keyCode == 36 || keyCode == 76 || keyCode == 53), case .processing = activity {
            return nil
        }

        let hotkeyIntent = GlobalHotkeyResolver.resolve(
            keyCode: keyCode,
            optionPressed: flags.contains(.maskAlternate),
            shiftPressed: flags.contains(.maskShift),
            commandPressed: flags.contains(.maskCommand),
            controlPressed: flags.contains(.maskControl)
        )
        if let hotkeyIntent {
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return nil }
            Task { @MainActor in
                if self.isRecording {
                    print("\n[CGEventTap: Toggle Stop]")
                    await self.stopAndInject()
                } else if case .processing = self.activity {
                    return
                } else {
                    let mode: ButterflyMode = hotkeyIntent == .smartPolish ? .smartPolish : .liveStreaming
                    print("\n[CGEventTap] -> Starting \(mode.title)...")
                    await self.startListening(mode: mode)
                }
            }
            return nil // Swallow Space key so it doesn't type a space
        }

        return Unmanaged.passUnretained(event)
    }

    /// Register global and local system-wide hotkeys
    private func registerEventTapIfNeeded() {
        guard eventTapPort == nil else { return }
        let previousStatus = hotkeyStatus
        guard InputInjector.checkAccessibilityPermission() else {
            hotkeyStatus = "Global Hotkeys: Accessibility Permission Required"
            if activity == .idle { statusItem.button?.title = " ⚠️ Hotkeys unavailable" }
            if previousStatus != hotkeyStatus { updateMenu() }
            return
        }
        // 1. Setup high-level Event Tap for global swallowing
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        let observer = Unmanaged.passUnretained(self).toOpaque()

        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
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
            hotkeyStatus = "Global Hotkeys: Ready"
            print("Butterfly: Low-level EventTap registered successfully (Enter swallowing active).")
        } else {
            hotkeyStatus = "Global Hotkeys: Unavailable — Check Accessibility"
            if activity == .idle { statusItem.button?.title = " ⚠️ Hotkeys unavailable" }
        }
        if eventTapPort != nil, activity == .idle {
            statusItem.button?.title = ""
        }
        if previousStatus != hotkeyStatus { updateMenu() }
    }

    private func setupGlobalHotkey() {
        registerEventTapIfNeeded()

        // 2. Local monitor for fallback
        let fallbackHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            guard let self = self else { return event }
            if (event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 53) && self.isRecording {
                Task { @MainActor in
                    await self.stopAndInject()
                }
                return nil
            }
            if (event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 53), case .processing = self.activity {
                return nil
            }
            let intent = GlobalHotkeyResolver.resolve(
                keyCode: Int(event.keyCode),
                optionPressed: event.modifierFlags.contains(.option),
                shiftPressed: event.modifierFlags.contains(.shift),
                commandPressed: event.modifierFlags.contains(.command),
                controlPressed: event.modifierFlags.contains(.control)
            )
            if let intent {
                guard !event.isARepeat else { return nil }
                Task { @MainActor in
                    if self.isRecording {
                        await self.stopAndInject()
                    } else if self.activity == .idle {
                        let mode: ButterflyMode = intent == .smartPolish ? .smartPolish : .liveStreaming
                        await self.startListening(mode: mode)
                    }
                }
                return nil
            }
            return event
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: fallbackHandler)
    }

    @objc private func openAccessibilitySettings() {
        _ = InputInjector.checkAccessibilityPermission(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showRecordingError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Dictation Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyRetryTimer?.invalidate()
        recordingTimer?.invalidate()
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTapPort { CFMachPortInvalidate(eventTapPort) }
    }

    private func refreshSmartPolishAvailability() {
        Task { @MainActor in
            do {
                let configuration = try PolishConfiguration.load()
                let selected = polishModelOverride ?? configuration.polish.defaultModel
                let modelName = configuration.models.first { $0.id == selected }?.name ?? selected
                let engine = try configuration.makeEngine(model: selected)
                switch await engine.availability() {
                case .available:
                    smartPolishAvailabilityText = "\(modelName) (Configured)"
                case .unavailable:
                    smartPolishAvailabilityText = "\(modelName) (Rules Fallback)"
                }
            } catch {
                smartPolishAvailabilityText = "Configuration Error"
                print("Butterfly: \(error.localizedDescription)")
            }
            updateMenu()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
