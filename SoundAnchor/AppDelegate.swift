import Cocoa
import SwiftUI
import ServiceManagement
import UserNotifications
import CoreAudio
import FirebaseCore
import FirebaseAnalytics

#if !APPSTORE
import Sparkle
#else
protocol SPUStandardUserDriverDelegate {}
protocol SPUUpdaterDelegate {}
#endif

class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    
    var isFirstLaunch: Bool = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(
            defaults: ["NSApplicationCrashOnExceptions" : true]
        )
        
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        
        FirebaseApp.configure()

        NSApp.setActivationPolicy(.accessory)
        
        // Create window
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.mic" , accessibilityDescription: nil)
            button.image?.isTemplate = true // Ensures proper rendering in light/dark mode
            button.action = #selector(togglePopover(_:))
        }

        let contentView = ContentView().environmentObject(self)
        
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: contentView)
        
        AudioManager.shared.continuoslyEnforceDeviceOrder()

        if isFirstLaunch && !isAppInLoginItems() {
            askToAddToLoginItems()
        }

        requestNotificationPermissions()
        
#if !APPSTORE
        setupUpdater()
#endif

        if isFirstLaunch {
            print("Launching app first time")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.togglePopover(nil)
            }
        }
    }

    private func askToAddToLoginItems() {
        let alert = NSAlert()
        alert.messageText = "Add to Login Items?"
        alert.informativeText = "Would you like SoundAnchor to start automatically when you log in? This will help ensure your audio devices are always managed correctly."
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            addAppToLoginItems()
        }
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
        Analytics.logEvent("check_for_updates", parameters: nil)
    }
    
#endif

    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem?.button, let popover = popover {
            if (popover.isShown) {
                popover.performClose(sender)
                Analytics.logEvent("popover_closed", parameters: nil)
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
                Analytics.logEvent("popover_opened", parameters: nil)
            }
        }
    }

    private func addAppToLoginItems() {
        do {
            if #available(macOS 13.0, *) {
                try SMAppService.mainApp.register()
                Analytics.logEvent("add_to_login_items_success", parameters: nil)
            } else {
                // Fallback on earlier versions
            }
            print("Successfully added app to login items")
        } catch {
            print("Failed to add app to login items: \(error)")
            Analytics.logEvent("add_to_login_items_failure", parameters: ["error": error.localizedDescription])
        }
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permissions: \(error)")
                Analytics.logEvent("notification_permission_error", parameters: ["error": error.localizedDescription])
            } else if granted {
                print("Notification permissions granted")
                Analytics.logEvent("notification_permission_granted", parameters: nil)
            } else {
                print("Notification permissions denied")
                Analytics.logEvent("notification_permission_denied", parameters: nil)
            }
        }
    }
    
    @objc public func openDonateLink() {
        if let url = Bundle.main.object(forInfoDictionaryKey: "DonateURL") as? String,
           let espressoURL = URL(string: url) {
            NSWorkspace.shared.open(espressoURL)
            Analytics.logEvent("open_donate_link", parameters: nil)
        }
    }
    
    private func isAppInLoginItems() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
    
    private func removeFromLoginItems() {
        do {
            if #available(macOS 13.0, *) {
                try SMAppService.mainApp.unregister()
                Analytics.logEvent("remove_from_login_items_success", parameters: nil)
            }
        } catch {
            print("Failed to remove app from login items: \(error)")
            Analytics.logEvent("remove_from_login_items_failure", parameters: ["error": error.localizedDescription])
        }
    }

    @objc private func toggleLoginItems() {
        if isAppInLoginItems() {
            removeFromLoginItems()
        } else {
            addAppToLoginItems()
        }
    }

    @objc func showSettingsMenu() {
        let menu = NSMenu(title: "Settings Menu")
        #if !APPSTORE
        menu.addItem(withTitle: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "Buy me an espresso", action: #selector(openDonateLink), keyEquivalent: "")
        #endif
        menu.addItem(withTitle: isAppInLoginItems() ? "Remove from Login Items" : "Add to Login Items", 
                    action: #selector(toggleLoginItems), 
                    keyEquivalent: "")
        menu.addItem(withTitle: "Get support", action: #selector(getSupport), keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.shared.terminate(_:)), keyEquivalent: "")
        if let contentView = NSApplication.shared.keyWindow?.contentView {
            NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: contentView)
        }
        Analytics.logEvent("show_settings_menu", parameters: nil)
    }
    
    @objc func getSupport() {
        if let email = Bundle.main.object(forInfoDictionaryKey: "DeveloperEmail") as? String,
           let mailURL = URL(string: "mailto:\(email)") {
            NSWorkspace.shared.open(mailURL)
            Analytics.logEvent("contact_developer", parameters: nil)
        }
    }

}
