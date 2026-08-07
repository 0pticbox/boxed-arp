import Cocoa
import CoreAudioKit
import AudioToolbox

final class BoxedArpViewController: AUViewController, AUAudioUnitFactory {
    private var audioUnit: BoxedArpAudioUnit?
    private var observerToken: AUParameterObserverToken?

    private let pattern = NSPopUpButton()
    private let division = NSPopUpButton()
    private let octaves = NSSlider(value: 1, minValue: 1, maxValue: 4, target: nil, action: nil)
    private let gate = NSSlider(value: 0.72, minValue: 0.05, maxValue: 0.98, target: nil, action: nil)
    private let swing = NSSlider(value: 0, minValue: 0, maxValue: 0.45, target: nil, action: nil)
    private let latch = NSButton(checkboxWithTitle: "LATCH", target: nil, action: nil)
    private let sync = NSButton(checkboxWithTitle: "HOST SYNC", target: nil, action: nil)
    private let bpm = NSSlider(value: 120, minValue: 20, maxValue: 400, target: nil, action: nil)
    private let bpmReadout = NSTextField(labelWithString: "120 BPM")
    private let scaleLock = NSButton(checkboxWithTitle: "SCALE LOCK", target: nil, action: nil)
    private let rootMenu = NSPopUpButton()
    private let scaleMenu = NSPopUpButton()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 390))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.045, alpha: 1).cgColor
        self.view = root
        preferredContentSize = NSSize(width: 720, height: 390)

        let title = label("BOXED ARP", 27, .bold)
        title.frame = NSRect(x: 24, y: 336, width: 300, height: 36)
        root.addSubview(title)

        let status = label("LOGIC MIDI FX  /  OPTC", 11, .medium, 0.68)
        status.frame = NSRect(x: 26, y: 316, width: 300, height: 18)
        root.addSubview(status)

        let screen = NSView(frame: NSRect(x: 474, y: 246, width: 220, height: 112))
        screen.wantsLayer = true
        screen.layer?.backgroundColor = NSColor(calibratedRed: 0.025, green: 0.075, blue: 0.055, alpha: 1).cgColor
        screen.layer?.borderColor = NSColor(calibratedWhite: 0.32, alpha: 1).cgColor
        screen.layer?.borderWidth = 1
        root.addSubview(screen)
        let screenTitle = label("ARP ENGINE ONLINE", 13, .bold)
        screenTitle.textColor = NSColor(calibratedRed: 0.65, green: 1.0, blue: 0.75, alpha: 1)
        screenTitle.frame = NSRect(x: 14, y: 70, width: 190, height: 22)
        screen.addSubview(screenTitle)
        let screenSub = label("MIDI OUT: BOXED ARP OUT", 10, .regular, 0.72)
        screenSub.frame = NSRect(x: 14, y: 45, width: 190, height: 18)
        screen.addSubview(screenSub)
        let screenSub2 = label("1/4 → 1/64T   •   1–4 OCT", 10, .regular, 0.72)
        screenSub2.frame = NSRect(x: 14, y: 24, width: 190, height: 18)
        screen.addSubview(screenSub2)

        pattern.addItems(withTitles: ["UP", "DOWN", "UP-DOWN", "RANDOM"])
        division.addItems(withTitles: ["1/4", "1/8", "1/8T", "1/16", "1/16T", "1/32", "1/32T", "1/64", "1/64T"])
        rootMenu.addItems(withTitles: ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])
        scaleMenu.addItems(withTitles: ["CHROMATIC", "MAJOR", "MINOR", "DORIAN", "LYDIAN", "HIRAJOSHI", "BHAIRAV", "TODI", "MARWA", "MALKAUNS", "HAMSADHWANI", "CHARUKESHI"])

        addCaption("PATTERN", x: 24, y: 280); pattern.frame = NSRect(x: 24, y: 248, width: 160, height: 28); root.addSubview(pattern)
        addCaption("RATE", x: 205, y: 280); division.frame = NSRect(x: 205, y: 248, width: 120, height: 28); root.addSubview(division)
        addCaption("OCTAVES", x: 346, y: 280); octaves.frame = NSRect(x: 346, y: 250, width: 105, height: 24); root.addSubview(octaves)

        addCaption("GATE", x: 24, y: 207); gate.frame = NSRect(x: 24, y: 176, width: 192, height: 24); root.addSubview(gate)
        addCaption("SWING", x: 238, y: 207); swing.frame = NSRect(x: 238, y: 176, width: 192, height: 24); root.addSubview(swing)
        latch.frame = NSRect(x: 474, y: 180, width: 105, height: 22); root.addSubview(latch)
        sync.frame = NSRect(x: 585, y: 180, width: 110, height: 22); root.addSubview(sync)

        addCaption("FREE BPM", x: 24, y: 132); bpm.frame = NSRect(x: 24, y: 100, width: 250, height: 24); root.addSubview(bpm)
        bpmReadout.font = .monospacedSystemFont(ofSize: 12, weight: .bold); bpmReadout.textColor = .white
        bpmReadout.frame = NSRect(x: 285, y: 101, width: 92, height: 22); root.addSubview(bpmReadout)

        scaleLock.frame = NSRect(x: 403, y: 101, width: 112, height: 22); root.addSubview(scaleLock)
        rootMenu.frame = NSRect(x: 524, y: 96, width: 72, height: 28); root.addSubview(rootMenu)
        scaleMenu.frame = NSRect(x: 604, y: 96, width: 92, height: 28); root.addSubview(scaleMenu)

        let footer = label("Hold a chord in Logic. BOXED ARP consumes its note input and emits the arpeggio to the instrument below it.", 11, .regular, 0.65)
        footer.frame = NSRect(x: 24, y: 32, width: 670, height: 32)
        root.addSubview(footer)

        [pattern, division, octaves, gate, swing, latch, sync, bpm, scaleLock, rootMenu, scaleMenu].forEach {
            $0.target = self
            $0.action = #selector(controlChanged(_:))
        }
        sync.state = .on
        refreshControls()
    }

    private func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight, _ white: CGFloat = 1) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .monospacedSystemFont(ofSize: size, weight: weight)
        field.textColor = NSColor(calibratedWhite: white, alpha: 1)
        return field
    }

    private func addCaption(_ text: String, x: CGFloat, y: CGFloat) {
        let c = label(text, 10, .medium, 0.68)
        c.frame = NSRect(x: x, y: y, width: 120, height: 18)
        view.addSubview(c)
    }

    func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try BoxedArpAudioUnit(componentDescription: componentDescription)
        audioUnit = unit
        installObserver()
        if isViewLoaded { refreshControls() }
        return unit
    }

    private func parameter(_ address: BAParameterAddress) -> AUParameter? {
        audioUnit?.parameterTree?.parameter(withAddress: address.rawValue)
    }

    private func installObserver() {
        guard let tree = audioUnit?.parameterTree else { return }
        if let token = observerToken { tree.removeParameterObserver(token) }
        observerToken = tree.token(byAddingParameterObserver: { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshControls() }
        })
    }

    private func refreshControls() {
        guard isViewLoaded else { return }
        pattern.selectItem(at: Int(parameter(.pattern)?.value ?? 0))
        division.selectItem(at: Int(parameter(.division)?.value ?? 3))
        octaves.doubleValue = Double(parameter(.octaves)?.value ?? 1)
        gate.doubleValue = Double(parameter(.gate)?.value ?? 0.72)
        swing.doubleValue = Double(parameter(.swing)?.value ?? 0)
        latch.state = (parameter(.latch)?.value ?? 0) >= 0.5 ? .on : .off
        sync.state = (parameter(.hostSync)?.value ?? 1) >= 0.5 ? .on : .off
        bpm.doubleValue = Double(parameter(.freeBPM)?.value ?? 120)
        bpmReadout.stringValue = "\(Int(bpm.doubleValue.rounded())) BPM"
        scaleLock.state = (parameter(.scaleLock)?.value ?? 0) >= 0.5 ? .on : .off
        rootMenu.selectItem(at: Int(parameter(.root)?.value ?? 0))
        scaleMenu.selectItem(at: Int(parameter(.scale)?.value ?? 0))
    }

    private func set(_ address: BAParameterAddress, _ value: AUValue) {
        parameter(address)?.setValue(value, originator: observerToken)
    }

    @objc private func controlChanged(_ sender: Any?) {
        if sender as AnyObject === pattern { set(.pattern, AUValue(pattern.indexOfSelectedItem)) }
        else if sender as AnyObject === division { set(.division, AUValue(division.indexOfSelectedItem)) }
        else if sender as AnyObject === octaves { set(.octaves, AUValue(octaves.doubleValue.rounded())) }
        else if sender as AnyObject === gate { set(.gate, AUValue(gate.doubleValue)) }
        else if sender as AnyObject === swing { set(.swing, AUValue(swing.doubleValue)) }
        else if sender as AnyObject === latch { set(.latch, latch.state == .on ? 1 : 0) }
        else if sender as AnyObject === sync { set(.hostSync, sync.state == .on ? 1 : 0) }
        else if sender as AnyObject === bpm {
            set(.freeBPM, AUValue(bpm.doubleValue.rounded()))
            bpmReadout.stringValue = "\(Int(bpm.doubleValue.rounded())) BPM"
        }
        else if sender as AnyObject === scaleLock { set(.scaleLock, scaleLock.state == .on ? 1 : 0) }
        else if sender as AnyObject === rootMenu { set(.root, AUValue(rootMenu.indexOfSelectedItem)) }
        else if sender as AnyObject === scaleMenu { set(.scale, AUValue(scaleMenu.indexOfSelectedItem)) }
    }
}
