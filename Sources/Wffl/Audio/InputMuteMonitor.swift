import Foundation
import CoreAudio
import os

/// Watches the current input device's mute and volume state, so a microphone
/// the user has silenced at the system level is not recorded into the meeting.
///
/// Scope, stated plainly: this sees *device* mute — a hardware mute switch, a
/// muted input in Sound settings, or an app that mutes the device itself. It
/// cannot see the software mute button inside Zoom, Teams, or Meet, because
/// those apps do not mute the device; they keep capturing and stop
/// transmitting. There is no public macOS API that reports another
/// application's mute state, and reverse-engineering per-app internals would
/// be both fragile and a poor trade. `RecorderController.micMuted` is the
/// answer for that case: an explicit control in Wffl the user can hit, which
/// this monitor feeds but does not own.
final class InputMuteMonitor {
    private static let log = Logger(subsystem: "com.wffl.app", category: "input-mute")

    /// Fires on the main queue whenever the system mute state changes.
    var onMuteChanged: ((Bool) -> Void)?

    private(set) var isMuted = false
    private var deviceID: AudioDeviceID?
    private var listener: AudioObjectPropertyListenerBlock?
    private var observedAddresses: [AudioObjectPropertyAddress] = []

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)

    func start(deviceID: AudioDeviceID?) {
        stop()
        guard let device = deviceID ?? Self.defaultInputDevice() else { return }
        self.deviceID = device

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let muted = Self.readMuted(device: device)
            guard muted != self.isMuted else { return }
            self.isMuted = muted
            Self.log.notice("system input mute -> \(muted ? "muted" : "unmuted", privacy: .public)")
            DispatchQueue.main.async { self.onMuteChanged?(muted) }
        }
        listener = block

        for address in [Self.muteAddress, Self.volumeAddress] {
            var addr = address
            let status = AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main, block)
            // A device with no mute or volume control is normal (many USB
            // interfaces expose neither); it just means there is nothing to
            // watch, not that anything failed.
            if status == noErr { observedAddresses.append(address) }
        }

        isMuted = Self.readMuted(device: device)
        if isMuted { DispatchQueue.main.async { [weak self] in self?.onMuteChanged?(true) } }
    }

    func stop() {
        if let deviceID, let listener {
            for address in observedAddresses {
                var addr = address
                AudioObjectRemovePropertyListenerBlock(deviceID, &addr, DispatchQueue.main, listener)
            }
        }
        observedAddresses = []
        listener = nil
        deviceID = nil
        isMuted = false
    }

    /// Muted when the device's mute flag is set, or when its input volume has
    /// been pulled to zero — which is how several devices and the Sound pane
    /// express the same intent.
    private static func readMuted(device: AudioDeviceID) -> Bool {
        if let muted: UInt32 = property(device: device, address: muteAddress), muted != 0 { return true }
        if let volume: Float32 = property(device: device, address: volumeAddress), volume <= 0.0001 { return true }
        return false
    }

    private static func property<T>(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> T? {
        var addr = address
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }
}
