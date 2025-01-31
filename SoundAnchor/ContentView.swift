import SwiftUI
import CoreAudio

struct ContentView: View {
    @State private var inputDevices: [AudioDevice] = []
    @State private var outputDevices: [AudioDevice] = []
    @State private var currentInputDeviceID: AudioDeviceID?
    @State private var currentOutputDeviceID: AudioDeviceID?
    @State private var forceInputEnabled: Bool = AudioManager.shared.isForceInputEnabled
    @State private var forceOutputEnabled: Bool = AudioManager.shared.isForceOutputEnabled
    @State private var devicesReloadedAt: Date? = nil
    @State private var showingHelp = false

    @EnvironmentObject var appDelegate: AppDelegate
    
    var requestSizeUpdate: (() -> Void)?
    
    var body: some View {
        VStack {
            TopBarView(showingHelp: $showingHelp)
            List {
                DeviceListSection(
                    title: "Input Devices",
                    devices: inputDevices,
                    isForceEnabled: $forceInputEnabled,
                    headerToggleAction: { AudioManager.shared.isForceInputEnabled = $0 },
                    moveAction: moveInputDevices,
                    onTap: { deviceID in
                        forceInputEnabled = false
                        AudioManager.shared.setDefaultDevice(deviceID: deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
                    },
                    isActive: { deviceID in currentInputDeviceID == deviceID },
                    deleteAction: deleteInputDevice
                )
                DeviceListSection(
                    title: "Output Devices",
                    devices: outputDevices,
                    isForceEnabled: $forceOutputEnabled,
                    headerToggleAction: { AudioManager.shared.isForceOutputEnabled = $0 },
                    moveAction: moveOutputDevices,
                    onTap: { deviceID in
                        forceOutputEnabled = false
                        AudioManager.shared.setDefaultDevice(deviceID: deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
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
        }
        .frame(minWidth: 300, minHeight: 400)
        .onChange(of: devicesReloadedAt) { _ in loadDevices() }
    }
    
    private func moveInputDevices(fromOffsets indices: IndexSet, toOffset newOffset: Int) {
        inputDevices.move(fromOffsets: indices, toOffset: newOffset)
        DeviceManager().saveInputDeviceOrder(inputDevices.map { SavedDevice(name: $0.name) })
        AudioManager.shared.enforceInputDeviceOrder()
        currentInputDeviceID = AudioManager.shared.getCurrentDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    private func moveOutputDevices(fromOffsets indices: IndexSet, toOffset newOffset: Int) {
        outputDevices.move(fromOffsets: indices, toOffset: newOffset)
        DeviceManager().saveOutputDeviceOrder(outputDevices.map { SavedDevice(name: $0.name) })
        AudioManager.shared.enforceOutputDeviceOrder()
        currentOutputDeviceID = AudioManager.shared.getCurrentDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    private func loadDevices() {
        currentInputDeviceID = AudioManager.shared.getCurrentDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        currentOutputDeviceID = AudioManager.shared.getCurrentDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        
        let savedInputDevices = DeviceManager().loadInputDeviceOrder().map { $0.name }
        let savedOutputDevices = DeviceManager().loadOutputDeviceOrder().map { $0.name }
        
        let availableInputDevices = AudioManager.shared.getAudioDevices(scope: kAudioDevicePropertyScopeInput)
        let availableOutputDevices = AudioManager.shared.getAudioDevices(scope: kAudioDevicePropertyScopeOutput)

        inputDevices = mergeDevices(savedNames: savedInputDevices, available: availableInputDevices, ioType: "input")
        outputDevices = mergeDevices(savedNames: savedOutputDevices, available: availableOutputDevices, ioType: "output")
        
        DeviceManager().saveInputDeviceOrder(inputDevices.map { SavedDevice(name: $0.name) })
        DeviceManager().saveOutputDeviceOrder(outputDevices.map { SavedDevice(name: $0.name) })
        
        requestSizeUpdate?()
    }

    private func mergeDevices(savedNames: [String], available: [AudioDevice], ioType: String) -> [AudioDevice] {
        var result = savedNames.map { name in
            available.first(where: { $0.name == name })
            ?? AudioDevice(name: name, ioType: ioType, id: nil, transportType: nil)
        }
        for device in available where !result.contains(where: { $0.name == device.name }) {
            result.append(device)
        }
        return result
    }
    
    private func deleteInputDevice(_ device: AudioDevice) {
        guard let index = inputDevices.firstIndex(where: { $0.uniqueIdentifier == device.uniqueIdentifier }) else { return }
        inputDevices.remove(at: index)
        DeviceManager().saveInputDeviceOrder(inputDevices.map { SavedDevice(name: $0.name) })
    }

    private func deleteOutputDevice(_ device: AudioDevice) {
        guard let index = outputDevices.firstIndex(where: { $0.uniqueIdentifier == device.uniqueIdentifier }) else { return }
        outputDevices.remove(at: index)
        DeviceManager().saveOutputDeviceOrder(outputDevices.map { SavedDevice(name: $0.name) })
    }
}

// MARK: - Subviews

struct TopBarView: View {
    @Binding var showingHelp: Bool
    @EnvironmentObject var appDelegate: AppDelegate
    
    var body: some View {
        HStack {
            Text("SoundAnchor").fontWeight(.heavy)
            Spacer()
            Button(action: { showingHelp.toggle() }) {
                Image(systemName: "questionmark.circle").padding()
            }
            .frame(width: 24, height: 24)
            .buttonStyle(BorderlessButtonStyle())
            .popover(isPresented: $showingHelp) {
                Text("Reorder the list to set the priority of your devices, then enable \"Auto-switch\" to let SoundAnchor do the rest for you. The topmost available device will be forced automatically.")
                    .padding(12)
                    .frame(width: 300)
            }
            Button(action: {
                let menu = NSMenu(title: "Settings Menu")
                #if !APPSTORE
                menu.addItem(withTitle: "Check for Updates", action: #selector(appDelegate.checkForUpdates), keyEquivalent: "")
                #endif
                menu.addItem(withTitle: "Buy me an espresso", action: #selector(appDelegate.openDonateLink), keyEquivalent: "")
                menu.addItem(withTitle: "Quit", action: #selector(NSApplication.shared.terminate(_:)), keyEquivalent: "")
                if let contentView = NSApplication.shared.keyWindow?.contentView {
                    NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: contentView)
                }
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
            ForEach(Array(devices.enumerated()), id: \.element.uniqueIdentifier) { (index, device) in
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
            Toggle("Auto-switch", isOn: $isForceEnabled)
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
            
            Text("\(index + 1)")
                .foregroundColor(.secondary)
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
