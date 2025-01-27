import SwiftUI
import CoreAudio
import SwiftUI

struct ContentView: View {
    @State private var devices: [AudioDevice] = [] // Merged saved and available devices
    @State private var currentDeviceID: AudioDeviceID? // Current active device name
    @State private var forceInputEnabled: Bool = AudioManager.shared.isForceInputEnabled
    @State private var hoveredIndex: Int? = nil
    @State private var devicesReloadedAt: Date? = nil
    @State private var showingHelp = false
    
    var body: some View {
        VStack(spacing: 0) {
            // App name
            HStack {
                Text("SoundAnchor")
                    .bold(true)
                    .padding()
                
                Spacer()
                Button(action: {
                    showingHelp.toggle()
                }) {
                    Image(systemName: "questionmark.circle")
                        .padding()
                }
                .buttonStyle(BorderlessButtonStyle())
                .popover(isPresented: $showingHelp) {
                    Text("Reorder the list to set the priority of your audio input devices. The topmost available device will be forced as your system default input device. You can also click on the device to temporarly force it as your system default input device.")
                        .padding(12)
                        .frame(width: 300)
                }
            }
            
            List {
                ForEach(devices.indices, id: \.self) { index in
                    let device = devices[index]
                    let isAvailable = device.id != nil
                    let isActive = currentDeviceID == device.id
                    let isHovering = hoveredIndex == index
                    let sampleRate = String(format: "%.0f kHz", Double(device.sampleRate ?? 0) / 1000)
                    let iconName = getIconName(for: device.name)

                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 28, height: 28)
                            Image(systemName: iconName)
                                .foregroundColor(isActive ? .white : .primary)
                                .frame(width: 20, height: 20)
                        }
                        .onTapGesture {
                            if let deviceID = device.id {
                                forceInputEnabled = false
                                AudioManager.shared.setDefaultInputDevice(deviceID: deviceID)
                            }
                        }
                        
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .bold(isActive)
                            Text(isAvailable ? "\(sampleRate)" : "Unavailable")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                        }
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
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()

        }
        .onAppear {
            loadDevices()
            
            AudioManager.shared.monitorChanges {
                print("Reloading devices list")
                devicesReloadedAt = Date()
            }
            AudioManager.shared.monitorDefaultInputDeviceChanges {
                print("Reloading default input device")
                devicesReloadedAt = Date()
            }
        }
        .onChange(of: devicesReloadedAt) { _ in
            loadDevices() // Reload devices when the trigger changes
        }
    }
    
    private func moveDevices(fromOffsets indices: IndexSet, toOffset newOffset: Int) {
        devices.move(fromOffsets: indices, toOffset: newOffset)
        DeviceManager().saveDeviceOrder(devices.map { SavedDevice(name: $0.name) })
        
        AudioManager.shared.enforceDeviceOrder()
        
        currentDeviceID = AudioManager.shared.getCurrentInputDeviceID()
    }

    private func loadDevices() {
        let savedDevices = DeviceManager().loadDeviceOrder().map { $0.name }
        let availableDevices = AudioManager.shared.getAudioInputDevices()

        devices = savedDevices.map { name in
            if let availableDevice = availableDevices.first(where: { $0.name == name }) {
                return availableDevice
            } else {
                return AudioDevice(name: name, id: nil, sampleRate: nil)
            }
        }

        // Add any new available devices not in the saved list
        for device in availableDevices where !devices.contains(where: { $0.name == device.name }) {
            devices.append(device)
        }

        DeviceManager().saveDeviceOrder(devices.map { SavedDevice(name: $0.name) })
                
        currentDeviceID = AudioManager.shared.getCurrentInputDeviceID()
    }

    private func deleteDevice(at index: Int) {
        devices.remove(at: index)
        let devicesToSave = devices.map { SavedDevice(name: $0.name) }
        DeviceManager().saveDeviceOrder(devicesToSave)
    }

    private func getIconName(for deviceName: String) -> String {
        switch deviceName.lowercased() {
        case "macbook pro microphone":
            return "laptopcomputer"
        case let name where name.contains("webcam"):
            return "camera.fill"
        case let name where name.contains("microphone"):
            return "mic.fill"
        case let name where name.contains("line"):
            return "waveform.path.ecg"
        case let name where name.contains("soundflower"):
            return "arrow.up.left.and.arrow.down.right"
        case let name where name.contains("aggregate"):
            return "square.stack.3d.up.fill"
        default:
            return "mic.fill" // Default icon
        }
    }
}
