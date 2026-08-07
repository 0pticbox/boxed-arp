import Cocoa
import AudioToolbox

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 0, y: 0, width: 560, height: 330)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered,
                          defer: false)
        window.center()
        window.title = "BOXED ARP"
        window.isReleasedWhenClosed = false

        let view = NSView(frame: rect)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.045, alpha: 1).cgColor

        let title = NSTextField(labelWithString: "BOXED ARP")
        title.font = .monospacedSystemFont(ofSize: 31, weight: .bold)
        title.textColor = .white
        title.frame = NSRect(x: 34, y: 245, width: 300, height: 42)
        view.addSubview(title)

        let badge = NSTextField(labelWithString: "OPTICBOX PLUGINS  •  LOGIC MIDI FX")
        badge.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        badge.textColor = NSColor(calibratedWhite: 0.72, alpha: 1)
        badge.frame = NSRect(x: 36, y: 220, width: 420, height: 22)
        view.addSubview(badge)

        let body = NSTextField(wrappingLabelWithString: "The BOXED ARP Audio Unit is bundled with this app. Keep this app in your Applications folder and open it once after installing. Then restart Logic Pro and add BOXED ARP from the MIDI FX Audio Units menu.")
        body.font = .systemFont(ofSize: 14)
        body.textColor = .white
        body.frame = NSRect(x: 36, y: 115, width: 480, height: 84)
        view.addSubview(body)

        let info = NSTextField(labelWithString: "Component: aumi / BARP / OPTC")
        info.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        info.textColor = NSColor(calibratedWhite: 0.65, alpha: 1)
        info.frame = NSRect(x: 36, y: 78, width: 350, height: 22)
        view.addSubview(info)

        let quit = NSButton(title: "CLOSE", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        quit.frame = NSRect(x: 36, y: 30, width: 96, height: 32)
        view.addSubview(quit)

        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
