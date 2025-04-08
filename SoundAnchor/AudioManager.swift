import CoreAudio
import AppKit
import UserNotifications

struct AudioDevice {
    let name: String
    let ioType: String
    let id: AudioDeviceID?
    let transportType: UInt32?
    let manufacturer: String
    let uid: String
}

class AudioManager {
    static let shared = AudioManager()
    private let forceInputKey = "ForceInputEnabled"
    private let forceOutputKey = "ForceOutputEnabled"
    private var lastNotificationDate: Date?

    var isForceInputEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: forceInputKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: forceInputKey)
            if newValue {
                enforceInputDeviceOrder()
            }
        }
    }

    var isForceOutputEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: forceOutputKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: forceOutputKey)
            if newValue {
                enforceOutputDeviceOrder()
            }
        }
    }

    func getAudioDevices(scope: AudioObjectPropertyScope) -> [AudioDevice] {
        var size = UInt32(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

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
        var devicesIds = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devicesIds
        )
        
        // Filter and map output devices
        return devicesIds.compactMap { deviceID in
            let name = getDeviceName(deviceID)
            let manufacturer = getDeviceManufacturer(deviceID)
            let uid = getDeviceUID(deviceID)
    
            guard canBeDefaultDevice(deviceID: deviceID, scope: scope) else {
                return nil
            }

            let transportType = getDeviceTransportType(deviceID)
            return AudioDevice(
                name: name,
                ioType: scope == kAudioDevicePropertyScopeInput ? "input" : "output",
                id: deviceID,
                transportType: transportType,
                manufacturer: manufacturer,
                uid: uid
            )
        }
    }

    private func canBeDefaultDevice(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var size = UInt32(MemoryLayout<UInt32>.size)
        var canBeDefault: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
            mScope: scope,
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
        var name: Unmanaged<CFString>?
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioDevicePropertyScopeInput,
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
        
        if status == noErr, let deviceNameCF = name?.takeRetainedValue() as String? {
            return deviceNameCF
        } else {
            return "Unknown Device"
        }
    }
    
    func getDeviceSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var size = UInt32(MemoryLayout<Double>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate: Double = 0
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
    
    func getDeviceManufacturer(_ deviceID: AudioDeviceID) -> String {
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceManufacturerCFString,
            mScope: kAudioObjectPropertyScopeGlobal, // Use kAudioDevicePropertyScopeGlobal here
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceManufacturer: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &deviceManufacturer
        )

        if status == noErr, let deviceManufacturerCF = deviceManufacturer?.takeRetainedValue() as String? {
            return deviceManufacturerCF
        } else {
            return "-"
        }
    }
    
    func getDeviceTransportType(_ deviceID: AudioDeviceID) -> UInt32? {
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, // Use kAudioDevicePropertyScopeGlobal here
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &transportType
        )

        guard status == noErr else {
            return nil
        }
        
        return transportType
    }

    func getDeviceUID(_ deviceID: AudioDeviceID) -> String {
        var size = UInt32(MemoryLayout<CFString>.size)
        var uid: Unmanaged<CFString>?
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &uid
        )

        if status == noErr, let deviceUID = uid?.takeRetainedValue() as String? {
            return deviceUID
        } else {
            print("Failed to get device UID for device ID: \(deviceID)")
            // If we can't get the UID, fall back to a combination of other properties
            let manufacturer = getDeviceManufacturer(deviceID)
            let transportType = getDeviceTransportType(deviceID) ?? 0
            return "\(manufacturer):\(transportType):\(deviceID)"
        }
    }

    func enforceInputDeviceOrder() {
        guard isForceInputEnabled else { return }

        let savedDevices = DeviceManager().loadInputDeviceOrder()
        let availableDevices = getAudioDevices(scope: kAudioDevicePropertyScopeInput)
        let currentDeviceID = getCurrentDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        let currentDeviceName = currentDeviceID.flatMap { getDeviceName($0) }

        for savedDevice in savedDevices {
            if let matchingDevice = availableDevices.first(where: { $0.uid == savedDevice.uid }) {
                print("Device \(savedDevice.name) is available")
                
                if let deviceID = matchingDevice.id, deviceID != currentDeviceID {
                    print("Forcing default input device to: \(matchingDevice.name)")

                    if setDefaultDevice(deviceID: deviceID, selector: kAudioHardwarePropertyDefaultInputDevice) {
                        sendNotification(ioType: "input", currentDeviceName: currentDeviceName, deviceName: matchingDevice.name)
                    }
                } else {
                    print("Device \(savedDevice.name) is already the current default input device")
                }
                
                return
            } else {
                print("Device \(savedDevice.name) is not available, continue")
            }
        }

        print("No devices from the saved order are currently available")
    }

    func enforceOutputDeviceOrder() {
        guard isForceOutputEnabled else { return }

        let savedDevices = DeviceManager().loadOutputDeviceOrder()
        let availableDevices = getAudioDevices(scope: kAudioDevicePropertyScopeOutput)
        let currentDeviceID = getCurrentDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let currentDeviceName = currentDeviceID.flatMap { getDeviceName($0) }

        for savedDevice in savedDevices {
            if let matchingDevice = availableDevices.first(where: { $0.uid == savedDevice.uid }) {
                print("Device \(savedDevice.name) is available")
                
                if let deviceID = matchingDevice.id, deviceID != currentDeviceID {
                    print("Forcing default output device to: \(matchingDevice.name)")

                    if setDefaultDevice(deviceID: deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice) {
                        sendNotification(ioType: "output", currentDeviceName: currentDeviceName, deviceName: matchingDevice.name)
                    }
                } else {
                    print("Device \(savedDevice.name) is already the current default output device")
                }
                
                return
            } else {
                print("Device \(savedDevice.name) is not available, continue")
            }
        }

        print("No devices from the saved order are currently available")
    }

    public func setDefaultDevice(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, // Scope global
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

    private func sendNotification(ioType: String, currentDeviceName: String?, deviceName: String) {
        let now = Date()
        if let lastDate = lastNotificationDate, now.timeIntervalSince(lastDate) < 1 {
            print("Skipping notification to avoid spamming")
            return
        }
        lastNotificationDate = now

        let content = UNMutableNotificationContent()
        content.title = "\(deviceName) is active"
        if (currentDeviceName != nil) {
            content.body = "The default \(ioType) device has been changed from \(currentDeviceName!) to \(deviceName)."
        } else {
            content.body = "The default \(ioType) device has been changed to \(deviceName)."
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func getCurrentDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceID: AudioDeviceID = 0
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,  // Scope global
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
    
    func monitorAnyDevicesChanges(callback: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, // Scope global
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
    
    func monitorDefaultDeviceChanges(selector: AudioObjectPropertySelector, callback: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,  // Scope global
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
            print("Failed to register listener for default device changes")
        }
    }
    
    public func continuoslyEnforceDeviceOrder() {
        monitorAnyDevicesChanges {
            self.enforceInputDeviceOrder()
            self.enforceOutputDeviceOrder()
        }
        
        monitorDefaultDeviceChanges(selector: kAudioHardwarePropertyDefaultInputDevice) {
            self.enforceInputDeviceOrder()
        }
        
        monitorDefaultDeviceChanges(selector: kAudioHardwarePropertyDefaultOutputDevice) {
            self.enforceOutputDeviceOrder()
        }

        enforceInputDeviceOrder()
        enforceOutputDeviceOrder()
    }
}
