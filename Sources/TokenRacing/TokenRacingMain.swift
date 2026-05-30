import AppKit
import Darwin
import SwiftUI

@main
final class TokenRacingMain {
    static func main() {
        if CommandLine.arguments.contains("--usage-fixture") {
            exit(UsageFixtureCheck.run(arguments: CommandLine.arguments))
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.title = "🏁 0"

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 390, height: 620)
        popover.contentViewController = NSHostingController(rootView: ContentView().environmentObject(state))

        state.onMenuBarTitleChange = { [weak self] title in
            self?.statusItem?.button?.title = title
        }

        Task {
            await state.refreshAll()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
