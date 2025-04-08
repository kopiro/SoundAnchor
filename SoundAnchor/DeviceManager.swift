//
//  DeviceManager.swift
//  SoundAnchor
//
//  Created by Flavio De Stefano on 1/24/25.
//

import Foundation

struct SavedDevice: Codable, Hashable {
    let name: String
    let uid: String
}

class DeviceManager {
    let defaults = UserDefaults.standard
    private let key = "DeviceOrder"
    private let outputKey = "OutputDeviceOrder"

    func saveInputDeviceOrder(_ devices: [SavedDevice]) {
        if let encoded = try? JSONEncoder().encode(devices) {
            defaults.set(encoded, forKey: key)
        }
    }

    func loadInputDeviceOrder() -> [SavedDevice] {
        if let savedData = defaults.data(forKey: key),
           let devices = try? JSONDecoder().decode([SavedDevice].self, from: savedData) {
            return devices
        }
        return []
    }

    func saveOutputDeviceOrder(_ devices: [SavedDevice]) {
        if let encoded = try? JSONEncoder().encode(devices) {
            defaults.set(encoded, forKey: outputKey)
        }
    }

    func loadOutputDeviceOrder() -> [SavedDevice] {
        if let savedData = defaults.data(forKey: outputKey),
           let devices = try? JSONDecoder().decode([SavedDevice].self, from: savedData) {
            return devices
        }
        return []
    }
}
