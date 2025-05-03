import SwiftUI
import CoreAudio
import FirebaseAnalytics

struct ContentView: View {
    @State private var inputDevices: [AudioDevice] = []
    @State private var outputDevices: [AudioDevice] = []
    @State private var currentInputDeviceID: AudioDeviceID?
    @State private var currentOutputDeviceID: AudioDeviceID?
    @State private var forceInputEnabled: Bool = AudioManager.shared.isForceInputEnabled
    @State private var forceOutputEnabled: Bool = AudioManager.shared.isForceOutputEnabled
    @State private var devicesReloadedAt: Date? = nil
    @State private var showingHelp = false
    @State private var showingDonationReminder = false

    @EnvironmentObject var appDelegate: AppDelegate
        
    var body: some View {
        VStack {
            TopBarView(showingHelp: $showingHelp)
            List {
                DeviceListSection(
                    title: "input_devices".localized,
                    devices: inputDevices,
                    isForceEnabled: $forceInputEnabled,
                    headerToggleAction: { value in
                        AudioManager.shared.isForceInputEnabled = value
                        Analytics.logEvent("toggle_force_input", parameters: ["enabled": value])
                    },
                    moveAction: moveInputDevices,
                    onTap: { deviceID in
                        forceInputEnabled = false
                        AudioManager.shared.setDefaultDevice(deviceID: deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
                        Analytics.logEvent("set_default_input_device", parameters: ["device_id": deviceID])
                    },
                    isActive: { deviceID in currentInputDeviceID == deviceID },
                    deleteAction: deleteInputDevice
                )
                DeviceListSection(
                    title: "output_devices".localized,
                    devices: outputDevices,
                    isForceEnabled: $forceOutputEnabled,
                    headerToggleAction: { value in
                        AudioManager.shared.isForceOutputEnabled = value
                        Analytics.logEvent("toggle_force_output", parameters: ["enabled": value])
                    },
                    moveAction: moveOutputDevices,
                    onTap: { deviceID in
                        forceOutputEnabled = false
                        AudioManager.shared.setDefaultDevice(deviceID: deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
                        Analytics.logEvent("set_default_output_device", parameters: ["device_id": deviceID])
                    },
                    isActive: { deviceID in currentOutputDeviceID == deviceID },
                    deleteAction: deleteOutputDevice
                )
                Spacer().frame(height: 0)
            }
            .listStyle(PlainListStyle())
        }
        .onAppear {
            loadDevices()
            AudioManager.shared.monitorAnyDevicesChanges { devicesReloadedAt = Date() }
            AudioManager.shared.monitorDefaultDeviceChanges(selector: kAudioHardwarePropertyDefaultOutputDevice) { devicesReloadedAt = Date() }
            AudioManager.shared.monitorDefaultDeviceChanges(selector: kAudioHardwarePropertyDefaultInputDevice) { devicesReloadedAt = Date() }
            Analytics.logEvent("app_opened", parameters: nil)
            
            #if !APPSTORE
            checkAndShowDonationReminder()
            #endif
        }
        .frame(minWidth: 300, minHeight: 400)
        .onChange(of: devicesReloadedAt) { _ in loadDevices() }
        .sheet(isPresented: $showingDonationReminder) {
            DonationReminderDialog(isPresented: $showingDonationReminder)
        }
    }
    
    private func checkAndShowDonationReminder() {
        let hasDonated = UserDefaults.standard.bool(forKey: "hasDonated")
        if hasDonated { return }
        
        let lastReminder = UserDefaults.standard.object(forKey: "lastDonationReminder") as? Date ?? Date.distantPast
        let daysSinceLastReminder = Calendar.current.dateComponents([.day], from: lastReminder, to: Date()).day ?? 0
        
        if daysSinceLastReminder >= 7 {
            showingDonationReminder = true
        }
    }
    
    private func moveInputDevices(fromOffsets indices: IndexSet, toOffset newOffset: Int) {
        inputDevices.move(fromOffsets: indices, toOffset: newOffset)
        DeviceManager().saveInputDeviceOrder(inputDevices.map { SavedDevice(name: $0.name, uid: $0.uid) })
        AudioManager.shared.enforceInputDeviceOrder()
        currentInputDeviceID = AudioManager.shared.getCurrentDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        Analytics.logEvent("move_input_devices", parameters: nil)
    }

    private func moveOutputDevices(fromOffsets indices: IndexSet, toOffset newOffset: Int) {
        outputDevices.move(fromOffsets: indices, toOffset: newOffset)
        DeviceManager().saveOutputDeviceOrder(outputDevices.map { SavedDevice(name: $0.name, uid: $0.uid) })
        AudioManager.shared.enforceOutputDeviceOrder()
        currentOutputDeviceID = AudioManager.shared.getCurrentDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        Analytics.logEvent("move_output_devices", parameters: nil)
    }

    private func loadDevices() {
        currentInputDeviceID = AudioManager.shared.getCurrentDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        currentOutputDeviceID = AudioManager.shared.getCurrentDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        
        let savedInputDevices = DeviceManager().loadInputDeviceOrder()
        let savedOutputDevices = DeviceManager().loadOutputDeviceOrder()
        
        let availableInputDevices = AudioManager.shared.getAudioDevices(scope: kAudioDevicePropertyScopeInput)
        let availableOutputDevices = AudioManager.shared.getAudioDevices(scope: kAudioDevicePropertyScopeOutput)

        inputDevices = mergeDevices(savedDevices: savedInputDevices, available: availableInputDevices, ioType: "input")
        outputDevices = mergeDevices(savedDevices: savedOutputDevices, available: availableOutputDevices, ioType: "output")
        
        DeviceManager().saveInputDeviceOrder(inputDevices.map { SavedDevice(name: $0.name, uid: $0.uid) })
        DeviceManager().saveOutputDeviceOrder(outputDevices.map { SavedDevice(name: $0.name, uid: $0.uid) })
    }

    private func mergeDevices(savedDevices: [SavedDevice], available: [AudioDevice], ioType: String) -> [AudioDevice] {
        var result = savedDevices.map { savedDevice in
            available.first(where: { $0.uid == savedDevice.uid })
            ?? AudioDevice(
                name: savedDevice.name,
                ioType: ioType,
                id: nil,
                transportType: nil,
                manufacturer: "-",
                uid: savedDevice.uid
            )
        }
        for device in available where !result.contains(where: { $0.uid == device.uid }) {
            result.append(device)
        }
        return result
    }
    
    private func deleteInputDevice(_ device: AudioDevice) {
        guard let index = inputDevices.firstIndex(where: { $0.uid == device.uid }) else { return }
        inputDevices.remove(at: index)
        DeviceManager().saveInputDeviceOrder(inputDevices.map { SavedDevice(name: $0.name, uid: $0.uid) })
        Analytics.logEvent("delete_input_device", parameters: ["device_name": device.name])
    }

    private func deleteOutputDevice(_ device: AudioDevice) {
        guard let index = outputDevices.firstIndex(where: { $0.uid == device.uid }) else { return }
        outputDevices.remove(at: index)
        DeviceManager().saveOutputDeviceOrder(outputDevices.map { SavedDevice(name: $0.name, uid: $0.uid) })
        Analytics.logEvent("delete_output_device", parameters: ["device_name": device.name])
    }
}

// MARK: - Subviews

struct TopBarView: View {
    @Binding var showingHelp: Bool
    @State private var showingDonation = false
    @EnvironmentObject var appDelegate: AppDelegate
    
    var body: some View {
        HStack {
            Text("app_title".localized).fontWeight(.heavy)
            Spacer()
            #if !APPSTORE
            Button(action: { showingDonation.toggle() }) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .padding()
            }
            .frame(width: 24, height: 24)
            .buttonStyle(BorderlessButtonStyle())
            .popover(isPresented: $showingDonation) {
                DonationDialog(isPresented: $showingDonation)
            }
            #endif
            Button(action: { showingHelp.toggle() }) {
                Image(systemName: "questionmark.circle").padding()
            }
            .frame(width: 24, height: 24)
            .buttonStyle(BorderlessButtonStyle())
            .popover(isPresented: $showingHelp) {
                Text("reorder_devices_help".localized)
                    .padding(12)
                    .frame(width: 300)
            }
            Button(action: {
                appDelegate.showSettingsMenu()
                Analytics.logEvent("settings_menu_opened", parameters: nil)
            }) {
                Image(systemName: "gearshape")
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            .frame(width: 24, height: 24)
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct DeviceListSection: View {
    let title: String
    let devices: [AudioDevice]
    @Binding var isForceEnabled: Bool
    let headerToggleAction: (Bool) -> Void
    let moveAction: (IndexSet, Int) -> Void
    let onTap: (AudioDeviceID) -> Void
    let isActive: (AudioDeviceID?) -> Bool
    let deleteAction: (AudioDevice) -> Void
    
    var body: some View {
        Section(header: headerView) {
            ForEach(Array(devices.enumerated()), id: \.element.uid) { (index, device) in
                DeviceRowView(
                    device: device,
                    index: index,
                    isActive: isActive(device.id),
                    onTap: { if let id = device.id { onTap(id) } },
                    deleteAction: { deleteAction(device) },
                    iconName: device.ioType == "input"
                        ? getInputIconName(name: device.name, transportType: device.transportType)
                        : getOutputIconName(name: device.name, transportType: device.transportType)
                )
            }
            .onMove(perform: moveAction)
        }
    }
    
    private var headerView: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("enable_auto_switch".localized, isOn: $isForceEnabled)
                .onChange(of: isForceEnabled, perform: headerToggleAction)
        }
    }
}

struct DeviceRowView: View {
    let device: AudioDevice
    let index: Int
    let isActive: Bool
    let onTap: () -> Void
    let deleteAction: () -> Void
    let iconName: String
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        let isAvailable = device.id != nil
        
        HStack {
            ZStack {
                Circle()
                    .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 24, height: 24)
                Image(systemName: iconName)
                    .foregroundColor(isActive ? .white : .primary)
                    .frame(width: 16, height: 16)
            }
            .onTapGesture(perform: onTap)
            
            VStack(alignment: .leading) {
                Text(device.name).fontWeight(isActive ? .bold : .regular)
            }
            
            Spacer()
            
            // Show delete icon only on hover if device is unavailable
            if !isAvailable && isHovering {
                Button(action: deleteAction) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .onHover { hovering in
                    if hovering {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .opacity(isAvailable ? 1 : 0.5)
        .onHover { hovering in
            isHovering = hovering
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .background(isHovering ? Color.secondary.opacity(0.05) : Color.clear)
    }
}

// MARK: - Icon Helpers

func getInputIconName(name: String, transportType: UInt32?) -> String {
    switch (transportType) {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypePCI,
             kAudioDeviceTransportTypeAggregate: return "mic.fill"
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI: return "tv"
        case kAudioDeviceTransportTypeAirPlay: return "airplay.audio"
        case kAudioDeviceTransportTypeAVB: return "network"
        case kAudioDeviceTransportTypeVirtual: return "waveform"
        case kAudioDeviceTransportTypeUnknown: return "mic.fill"
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless: return "iphone"
        default: return "mic.fill"
    }
}

func getOutputIconName(name: String, transportType: UInt32?) -> String {
    switch (transportType) {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypePCI,
             kAudioDeviceTransportTypeAggregate: return "speaker.wave.2"
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI: return "tv"
        case kAudioDeviceTransportTypeAirPlay: return "airplay.audio"
        case kAudioDeviceTransportTypeAVB: return "network"
        case kAudioDeviceTransportTypeVirtual: return "waveform"
        case kAudioDeviceTransportTypeUnknown: return "speaker.wave.2"
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless: return "iphone"
        default: return "speaker.wave.2"
    }
}
