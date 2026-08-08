import Cocoa
import AudioToolbox

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 0, y: 0, width: 650, height: 410)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered,
                          defer: false)
        window.center()
        window.title = "BOXED ARP"
        window.isReleasedWhenClosed = false

        let view = NSView(frame: rect)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.04, alpha: 1).cgColor

        let title = NSTextField(labelWithString: "BOXED ARP")
        title.font = .monospacedSystemFont(ofSize: 34, weight: .bold)
        title.textColor = .white
        title.frame = NSRect(x: 38, y: 322, width: 340, height: 46)
        view.addSubview(title)

        let badge = NSTextField(labelWithString: "OPTICBOX PLUGINS  •  GARAGEBAND + LOGIC")
        badge.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        badge.textColor = NSColor(calibratedWhite: 0.72, alpha: 1)
        badge.frame = NSRect(x: 40, y: 294, width: 500, height: 22)
        view.addSubview(badge)

        let instrumentTitle = NSTextField(labelWithString: "INSTRUMENT  •  GarageBand + Logic")
        instrumentTitle.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        instrumentTitle.textColor = .white
        instrumentTitle.frame = NSRect(x: 40, y: 242, width: 520, height: 22)
        view.addSubview(instrumentTitle)

        let instrumentBody = NSTextField(wrappingLabelWithString: "Built-in BOXED ARP synth + arpeggiator. Load it from AU Instruments → OPTC → BOXED ARP on a Software Instrument track.")
        instrumentBody.font = .systemFont(ofSize: 13)
        instrumentBody.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        instrumentBody.frame = NSRect(x: 40, y: 184, width: 565, height: 52)
        view.addSubview(instrumentBody)

        let midiTitle = NSTextField(labelWithString: "MIDI FX  •  Logic Pro")
        midiTitle.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        midiTitle.textColor = .white
        midiTitle.frame = NSRect(x: 40, y: 140, width: 520, height: 22)
        view.addSubview(midiTitle)

        let midiBody = NSTextField(wrappingLabelWithString: "MIDI-only arpeggiator that can drive another Logic instrument. Load it from MIDI FX → Audio Units → OPTC → BOXED ARP.")
        midiBody.font = .systemFont(ofSize: 13)
        midiBody.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        midiBody.frame = NSRect(x: 40, y: 82, width: 565, height: 52)
        view.addSubview(midiBody)

        let info = NSTextField(labelWithString: "Components: aumu / BARP / OPTC   +   aumi / BARP / OPTC")
        info.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        info.textColor = NSColor(calibratedWhite: 0.58, alpha: 1)
        info.frame = NSRect(x: 40, y: 50, width: 560, height: 20)
        view.addSubview(info)

        let quit = NSButton(title: "CLOSE", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        quit.frame = NSRect(x: 40, y: 16, width: 96, height: 30)
        view.addSubview(quit)

        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
