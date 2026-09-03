import Foundation
#if os(macOS)
import AppKit

/// Sleek macOS Floating Capsule HUD (Dynamic Island style) displaying two-tone real-time transcription
@MainActor
public final class FloatingHUDWindow: NSPanel {
    public static let shared = FloatingHUDWindow()
    
    private let visualEffectView = NSVisualEffectView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private var isVisibleOnScreen: Bool = false
    
    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 90),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        
        setupViews()
    }
    
    private func setupViews() {
        guard let contentView = self.contentView else { return }
        
        // 1. Frosted glass background
        visualEffectView.frame = contentView.bounds
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 18
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1.0
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        contentView.addSubview(visualEffectView)
        
        // 2. Status Header (Icon + Timer + Mode)
        statusLabel.frame = NSRect(x: 20, y: 56, width: 520, height: 22)
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0) // Neon cyan
        statusLabel.stringValue = "🎙️ Live Dictation [00:00]"
        visualEffectView.addSubview(statusLabel)
        
        // 3. Two-Tone Transcription Text View
        let scroll = NSScrollView(frame: NSRect(x: 18, y: 12, width: 524, height: 42))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        
        textView.frame = scroll.bounds
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        
        scroll.documentView = textView
        visualEffectView.addSubview(scroll)
    }
    
    /// Position HUD centered near top of primary screen (Dynamic Island position)
    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let hudWidth: CGFloat = 560
        let hudHeight: CGFloat = 90
        let x = screenRect.midX - (hudWidth / 2.0)
        let y = screenRect.maxY - hudHeight - 20
        self.setFrame(NSRect(x: x, y: y, width: hudWidth, height: hudHeight), display: true)
    }
    
    /// Show Floating HUD with smooth fade-in
    public func show(mode: ButterflyMode) {
        reposition()
        self.alphaValue = 0.0
        self.orderFrontRegardless()
        
        let modeIcon = (mode == .liveStreaming) ? "🎙️ Live Streaming" : "🔴 Smart Recording"
        statusLabel.stringValue = "\(modeIcon) [00:00]"
        
        let emptyAttr = NSAttributedString(string: "Listening...", attributes: [
            .foregroundColor: NSColor.systemGray,
            .font: NSFont.systemFont(ofSize: 14, weight: .regular)
        ])
        textView.textStorage?.setAttributedString(emptyAttr)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 1.0
        }
        isVisibleOnScreen = true
    }
    
    /// Update HUD text with Tri-Color Cognitive Visual Model:
    /// - `frozenText` -> ⚪ Bright White (100% Locked & confirmed)
    /// - `polishedText` -> 🟡 Amber Gold (AI Refined in active wave)
    /// - `activeTail` -> 🔘 Subtle Gray (Raw incoming speech)
    public func update(frozenText: String, polishedText: String, activeTail: String, timeStr: String, mode: ButterflyMode) {
        guard isVisibleOnScreen else { return }
        
        let modeIcon = (mode == .liveStreaming) ? "🎙️ Live Streaming" : "🔴 Smart Recording"
        statusLabel.stringValue = "\(modeIcon) \(timeStr)"
        
        let attributedString = NSMutableAttributedString()
        
        // 1. Frozen prefix in Bright White (⚪ Tier 1: 100% Locked)
        if !frozenText.isEmpty {
            let whiteAttr: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 14, weight: .medium)
            ]
            attributedString.append(NSAttributedString(string: frozenText, attributes: whiteAttr))
        }
        
        // 2. AI Polished segment in Amber Gold (🟡 Tier 2: AI Refined in active wave)
        if !polishedText.isEmpty {
            let goldColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.35, alpha: 1.0) // Amber gold / warm yellow
            let goldAttr: [NSAttributedString.Key: Any] = [
                .foregroundColor: goldColor,
                .font: NSFont.systemFont(ofSize: 14, weight: .regular)
            ]
            attributedString.append(NSAttributedString(string: polishedText, attributes: goldAttr))
        }
        
        // 3. Raw active tail in Subtle Gray (🔘 Tier 3: Raw incoming speech)
        if !activeTail.isEmpty {
            let grayAttr: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(white: 0.68, alpha: 0.9), // Subtle silver gray
                .font: NSFont.systemFont(ofSize: 14, weight: .regular)
            ]
            attributedString.append(NSAttributedString(string: activeTail, attributes: grayAttr))
        } else if frozenText.isEmpty && polishedText.isEmpty {
            let placeholderAttr: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.systemGray,
                .font: NSFont.systemFont(ofSize: 14, weight: .regular)
            ]
            attributedString.append(NSAttributedString(string: "Listening...", attributes: placeholderAttr))
        }
        
        textView.textStorage?.setAttributedString(attributedString)
        textView.scrollToEndOfDocument(nil)
    }
    
    /// Hide Floating HUD with smooth fade-out
    public func hide() {
        guard isVisibleOnScreen else { return }
        isVisibleOnScreen = false
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}
#endif
