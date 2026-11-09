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
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
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

    func showBase(clip: Slot?, logo: CGImage?, breakScreen: Bool) {
        withoutAnimation {
            playerA.isHidden = clip != .a
            playerB.isHidden = clip != .b
            baseLogo.contents = logo
            baseLogo.isHidden = logo == nil
            breakLayer.isHidden = !breakScreen
        }
    }

    func showCover(logo: CGImage?, black: Bool) {
        withoutAnimation {
            coverLogo.contents = logo
            coverLogo.isHidden = logo == nil
            coverBlack.isHidden = !black
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
