import Cocoa
import SwiftUI
import ServiceManagement
import UserNotifications
import Sentry

#if !APPSTORE
import Sparkle
#else
protocol SPUStandardUserDriverDelegate {}
protocol SPUUpdaterDelegate {}
#endif

class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupSentry()

        NSApp.setActivationPolicy(.accessory)
        
        // Create window
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.mic" , accessibilityDescription: nil)
            button.image?.isTemplate = true // Ensures proper rendering in light/dark mode
            button.action = #selector(togglePopover(_:))
        }
        
        // Initialize the popover
        popover = NSPopover()
        popover?.behavior = .transient // Allows auto-dismiss when clicking outside
        popover?.contentViewController = NSHostingController(rootView: ContentView().environmentObject(self))
        

        enforceDeviceOrder()

        addAppToLoginItems()

        requestNotificationPermissions()
        
#if !APPSTORE
        setupUpdater()
#endif
    }

#if !APPSTORE
    var softwareUpdater: SPUUpdater!
    
    func setupUpdater() {
        let updateDriver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: self)
        softwareUpdater = SPUUpdater(hostBundle: Bundle.main, applicationBundle: Bundle.main, userDriver: updateDriver, delegate: self)
    
        do {
            try softwareUpdater.start()
        } catch {
            NSLog("Failed to start software updater with error: \(error)")
        }
    }
    
    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        // We already request notifications permissions on boot
    }
    
    var supportsGentleScheduledUpdateReminders: Bool {
        return true
    }
    
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.setActivationPolicy(.regular)
        
        if !state.userInitiated {
            NSApp.dockTile.badgeLabel = "1"
            
            // Post a user notification
            // For banner style notification alerts, this may only trigger when the app is currently inactive.
            // For alert style notification alerts, this will trigger when the app is active or inactive.
            do {
                let content = UNMutableNotificationContent()
                content.title = "A new update is available"
                content.body = "Version \(update.displayVersionString) is now available"
                
                let request = UNNotificationRequest(identifier: "UpdateCheck", content: content, trigger: nil)
                
                UNUserNotificationCenter.current().add(request)
            }
        }
    }
        
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        NSApp.dockTile.badgeLabel = ""
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["UpdateCheck"])
    }
    
    func standardUserDriverWillFinishUpdateSession() {
        NSApp.setActivationPolicy(.accessory)
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == "UpdateCheck" && response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            softwareUpdater.checkForUpdates()
        }
        
        completionHandler()
    }
    
    @objc public func checkForUpdates() {
        softwareUpdater.checkForUpdates()
    }
    
#endif

    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem?.button, let popover = popover {
            if (popover.isShown) {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY) // Use .maxY for below the toolbar
                // Center the popover horizontally with the button
                if let popoverWindow = popover.contentViewController?.view.window {
                    let buttonFrame = button.window?.frame ?? .zero
                    let popoverFrame = popoverWindow.frame
                    let xPosition = buttonFrame.origin.x + (buttonFrame.width / 2) - (popoverFrame.width / 2)
                    let yPosition = buttonFrame.origin.y - popoverFrame.height - 2
                    popoverWindow.setFrame(NSRect(x: xPosition, y: yPosition, width: popoverFrame.width, height: popoverFrame.height), display: true)
                }
            }
        }
    }
    
    private func enforceDeviceOrder() {
        AudioManager.shared.monitorDefaultInputDeviceChanges {
            AudioManager.shared.enforceDeviceOrder()
        }
        AudioManager.shared.enforceDeviceOrder()
    }

    private func addAppToLoginItems() {
        do {
            if #available(macOS 13.0, *) {
                try SMAppService.mainApp.register()
            } else {
                // Fallback on earlier versions
            }
            print("Successfully added app to login items")
        } catch {
            print("Failed to add app to login items: \(error)")
        }
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permissions: \(error)")
            } else if granted {
                print("Notification permissions granted")
            } else {
                print("Notification permissions denied")
            }
        }
    }
    
    @objc public func openDonateLink() {
        if let url = Bundle.main.object(forInfoDictionaryKey: "DonateURL") as? String,
           let espressoURL = URL(string: url) {
            NSWorkspace.shared.open(espressoURL)
        }
    }
    
    func setupSentry() {
        SentrySDK.start { options in
            // Read from Info.plist
            options.dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String
        }
    }
}
