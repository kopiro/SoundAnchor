import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AudioManager.shared.monitorDefaultInputDeviceChanges {
            AudioManager.shared.enforceDeviceOrder()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "1.circle" , accessibilityDescription: nil)
            button.image?.isTemplate = true // Ensures proper rendering in light/dark mode
            button.action = #selector(togglePopover(_:))
        }
        
        // Initialize the popover
        popover = NSPopover()
        popover?.behavior = .transient // Allows auto-dismiss when clicking outside
        popover?.contentViewController = NSHostingController(rootView: ContentView())
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem?.button, let popover = popover {
            if popover.isShown {
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
}
