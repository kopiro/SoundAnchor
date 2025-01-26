import CoreAudio
import AppKit
import UserNotifications

struct AudioDevice {
    let name: String
    let id: AudioDeviceID?
    let sampleRate: Double?
}

class AudioManager {
    static let shared = AudioManager()
    private let forceInputKey = "ForceInputEnabled"
    private var lastNotificationDate: Date?

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
        guard status == noErr else {
            return []
        }

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
            guard isInputDevice(deviceID), canBeDefaultDevice(deviceID) else {
                return nil
            }
            let name = getDeviceName(deviceID)
            let sampleRate = getDeviceSampleRate(deviceID)
            return AudioDevice(name: name, id: deviceID, sampleRate: sampleRate)
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

    private func canBeDefaultDevice(_ deviceID: AudioDeviceID) -> Bool {
        var size = UInt32(MemoryLayout<UInt32>.size)
        var canBeDefault: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &canBeDefault
        )

        return status == noErr && canBeDefault != 0
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
    
    func getDeviceSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var size = UInt32(MemoryLayout<Double>.size)
        var sampleRate: Double = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &sampleRate
        )

        return status == noErr ? sampleRate : 0
    }

    func enforceDeviceOrder() {
        guard isForceInputEnabled else { return }

        let savedDeviceNames = DeviceManager().loadDeviceOrder().map { $0.name }
        let availableDevices = getAudioInputDevices()
        let currentDeviceID = getCurrentInputDeviceID()

        for name in savedDeviceNames {
            if let matchingDevice = availableDevices.first(where: { $0.name == name }) {
                print("Device \(name) is available")
                
                if let deviceID = matchingDevice.id, deviceID != currentDeviceID {
                    print("Set default input device: \(matchingDevice.name)")
                    if setDefaultInputDevice(deviceID: deviceID) {
                        sendNotification(deviceName: matchingDevice.name)
                    }
                } else {
                    print("Device \(name) is already the current default input device")
                }
                
                return
            } else {
                print("Device \(name) is not available, continue")
            }
        }

        print("No devices from the saved order are currently available")
    }

    public func setDefaultInputDevice(deviceID: AudioDeviceID) -> Bool {
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
            UInt32(MemoryLayout.size(ofValue: deviceID)),
            &deviceIDCopy
        )

        if status != noErr {
            print("Failed to set device with ID: \(deviceID)")
        }
        return status == noErr
    }

    private func sendNotification(deviceName: String) {
        let now = Date()
        if let lastDate = lastNotificationDate, now.timeIntervalSince(lastDate) < 1 {
            print("Skipping notification to avoid spamming")
            return
        }
        lastNotificationDate = now

        let content = UNMutableNotificationContent()
        content.title = "\(deviceName) is active"
        content.body = "The system default audio input device has been changed to \(deviceName)."
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
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
    
    func monitorChanges(callback: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
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
        }
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
        }
    }
}
