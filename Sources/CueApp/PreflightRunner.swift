import AVFoundation
import AppKit
import CoreGraphics
import CueCore
import IOKit.ps

enum PreflightRunner {
    @MainActor private static var onPowerChange: (() -> Void)?

    static func probe(_ url: URL) async -> ClipProbe {
        guard FileManager.default.fileExists(atPath: url.path) else { return ClipProbe() }
        let asset = AVURLAsset(url: url)
        var probe = ClipProbe(exists: true)
        do {
            let (playable, duration, tracks) = try await asset.load(.isPlayable, .duration, .tracks)
            probe.playable = playable
            probe.duration = duration.seconds.isFinite ? duration.seconds : 0
            probe.hasAudio = tracks.contains { $0.mediaType == .audio }
            guard let video = tracks.first(where: { $0.mediaType == .video }) else { return probe }
            probe.hasVideo = true
            let (size, fps, formats) = try await video.load(.naturalSize, .nominalFrameRate, .formatDescriptions)
            probe.width = Int(abs(size.width).rounded())
            probe.height = Int(abs(size.height).rounded())
            probe.fps = Double(fps)
            probe.codec = formats.first.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? ""
        } catch {
            Log.deferred("probe \(url.lastPathComponent) failed: \(error.localizedDescription)")
        }
        return probe
    }

    static func logoImage(at url: URL) -> CGImage? {
        NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static func system(output: OutputStatus?, availableHz: [Double], soundDevice: String?) -> SystemProbe {
        var probe = SystemProbe(projector: false)
        if case .attached(let name, let hz, let mirrored)? = output {
            probe.projector = true
            probe.projectorName = name ?? ""
            probe.mirrored = mirrored
            probe.refreshHz = hz
            probe.availableHz = availableHz
        }
        probe.onBattery = onBattery
        // "Displays have separate Spaces" off is stored as spans-displays = true.
        probe.spansDisplays = UserDefaults(suiteName: "com.apple.spaces")?.bool(forKey: "spans-displays") ?? false
        probe.soundDevice = soundDevice ?? ""
        probe.soundToDisplay = AudioOutput.defaultDeviceIsDisplay()
        return probe
    }

    @MainActor static func observePowerSource(_ onChange: @escaping @MainActor () -> Void) {
        onPowerChange = onChange
        let source = IOPSNotificationCreateRunLoopSource(
            { _ in
                MainActor.assumeIsolated { PreflightRunner.onPowerChange?() }
            }, nil)
        guard let source = source?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    // Rates at the current resolution only, as System Settings > Displays offers; HiDPI modes need the option.
    static func refreshRates(of display: CGDirectDisplayID) -> [Double] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let current = CGDisplayCopyDisplayMode(display),
            let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]
        else { return [] }
        return modes.filter { $0.pixelWidth == current.pixelWidth && $0.pixelHeight == current.pixelHeight }
            .map(\.refreshRate)
    }

    private static var onBattery: Bool {
        let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        return (source as String?) == kIOPMBatteryPowerKey
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}
