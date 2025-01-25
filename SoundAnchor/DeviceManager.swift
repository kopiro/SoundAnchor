//
//  DeviceManager.swift
//  SoundAnchor
//
//  Created by Flavio De Stefano on 1/24/25.
//

import Foundation

struct SavedDevice: Codable, Hashable {
    let name: String
}

class DeviceManager {
    let defaults = UserDefaults.standard
    private let key = "DeviceOrder"

    func saveDeviceOrder(_ devices: [SavedDevice]) {
        if let encoded = try? JSONEncoder().encode(devices) {
            defaults.set(encoded, forKey: key)
        }
    }

    func loadDeviceOrder() -> [SavedDevice] {
        if let savedData = defaults.data(forKey: key),
           let devices = try? JSONDecoder().decode([SavedDevice].self, from: savedData) {
            return devices
        }
        return []
    }
}
