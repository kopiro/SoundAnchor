import CoreAudio
import AppKit

struct AudioDevice {
    let id: AudioDeviceID?
    let name: String
    let icon: NSImage?
}

class AudioManager {
    static let shared = AudioManager()
    private let forceInputKey = "ForceInputEnabled"

    var isForceInputEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: forceInputKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: forceInputKey)
            if newValue {
                enforceDeviceOrder()
            }
        }
    }

    func getAudioInputDevices() -> [AudioDevice] {
        var size = UInt32(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Get the size of the devices array
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        )

        // Filter and map input devices
        return devices.compactMap { deviceID in
            guard isInputDevice(deviceID) else { return nil }
            let name = getDeviceName(deviceID)
            let icon = getDeviceIcon(deviceID)
            return AudioDevice(id: deviceID, name: name, icon: icon)
        }
    }

    private func isInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var size = UInt32(MemoryLayout<UInt32>.size)
        var inputStreams: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &inputStreams
        )

        return status == noErr && inputStreams > 0
    }

    func getDeviceName(_ deviceID: AudioDeviceID) -> String {
        var size = UInt32(MemoryLayout<CFString>.size)
        var name: CFString = "" as CFString
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &name
        )
        return status == noErr ? (name as String) : "Unknown Device"
    }
    
    func getDeviceIcon(_ deviceID: AudioDeviceID) -> NSImage? {
        var size = UInt32(MemoryLayout<CFData>.size)
        var iconData: CFData?
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIcon,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &iconData
        )

        guard status == noErr, let iconData = iconData as Data? else { return nil }
        return NSImage(data: iconData)
    }

    func enforceDeviceOrder() {
        guard isForceInputEnabled else { return }

        let savedDeviceNames = DeviceManager().loadDeviceOrder().map { $0.name }
        let availableDevices = getAudioInputDevices()

        for name in savedDeviceNames {
            if let matchingDevice = availableDevices.first(where: { $0.name == name }) {
                if let deviceID = matchingDevice.id {
                    print("Set default input device: \(matchingDevice.name)")
                    setDefaultInputDevice(deviceID: deviceID)
                    return
                }
            }
        }

        print("No devices from the saved order are currently available")
    }

    private func setDefaultInputDevice(deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceIDCopy = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout.size(ofValue: deviceIDCopy)),
            &deviceIDCopy
        )

        if status != noErr {
            print("Failed to set device with ID: \(deviceID)")
        }
    }

    func getCurrentInputDeviceID() -> AudioDeviceID? {
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceID: AudioDeviceID = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }
    
    func monitorDefaultInputDeviceChanges(callback: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listenerBlock: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                callback()
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listenerBlock
        )

        if status != noErr {
            print("Failed to register listener for default input device changes")
        } else {
            print("Successfully registered listener for default input device changes")
        }
    }
}
