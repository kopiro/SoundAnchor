import SwiftUI
import CoreAudio
import SwiftUI

struct ContentView: View {
    @State private var devices: [AudioDevice] = [] // Merged saved and available devices
    @State private var currentDeviceID: AudioDeviceID? // Current active device name
    @State private var forceInputEnabled: Bool = AudioManager.shared.isForceInputEnabled
    @State private var hoveredIndex: Int? = nil
    @State private var devicesReloadedAt: Date? = nil

    var body: some View {
        VStack(spacing: 10) {
            Text("SoundAnchor")
                .padding(.top)
                .padding(.bottom, 4)
            
            List {
                ForEach(devices.indices, id: \.self) { index in
                    let device = devices[index]
                    let isAvailable = device.id != nil
                    let isActive = currentDeviceID == device.id
                    let isHovering = hoveredIndex == index

                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 24, height: 24)
                            
                            if let icon = device.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "mic.fill") // Fallback icon
                                    .foregroundColor(isActive ? .white : .primary)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        
                        Text(device.name)
                        Spacer()
                        
                        if !isAvailable && isHovering {
                            Button(action: {
                                deleteDevice(at: index)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .listRowSeparator(.hidden)
                    .opacity(isAvailable ? 1 : 0.5)
                    .background(isHovering ? Color.gray.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                    .onHover { hovering in
                        hoveredIndex = hovering ? index : nil
                    }
                }
                .onMove { indices, newOffset in
                    moveDevices(fromOffsets: indices, toOffset: newOffset)
                }

            }
            .listStyle(PlainListStyle())

            HStack {
                Toggle("Enabled", isOn: $forceInputEnabled)
                    .onChange(of: forceInputEnabled) { value in
                        AudioManager.shared.isForceInputEnabled = value
                    }
            }
            .padding(.bottom)
        }
        .onAppear {
            loadDevices()
            AudioManager.shared.monitorDefaultInputDeviceChanges {
                devicesReloadedAt = Date()
            }
        }
        .onChange(of: devicesReloadedAt) { _ in
            loadDevices() // Reload devices when the trigger changes
        }
    }
    
    private func moveDevices(fromOffsets indices: IndexSet, toOffset newOffset: Int) {
        devices.move(fromOffsets: indices, toOffset: newOffset)
        
        let devicesToSave = devices.map { SavedDevice(name: $0.name) }
        DeviceManager().saveDeviceOrder(devicesToSave)

        AudioManager.shared.enforceDeviceOrder()
        currentDeviceID = AudioManager.shared.getCurrentInputDeviceID()
    }

    private func loadDevices() {
        // Load saved device names
        let savedNames = DeviceManager().loadDeviceOrder().map { $0.name }

        // Get all available devices
        let availableDevices = AudioManager.shared.getAudioInputDevices()

        // Merge saved and available devices, ensuring proper sorting and gray-out for unavailable devices
        devices = savedNames.map { name in
            if let availableDevice = availableDevices.first(where: { $0.name == name }) {
                return availableDevice // Use the available device
            } else {
                return AudioDevice(id: nil, name: name, icon: nil) // Create a placeholder for unavailable devices
            }
        }

        // Add any new available devices not in the saved list
        for device in availableDevices where !devices.contains(where: { $0.name == device.name }) {
            devices.append(device)
        }

        // Get the current default input device
        currentDeviceID = AudioManager.shared.getCurrentInputDeviceID()
    }

    private func deleteDevice(at index: Int) {
        devices.remove(at: index)
        let devicesToSave = devices.map { SavedDevice(name: $0.name) }
        DeviceManager().saveDeviceOrder(devicesToSave)
    }
}
