import AppKit
import AudioToolbox
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

final class ArpViewModel: ObservableObject {
    @Published var osc1Wave = 0
    @Published var osc2Wave = 1
    @Published var oscBlend: Float = 0.28
    @Published var detune: Float = 7
    @Published var attack: Float = 0.008
    @Published var decay: Float = 0.18
    @Published var sustain: Float = 0.72
    @Published var release: Float = 0.20
    @Published var cutoff: Float = 7200
    @Published var resonance: Float = 0.15

    @Published var pattern = 2
    @Published var rate = 4
    @Published var arpTimingMode = 0
    @Published var freeRateHz: Float = 8.0
    @Published var octaves = 2
    @Published var gate: Float = 0.62
    @Published var swing: Float = 0
    @Published var latch = false
    @Published var output: Float = 0.78
    @Published var arpEnabled = true

    @Published var tempoBPM: Float = 120
    @Published var tempoText = "120.0"
    @Published var chordRoot = 0
    @Published var chordPreset = 0
    @Published var scalePreset = 0

    @Published var delayEnabled = false
    @Published var delayTime: Float = 0.32
    @Published var delayFeedback: Float = 0.38
    @Published var delayTone: Float = 0.42
    @Published var delayMix: Float = 0.24
    @Published var midiOutEnabled = true
    @Published var midiCaptureActive = false
    @Published var capturedMIDIEventCount = 0
    @Published var midiExportStatus = "MIDI READY"

    @Published var currentStep = -1
    @Published var currentNote = -1
    @Published var heldNotes = 0
    @Published var currentTempo: Double = 120
    @Published var animationPhase: Double = 0
    @Published var interactionPulse: Double = 0
    @Published var skinIndex: Int
    @Published var selectedPresetIndex = 0
    @Published var userPresets: [BoxedArpUserPreset] = []
    @Published var presetStatus = "CUSTOM"

    let waveNames = ["SAW", "SQUARE", "SINE"]
    let patternNames = ["UP", "DOWN", "UP/DN", "RANDOM"]
    let rateNames = ["1/4", "1/4T", "1/8", "1/8T", "1/16", "1/16T", "1/32", "1/32T", "1/64T"]
    let rootNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let chordNames = ["OFF", "MAJOR", "MINOR", "MAJ7", "MIN7", "DOM7", "SUS2", "SUS4", "POWER"]
    let scaleNames = ["OFF", "LYDIAN", "DORIAN", "PHRYGIAN", "HARM MIN", "WHOLE TONE", "HIRAJOSHI", "MAJOR PENT", "IONIAN", "AEOLIAN", "MIXOLYDIAN", "LOCRIAN", "MELODIC MIN", "LYDIAN DOM", "PHRYG DOM", "DORIAN b2", "MIXO b6", "LOCRIAN #2", "ALTERED", "DOUBLE HARM", "HUNGARIAN MIN", "NEAPOLITAN MIN", "NEAPOLITAN MAJ", "ENIGMATIC", "PROMETHEUS", "AUGMENTED", "DIM H-W", "DIM W-H", "CHROMATIC", "MINOR PENT", "BLUES", "IN SEN", "IWATO", "KUMOI", "HAMSADHWANI", "SHIVARANJANI", "MALKAUNS", "BHAIRAV", "TODI", "MARWA", "CHARUKESHI", "AHIR BHAIRAV", "µ NEUTRAL DOR", "µ NEUTRAL PHR", "µ SHRUTI BHAIRAV", "µ SHRUTI TODI", "µ JUST MAJOR", "µ JUST MINOR", "µ 19EDO DORIAN"]

    private let audioUnit: BoxedArpAudioUnit
    private var parameterByID: [String: AUParameter] = [:]
    private var observerToken: AUParameterObserverToken?
    private var displayTimer: Timer?
    private var tapTimes: [TimeInterval] = []
    private var capturedMIDIEvents: [BoxedArpMIDIEvent] = []
    private let userPresetsKey = "boxedArpUserPresetsV2"
    private let legacyMemoryKey = "boxedArpMemoryBankV1"
    private var isApplyingSnapshot = false

