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
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePopover)
        updateMenuBarContent(entries: [])

        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.contentViewController = NSHostingController(rootView: ContentView().environmentObject(state))
        showMainWindow()

        state.onMenuBarContentChange = { [weak self] entries in
            self?.updateMenuBarContent(entries: entries)
        }

        Task {
            await state.refreshAll()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    private func showMainWindow() {
        if mainWindow == nil {
            let controller = NSHostingController(rootView: ContentView().environmentObject(state))
            let window = NSWindow(contentViewController: controller)
            window.title = "Token Racing"
            window.setContentSize(NSSize(width: 400, height: 600))
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            mainWindow = window
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    private func updateMenuBarContent(entries: [MenuBarEntry]) {
        guard let button = statusItem?.button else { return }

        guard !entries.isEmpty else {
            button.image = nil
            button.attributedTitle = NSAttributedString(string: "")
            button.title = "🏁 0"
            return
        }

        button.image = nil
        button.title = ""
        button.attributedTitle = menuBarTitle(for: entries)
    }

    private func menuBarTitle(for entries: [MenuBarEntry]) -> NSAttributedString {
        let title = NSMutableAttributedString()
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]

        for (index, entry) in entries.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: "   ", attributes: textAttributes))
            }

            let attachment = NSTextAttachment()
            attachment.image = menuBarImage(handle: entry.handle, avatarDataURL: entry.avatarDataURL)
            attachment.bounds = NSRect(x: 0, y: -4, width: 18, height: 18)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: " \(entry.tokens.tokenAbbreviation)", attributes: textAttributes))
        }

        return title
    }

    private func menuBarImage(handle: String, avatarDataURL: String?) -> NSImage {
        let sourceImage = AvatarImageData.nsImage(from: avatarDataURL)

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        NSBezierPath(ovalIn: rect).addClip()
        if let sourceImage {
            sourceImage.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        } else {
            NSColor.systemBlue.setFill()
            rect.fill()
            drawInitials(for: handle, in: rect)
        }

        NSColor.white.withAlphaComponent(0.65).setStroke()
        let stroke = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        stroke.lineWidth = 1
        stroke.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func drawInitials(for handle: String, in rect: NSRect) {
        let initials = initials(for: handle)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7.5, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: initials, attributes: attributes)
        let textSize = text.size()
        let textRect = NSRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect)
    }

    private func initials(for handle: String) -> String {
        let parts = handle
            .split(separator: " ")
            .map { String($0.prefix(1)) }

        if parts.count >= 2 {
            return String(parts.prefix(2).joined()).uppercased()
        }

        return String(handle.prefix(2)).uppercased()
    }
}
