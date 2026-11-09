import CoreAudio

enum AudioOutput {
    static func defaultDeviceName() -> String? {
        guard let device = defaultDevice() else { return nil }
        var address = property(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    // HDMI or DisplayPort means the sound goes to a screen, most likely the projector.
    static func defaultDeviceIsDisplay() -> Bool {
        guard let device = defaultDevice() else { return false }
        var address = property(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort
    }

    static func observeDefaultDevice(_ onChange: @escaping @MainActor () -> Void) {
        var address = property(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
            MainActor.assumeIsolated(onChange)
        }
    }

    private static func defaultDevice() -> AudioObjectID? {
        var address = property(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr,
            device != AudioObjectID(kAudioObjectUnknown)
        else { return nil }
        return device
    }

    private static func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