    init(audioUnit: BoxedArpAudioUnit) {
        self.audioUnit = audioUnit
        self.skinIndex = min(PicoSkin.skins.count - 1, max(0, UserDefaults.standard.integer(forKey: "boxedArpSkin")))

        if let tree = audioUnit.parameterTree {
            for parameter in tree.allParameters {
                parameterByID[parameter.identifier] = parameter
            }
            observerToken = tree.token(byAddingParameterObserver: { [weak self] address, value in
                DispatchQueue.main.async {
                    self?.receiveParameter(address: address, value: value)
                }
            })
        }

        syncAllParameters()
        loadUserPresets()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            currentStep = audioUnit.currentStepForUI
            currentNote = audioUnit.currentNoteForUI
            heldNotes = audioUnit.heldNoteCountForUI
            currentTempo = audioUnit.currentTempoForUI
            drainMIDICaptureEvents()
            midiCaptureActive = audioUnit.midiCaptureActive
            animationPhase += 1.0 / 30.0
            interactionPulse = max(0, interactionPulse - 0.08)
        }
    }

    deinit {
        displayTimer?.invalidate()
        if let observerToken, let tree = audioUnit.parameterTree {
            tree.removeParameterObserver(observerToken)
        }
    }


    var freeRateSliderPosition: Float {
        let minimum: Float = 0.5
        let maximum: Float = 50.0
        let clamped = min(maximum, max(minimum, freeRateHz))
        return log(clamped / minimum) / log(maximum / minimum)
    }

    var freeRateDisplay: String {
        freeRateHz < 10 ? String(format: "%.1f Hz", freeRateHz) : String(format: "%.0f Hz", freeRateHz)
    }

    var freeRateStepDisplay: String {
        let milliseconds = 1000.0 / max(0.5, Double(freeRateHz))
        return milliseconds >= 1000
            ? String(format: "%.2f SEC / STEP", milliseconds / 1000.0)
            : String(format: "%.0f MS / STEP", milliseconds)
    }

    var crtDistortion: Double {
        let detuneAmount = Double(abs(detune) / 24.0) * 0.18
        let resonanceAmount = Double(resonance) * 0.18
        let filterDarkness = Double(1.0 - min(1.0, max(0.0, (cutoff - 80.0) / 17920.0))) * 0.13
        let swingAmount = Double(swing / 0.45) * 0.12
        let blendEdge = Double(abs(oscBlend - 0.5) * 2.0) * 0.06
        let echoSmear = delayEnabled ? Double(delayFeedback * delayMix) * 0.32 : 0
        return min(1.0, detuneAmount + resonanceAmount + filterDarkness + swingAmount + blendEdge + echoSmear + interactionPulse * 0.55)
    }

    func selectSkin(_ index: Int) {
        markPresetCustom()
        skinIndex = min(PicoSkin.skins.count - 1, max(0, index))
        UserDefaults.standard.set(skinIndex, forKey: "boxedArpSkin")
    }

    func setWave1(_ value: Int) { setDiscrete("osc1Wave", Float(value)) }
    func setWave2(_ value: Int) { setDiscrete("osc2Wave", Float(value)) }
    func setPattern(_ value: Int) { setDiscrete("pattern", Float(value)) }
    func setRate(_ value: Int) { setDiscrete("rate", Float(value)) }
    func setArpTimingMode(_ value: Int) { setDiscrete("arpTimingMode", Float(value)) }
    func setFreeRateNormalized(_ normalized: Float) {
        let amount = min(1, max(0, normalized))
        let minimum: Float = 0.5
        let maximum: Float = 50.0
        let hz = minimum * pow(maximum / minimum, amount)
        set("freeRateHz", hz)
    }
    func setOctaves(_ value: Int) { setDiscrete("octaves", Float(value)) }
    func setLatch(_ value: Bool) { setDiscrete("latch", value ? 1 : 0) }
    func setRoot(_ value: Int) { setDiscrete("chordRoot", Float(value)) }
    func setChord(_ value: Int) { setDiscrete("chordPreset", Float(value)) }
    func setScale(_ value: Int) {
        // Indexed automation: GarageBand/Logic-compatible hosts receive a discrete
        // touch/value/release gesture, and external automation updates the UI via
        // the parameter observer below. The DSP applies the new scale on the next step.
        beginAutomation("scalePreset")
        set("scalePreset", Float(value))
        endAutomation("scalePreset")
    }
    func setArpEnabled(_ value: Bool) { setDiscrete("arpEnabled", value ? 1 : 0) }
    func setDelayEnabled(_ value: Bool) { setDiscrete("delayEnabled", value ? 1 : 0) }
    func setMIDIOutEnabled(_ value: Bool) { setDiscrete("midiOutEnabled", value ? 1 : 0) }

    var selectedPresetName: String {
        if selectedPresetIndex == 0 { return "CUSTOM" }
        let factoryCount = BoxedArpPresetLibrary.factoryPresets.count
        if selectedPresetIndex <= factoryCount {
            return BoxedArpPresetLibrary.factoryPresets[selectedPresetIndex - 1].name
        }
        let userIndex = selectedPresetIndex - factoryCount - 1
        guard userPresets.indices.contains(userIndex) else { return "CUSTOM" }
        return userPresets[userIndex].name
    }

    var selectedUserPresetIndex: Int? {
        let index = selectedPresetIndex - BoxedArpPresetLibrary.factoryPresets.count - 1
        return userPresets.indices.contains(index) ? index : nil
    }

    var suggestedPresetName: String {
        selectedUserPresetIndex.map { userPresets[$0].name } ?? "MY ARP"
    }

    func selectPreset(_ menuIndex: Int) {
        guard menuIndex > 0 else {
            selectedPresetIndex = 0
            presetStatus = "CUSTOM"
            return
        }

        let factoryCount = BoxedArpPresetLibrary.factoryPresets.count
        if menuIndex <= factoryCount {
            let preset = BoxedArpPresetLibrary.factoryPresets[menuIndex - 1]
            applySnapshot(preset.snapshot)
            selectedPresetIndex = menuIndex
            presetStatus = preset.name
            return
        }

        let userIndex = menuIndex - factoryCount - 1
        guard userPresets.indices.contains(userIndex) else { return }
        let preset = userPresets[userIndex]
        applySnapshot(preset.snapshot)
        selectedPresetIndex = menuIndex
        presetStatus = preset.name
    }

    @discardableResult
    func saveUserPreset(named rawName: String) -> Bool {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            presetStatus = "NAME NEEDED"
            return false
        }

        let name = String(trimmed.prefix(24))
        let snapshot = makeSnapshot()
        if let existing = userPresets.firstIndex(where: {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            userPresets[existing].name = name
            userPresets[existing].snapshot = snapshot
            selectedPresetIndex = BoxedArpPresetLibrary.factoryPresets.count + existing + 1
        } else {
            let preset = BoxedArpUserPreset(id: UUID(), name: name, snapshot: snapshot)
            userPresets.append(preset)
            selectedPresetIndex = BoxedArpPresetLibrary.factoryPresets.count + userPresets.count
        }
        persistUserPresets()
        presetStatus = "SAVED"
        interactionPulse = 1
        return true
    }

    func deleteSelectedUserPreset() {
        guard let index = selectedUserPresetIndex else {
            presetStatus = "FACTORY LOCKED"
            return
        }
        userPresets.remove(at: index)
        persistUserPresets()
        selectedPresetIndex = 0
        presetStatus = "DELETED"
        interactionPulse = 1
    }

    func toggleMIDICapture() {
        if midiCaptureActive {
            audioUnit.stopMIDICapture()
            drainMIDICaptureEvents()
            midiCaptureActive = false
            midiExportStatus = capturedMIDIEvents.isEmpty
                ? "NO NOTES CAPTURED"
                : "CAPTURED \(capturedMIDIEvents.count) EVENTS"
        } else {
            capturedMIDIEvents.removeAll(keepingCapacity: true)
            capturedMIDIEventCount = 0
            audioUnit.startMIDICapture()
            midiCaptureActive = true
            midiExportStatus = "RECORDING GENERATED MIDI"
        }
        interactionPulse = 1
    }

    func saveMIDICapture() {
        if midiCaptureActive {
            audioUnit.stopMIDICapture()
            midiCaptureActive = false
        }
        drainMIDICaptureEvents()
        guard let data = MIDIFileWriter.makeFile(events: capturedMIDIEvents,
                                                  fallbackTempo: currentTempo) else {
            midiExportStatus = "PLAY NOTES, THEN CAPTURE"
            return
        }

        let scale = scaleNames[min(max(scalePreset, 0), scaleNames.count - 1)]
            .replacingOccurrences(of: "µ", with: "MICRO")
            .replacingOccurrences(of: " ", with: "_")
        let root = rootNames[min(max(chordRoot, 0), rootNames.count - 1)]
            .replacingOccurrences(of: "#", with: "sharp")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BOXED_ARP_\(root)_\(scale).mid"
        if let midiType = UTType(filenameExtension: "mid") {
            panel.allowedContentTypes = [midiType]
        }
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                midiExportStatus = "EXPORT CANCELLED"
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                midiExportStatus = "SAVED \(url.lastPathComponent)"
            } catch {
                midiExportStatus = "SAVE FAILED"
            }
        }
    }

    /// Sends an automation value event. Sliders call begin/end around this method.
    func set(_ identifier: String, _ value: Float) {
        markPresetCustom()
        guard let parameter = parameterByID[identifier] else { return }
        parameter.setValue(value,
                           originator: observerToken,
                           atHostTime: mach_absolute_time(),
                           eventType: .value)
        receiveParameter(address: parameter.address, value: value)
        interactionPulse = 1
    }

    func beginAutomation(_ identifier: String) {
        guard let parameter = parameterByID[identifier] else { return }
        parameter.setValue(parameter.value,
                           originator: observerToken,
                           atHostTime: mach_absolute_time(),
                           eventType: .touch)
    }

    func endAutomation(_ identifier: String) {
        guard let parameter = parameterByID[identifier] else { return }
        parameter.setValue(parameter.value,
                           originator: observerToken,
                           atHostTime: mach_absolute_time(),
                           eventType: .release)
    }

    func commitTempoText() {
        let normalized = tempoText.replacingOccurrences(of: ",", with: ".")
        guard let typed = Float(normalized), typed.isFinite else {
            tempoText = String(format: "%.1f", tempoBPM)
            return
        }
        applyInternalTempo(typed)
    }

    func tapTempo() {
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = tapTimes.last, now - previous > 2.0 {
            tapTimes.removeAll(keepingCapacity: true)
        }
        tapTimes.append(now)
        if tapTimes.count > 6 { tapTimes.removeFirst() }
        guard tapTimes.count >= 2 else {
            interactionPulse = 1
            return
        }

        var intervals: [TimeInterval] = []
        for index in 1..<tapTimes.count {
            intervals.append(tapTimes[index] - tapTimes[index - 1])
        }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0 else { return }
        applyInternalTempo(Float(60.0 / average))
    }

    var tempoSourceBadge: String {
        if arpTimingMode == 1 {
            return freeRateHz < 10
                ? String(format: "FREE %.1fHZ", freeRateHz)
                : String(format: "FREE %.0fHZ", freeRateHz)
        }
        return String(format: "%.1f BPM", currentTempo)
    }

    func noteName(_ midi: Int) -> String {
        guard midi >= 0 else { return "--" }
        return "\(rootNames[midi % 12])\(midi / 12 - 1)"
    }

    private func makeSnapshot() -> BoxedArpSnapshot {
        var values: [String: Float] = [:]
        for (identifier, parameter) in parameterByID {
            values[identifier] = parameter.value
        }
        return BoxedArpSnapshot(values: values, skinIndex: skinIndex)
    }

    private func applySnapshot(_ snapshot: BoxedArpSnapshot) {
        isApplyingSnapshot = true
        let arpValue = snapshot.values["arpEnabled"]
        for (identifier, value) in snapshot.values where identifier != "arpEnabled" {
            guard let parameter = parameterByID[identifier] else { continue }
            parameter.setValue(value,
                               originator: observerToken,
                               atHostTime: mach_absolute_time(),
                               eventType: .value)
            receiveParameter(address: parameter.address, value: value)
        }
        if let arpValue, let parameter = parameterByID["arpEnabled"] {
            parameter.setValue(arpValue,
                               originator: observerToken,
                               atHostTime: mach_absolute_time(),
                               eventType: .value)
            receiveParameter(address: parameter.address, value: arpValue)
        }
        skinIndex = min(PicoSkin.skins.count - 1, max(0, snapshot.skinIndex))
        UserDefaults.standard.set(skinIndex, forKey: "boxedArpSkin")
        isApplyingSnapshot = false
        interactionPulse = 1
    }

    private func loadUserPresets() {
        if let data = UserDefaults.standard.data(forKey: userPresetsKey),
           let decoded = try? JSONDecoder().decode([BoxedArpUserPreset].self, from: data) {
            userPresets = decoded
            return
        }

        // Migrate favorites created by v8/v9 into the unified preset menu.
        guard let legacyData = UserDefaults.standard.data(forKey: legacyMemoryKey),
              let legacy = try? JSONDecoder().decode([BoxedArpMemorySlot?].self, from: legacyData) else {
            userPresets = []
            return
        }
        userPresets = legacy.compactMap { slot in
            guard let slot else { return nil }
            return BoxedArpUserPreset(id: UUID(), name: slot.name, snapshot: slot.snapshot)
        }
        persistUserPresets()
    }

    private func persistUserPresets() {
        guard let data = try? JSONEncoder().encode(userPresets) else { return }
        UserDefaults.standard.set(data, forKey: userPresetsKey)
    }

    private func markPresetCustom() {
        guard !isApplyingSnapshot else { return }
        selectedPresetIndex = 0
        presetStatus = "CUSTOM"
    }

    private func drainMIDICaptureEvents() {
        let drained = audioUnit.drainCapturedMIDIEvents()
        if !drained.isEmpty {
            capturedMIDIEvents.append(contentsOf: drained)
            capturedMIDIEventCount = capturedMIDIEvents.count
        }
        let dropped = audioUnit.droppedMIDICaptureEventCount
        if dropped > 0 {
            midiExportStatus = "MIDI BUFFER FULL: \(dropped) DROPPED"
        }
    }

    private func setDiscrete(_ identifier: String, _ value: Float) {
        beginAutomation(identifier)
        set(identifier, value)
        endAutomation(identifier)
    }

    private func applyInternalTempo(_ bpm: Float) {
        let clamped = min(240, max(40, bpm))
        beginAutomation("tempoBPM")
        set("tempoBPM", clamped)
        endAutomation("tempoBPM")
        tempoText = String(format: "%.1f", clamped)
    }

    private func syncAllParameters() {
        for parameter in parameterByID.values {
            receiveParameter(address: parameter.address, value: parameter.value)
        }
    }

    private func receiveParameter(address: AUParameterAddress, value: AUValue) {
        switch address {
        case 0: osc1Wave = Int(value.rounded())
        case 1: osc2Wave = Int(value.rounded())
        case 2: oscBlend = value
        case 3: detune = value
        case 4: attack = value
        case 5: decay = value
        case 6: sustain = value
        case 7: release = value
        case 8: cutoff = value
        case 9: resonance = value
        case 10: pattern = Int(value.rounded())
        case 11: rate = Int(value.rounded())
        case 12: octaves = Int(value.rounded())
        case 13: gate = value
        case 14: swing = value
        case 15: latch = value >= 0.5
        case 16: output = value
        case 17:
            tempoBPM = value
            tempoText = String(format: "%.1f", value)
        case 18: break // Reserved address from v13.
        case 19: chordRoot = Int(value.rounded())
        case 20: chordPreset = Int(value.rounded())
        case 21: scalePreset = Int(value.rounded())
        case 22: arpEnabled = value >= 0.5
        case 23: delayEnabled = value >= 0.5
        case 24: delayTime = value
        case 25: delayFeedback = value
        case 26: delayTone = value
        case 27: delayMix = value
        case 28: midiOutEnabled = value >= 0.5
        case 29: arpTimingMode = Int(value.rounded())
        case 30: freeRateHz = value
        default: break
        }
    }
}
