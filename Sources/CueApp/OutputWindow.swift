import AVFoundation
import AppKit
import CueCore
import QuartzCore

func withoutAnimation(_ changes: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    changes()
    CATransaction.commit()
}

@MainActor
final class OutputWindow: NSWindow {
    private static let shielding = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    private static let fullscreenBehaviour: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone,
    ]
    private static let windowedSize = NSSize(width: 960, height: 540)
    private static let fadeKey = "coverFade"

    private(set) var presentation = OutputPresentation.fullscreen
    private var windowedFrame: NSRect?
    private let root = CALayer()
    private let playerA: AVPlayerLayer
    private let playerB: AVPlayerLayer
    private let baseLogo = CALayer()
    private let breakLayer = CALayer()
    private let breakTitle = CATextLayer()
    private let breakCountdown = CATextLayer()
    private let coverLogo = CALayer()
    private let coverBlack = CALayer()
    private var titleText = ""
    private var countdownText: String?

    init(playerA a: AVPlayer, playerB b: AVPlayer) {
        playerA = AVPlayerLayer(player: a)
        playerB = AVPlayerLayer(player: b)
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        level = Self.shielding
        collectionBehavior = Self.fullscreenBehaviour
        ignoresMouseEvents = true
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        animationBehavior = .none
        isReleasedWhenClosed = false
        // Hiding the app (Dock menu, Cmd+H elsewhere) must never reveal the desktop on the projector.
        canHide = false

        let black = CGColor.black
        root.backgroundColor = black
        for layer in [playerA, playerB] {
            layer.videoGravity = .resizeAspect
            layer.backgroundColor = black
        }
        for layer in [baseLogo, coverLogo] {
            layer.contentsGravity = .resizeAspect
            layer.backgroundColor = black
        }
        breakLayer.backgroundColor = black
        coverBlack.backgroundColor = black
        for layer in [breakTitle, breakCountdown] {
            layer.truncationMode = .end
            breakLayer.addSublayer(layer)
        }
        let stack = [playerA, playerB, baseLogo, breakLayer, coverLogo, coverBlack]
        withoutAnimation {
            for layer in stack {
                layer.isHidden = true
                root.addSublayer(layer)
            }
        }

        let view = OutputView()
        view.layer = root
        view.wantsLayer = true
        view.onLayout = { [weak self] in self?.layoutLayers() }
        contentView = view
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func playerLayer(_ slot: Slot) -> AVPlayerLayer {
        slot == .a ? playerA : playerB
    }

    // Fullscreen leaves frame and ordering to the display watcher; window and off sit on the control screen.
    func present(_ new: OutputPresentation) {
        if presentation == .window { windowedFrame = frame }
        presentation = new
        // Out while restyled, so no screen ever shows a half-changed window.
        orderOut(nil)
        switch new {
        case .fullscreen:
            styleMask = .borderless
            level = Self.shielding
            collectionBehavior = Self.fullscreenBehaviour
            hasShadow = false
            ignoresMouseEvents = true
            alphaValue = 1
        case .window:
            styleMask = [.titled, .resizable]
            // Above the control window, which fills the laptop screen and would otherwise bury it on every click.
            level = .floating
            // Every Space, so a Space switch never takes the picture away mid-rehearsal.
            collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
            hasShadow = true
            ignoresMouseEvents = false
            alphaValue = 1
            contentAspectRatio = Self.windowedSize
            let saved = windowedFrame.flatMap { frame in
                NSScreen.screens.contains { $0.frame.intersects(frame) } ? frame : nil
            }
            setFrame(saved ?? centeredOnControlScreen(), display: true)
            orderFrontRegardless()
        case .off:
            styleMask = .borderless
            level = .normal
            collectionBehavior = Self.fullscreenBehaviour
            hasShadow = false
            ignoresMouseEvents = true
            // Ordered in but invisible, so the output layers still report ready and arming never waits.
            alphaValue = 0
            setFrame(centeredOnControlScreen(), display: true)
            orderFrontRegardless()
        }
    }

    private func centeredOnControlScreen() -> NSRect {
        let control = DisplayWatcher.roles().control
        let screen = NSScreen.screens.first { $0.displayID == control } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = frameRect(forContentRect: NSRect(origin: .zero, size: Self.windowedSize)).size
        return NSRect(
            x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width,
            height: size.height)
    }

    func showBase(clip: Slot?, logo: CGImage?, breakScreen: Bool) {
        withoutAnimation {
            playerA.isHidden = clip != .a
            playerB.isHidden = clip != .b
            baseLogo.contents = logo
            baseLogo.isHidden = logo == nil
            breakLayer.isHidden = !breakScreen
            // A new base ends a cover fade, so nothing ever dissolves over the item GO brings in.
            coverLogo.removeAnimation(forKey: Self.fadeKey)
        }
    }

    // Model values are always the final state; a fade only animates the cover logo's opacity towards them.
    func showCover(logo: CGImage?, black: Bool, fade: TimeInterval) {
        withoutAnimation {
            let from: Float = fade > 0 && !coverLogo.isHidden ? coverLogo.presentation()?.opacity ?? coverLogo.opacity : 0
            coverLogo.removeAnimation(forKey: Self.fadeKey)
            coverBlack.isHidden = !black
            guard fade > 0 else {
                coverLogo.contents = logo
                coverLogo.isHidden = logo == nil
                coverLogo.opacity = 1
                return
            }
            // Fading out keeps the old image until the layer is transparent.
            if let logo { coverLogo.contents = logo }
            let to: Float = logo == nil ? 0 : 1
            coverLogo.isHidden = false
            coverLogo.opacity = to
            // A zero-length CAAnimation runs for the default 0.25 s, so none is added.
            guard from != to else { return }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = from
            animation.toValue = to
            animation.duration = fade * Double(abs(to - from))
            coverLogo.add(animation, forKey: Self.fadeKey)
        }
    }

    func setBreak(title: String, countdown: String?) {
        titleText = title
        countdownText = countdown
        withoutAnimation { renderBreak() }
    }

    private func layoutLayers() {
        let bounds = contentView?.bounds ?? .zero
        let scale = backingScaleFactor
        withoutAnimation {
            for layer in [playerA, playerB, baseLogo, breakLayer, coverLogo, coverBlack] {
                layer.frame = bounds
            }
            breakTitle.contentsScale = scale
            breakCountdown.contentsScale = scale
            renderBreak()
        }
    }

    private func renderBreak() {
        let bounds = breakLayer.bounds
        let titleSize = max(1, bounds.height * 0.12)
        let countdownSize = max(1, bounds.height * 0.24)
        let inset = bounds.width * 0.05
        breakTitle.frame = CGRect(
            x: inset, y: bounds.height * 0.55, width: bounds.width - 2 * inset, height: titleSize * 1.3)
        breakCountdown.frame = CGRect(
            x: inset, y: bounds.height * 0.2, width: bounds.width - 2 * inset, height: countdownSize * 1.3)
        breakTitle.string = Self.text(titleText, font: .systemFont(ofSize: titleSize, weight: .semibold))
        breakCountdown.string = Self.text(
            countdownText ?? "", font: .monospacedDigitSystemFont(ofSize: countdownSize, weight: .semibold))
        breakCountdown.isHidden = countdownText == nil
    }

    private static func text(_ string: String, font: NSFont) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(
            string: string, attributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
    }
}

private final class OutputView: NSView {
    var onLayout: () -> Void = {}

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onLayout()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onLayout()
    }
}
