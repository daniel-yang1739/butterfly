import AppKit

/// A nonactivating recording waveform that switches to text during polishing.
@MainActor
public final class FloatingHUDWindow: NSPanel {
    public static let shared = FloatingHUDWindow()

    private let visualEffectView = NSVisualEffectView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let waveformView = RecordingWaveformView()
    private var isVisibleOnScreen = false
    private var isShowingWaveform = false
    private var presentationGeneration = 0

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 90),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        setupViews()
    }

    private func setupViews() {
        guard let contentView else { return }
        visualEffectView.frame = contentView.bounds
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 18
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        contentView.addSubview(visualEffectView)

        statusLabel.frame = NSRect(x: 20, y: 56, width: 520, height: 22)
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .systemCyan
        visualEffectView.addSubview(statusLabel)

        let bodyFrame = NSRect(x: 20, y: 12, width: 520, height: 38)
        waveformView.frame = bodyFrame
        visualEffectView.addSubview(waveformView)

        scrollView.frame = bodyFrame
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        textView.frame = scrollView.bounds
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        visualEffectView.addSubview(scrollView)
    }

    public func show(mode: ButterflyMode = .liveStreaming) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        setFrame(NSRect(x: frame.midX - 280, y: frame.maxY - 110, width: 560, height: 90), display: true)
        presentationGeneration += 1
        isVisibleOnScreen = true
        isShowingWaveform = true
        scrollView.isHidden = true
        waveformView.isHidden = false
        waveformView.start()
        updateRecordingTime("[00:00]", mode: mode)
        alphaValue = 1
        orderFrontRegardless()
    }

    public func updateAudioLevel(_ level: Float) {
        guard isVisibleOnScreen, isShowingWaveform else { return }
        waveformView.updateLevel(level)
    }

    public func updateRecordingTime(_ time: String, mode: ButterflyMode) {
        guard isVisibleOnScreen, isShowingWaveform else { return }
        let title = mode == .liveStreaming ? "Live Dictation" : "Smart Polish Recording"
        statusLabel.stringValue = "\(title) \(time)  ·  Enter / Esc to finish"
    }

    /// Stop waveform rendering as soon as the app starts processing the transcript.
    public func updateStatus(title: String, detail: String) {
        guard isVisibleOnScreen else { return }
        isShowingWaveform = false
        waveformView.stop()
        waveformView.isHidden = true
        scrollView.isHidden = false
        statusLabel.stringValue = title
        textView.textStorage?.setAttributedString(NSAttributedString(string: detail, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 14, weight: .regular)
        ]))
    }

    public func hide() {
        guard isVisibleOnScreen else { return }
        isVisibleOnScreen = false
        isShowingWaveform = false
        waveformView.stop()
        presentationGeneration += 1
        let generation = presentationGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.presentationGeneration == generation else { return }
                self.orderOut(nil)
            }
        })
    }
}

/// A short rolling history of measured microphone levels, without synthetic motion.
@MainActor
private final class RecordingWaveformView: NSView {
    private static let barCount = 52
    private var history = [CGFloat](repeating: 0, count: barCount)
    private var targetLevel: CGFloat = 0
    private var displayedLevel: CGFloat = 0
    private var lastSampleTime = Date.distantPast
    private var timer: Timer?

    func start() {
        stop()
        history = [CGFloat](repeating: 0, count: Self.barCount)
        targetLevel = 0
        displayedLevel = 0
        lastSampleTime = .distantPast
        setAccessibilityElement(true)
        setAccessibilityLabel("Microphone input level")
        needsDisplay = true
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advance() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateLevel(_ level: Float) {
        guard level.isFinite else { return }
        targetLevel = CGFloat(min(max(level, 0), 1))
        lastSampleTime = Date()
    }

    private func advance() {
        guard timer != nil else { return }
        let target = Date().timeIntervalSince(lastSampleTime) > 0.3 ? 0 : targetLevel
        displayedLevel += (target - displayedLevel) * (target > displayedLevel ? 0.8 : 0.3)
        history.removeFirst()
        history.append(displayedLevel)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let spacing = bounds.width / CGFloat(Self.barCount)
        let barWidth: CGFloat = 4
        for index in history.indices {
            let level = reducedMotion ? displayedLevel : history[index]
            let height = max(2, sqrt(level) * (bounds.height - 2))
            let rect = NSRect(x: CGFloat(index) * spacing + (spacing - barWidth) / 2,
                              y: bounds.midY - height / 2, width: barWidth, height: height)
            NSColor.systemCyan.withAlphaComponent(level > 0.01 ? 0.9 : 0.3).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }
}
