import Foundation
import SwiftUI

struct PicoArpView: View {
    @ObservedObject var model: ArpViewModel
    @State private var page = 0
    @State private var showHelp = false
    @State private var helpPage = 0
    @State private var showSavePreset = false
    @State private var presetNameDraft = ""

    private var skin: PicoSkin {
        PicoSkin.skins[min(PicoSkin.skins.count - 1, max(0, model.skinIndex))]
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let narrow = proxy.size.width < 620
                let monitorWidth = narrow ? 172.0 : 210.0

                VStack(spacing: 5) {
                    header

                    HStack(alignment: .top, spacing: 6) {
                        navigatorPanel
                            .frame(width: monitorWidth)

                        VStack(spacing: 5) {
                            setupPanel
                                .frame(height: 70)
                            pageTabs
                            controlPage
                                .frame(maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(skin.background)
                .animation(.none, value: model.skinIndex)
            }

            if showHelp {
                helpOverlay
            }

            if showSavePreset {
                savePresetOverlay
            }
        }
        .frame(minWidth: 560, idealWidth: 720, minHeight: 300, idealHeight: 340)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("BOXED ARP")
                .font(.opticPixel(15))
                .foregroundStyle(skin.text)
                .lineLimit(1)

            Spacer(minLength: 2)

            Text(clockBadge)
                .font(.opticPixel(7))
                .foregroundStyle(model.arpTimingMode == 1 ? skin.accent : skin.accent2)
                .lineLimit(1)

            PixelButton(label: model.arpEnabled ? "STOP" : "PLAY",
                        isSelected: model.arpEnabled,
                        skin: skin) {
                model.setArpEnabled(!model.arpEnabled)
            }
            .frame(width: 48)

            presetMenu
                .frame(width: 126)

            PixelButton(label: "SAVE", isSelected: false, skin: skin) {
                presetNameDraft = model.suggestedPresetName
                showSavePreset = true
            }
            .frame(width: 38)

            PixelButton(label: "DEL", isSelected: false, skin: skin) {
                model.deleteSelectedUserPreset()
            }
            .frame(width: 30)
            .opacity(model.selectedUserPresetIndex == nil ? 0.45 : 1)

            PixelMenu(label: "SKIN",
                      value: model.skinIndex,
                      options: PicoSkin.skins.map(\.name),
                      skin: skin,
                      onSelect: model.selectSkin)
                .frame(width: 70)

            PixelButton(label: "?", isSelected: showHelp, skin: skin) {
                showHelp.toggle()
            }
            .frame(width: 26)
        }
        .padding(.horizontal, 1)
    }

    private var presetMenu: some View {
        Menu {
            Button("CUSTOM") { model.selectPreset(0) }

            Section("FACTORY") {
                ForEach(BoxedArpPresetLibrary.factoryPresets.indices, id: \.self) { index in
                    Button(BoxedArpPresetLibrary.factoryPresets[index].name) {
                        model.selectPreset(index + 1)
                    }
                }
            }

            if !model.userPresets.isEmpty {
                Section("MY PRESETS") {
                    ForEach(model.userPresets.indices, id: \.self) { index in
                        Button(model.userPresets[index].name) {
                            model.selectPreset(BoxedArpPresetLibrary.factoryPresets.count + index + 1)
                        }
                    }
                }
            }

        } label: {
            HStack(spacing: 4) {
                Text("PST")
                    .font(.opticPixel(6.5))
                    .foregroundStyle(skin.muted)
                Spacer(minLength: 2)
                Text(model.selectedPresetName)
                    .font(.opticPixel(6.5))
                    .foregroundStyle(skin.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text("▼")
                    .font(.opticPixel(6.5))
                    .foregroundStyle(skin.accent)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 19)
            .background(skin.panelAlt)
            .overlay(Rectangle().stroke(skin.muted.opacity(0.75), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var clockBadge: String { model.tempoSourceBadge }

    private var navigatorPanel: some View {
        PixelPanel("CRT", skin: skin) {
            VStack(spacing: 4) {
                CRTArpAnimation(currentStep: model.currentStep,
                                currentNote: model.currentNote,
                                heldNotes: model.heldNotes,
                                pattern: model.pattern,
                                phase: model.animationPhase,
                                distortion: model.crtDistortion,
                                isRunning: model.arpEnabled,
                                skin: skin)
                    .frame(maxHeight: .infinity)

                HStack(spacing: 3) {
                    PixelReadout(label: "STP", value: model.currentStep >= 0 ? "\(model.currentStep + 1)" : "--", skin: skin)
                    PixelReadout(label: "NOTE", value: model.noteName(model.currentNote), skin: skin)
                    PixelReadout(label: "HLD", value: "\(model.heldNotes)", skin: skin)
                }
            }
        }
    }

    private var setupPanel: some View {
        PixelPanel("SETUP", skin: skin) {
            HStack(spacing: 4) {
                Text("BPM")
                    .font(.opticPixel(7))
                    .foregroundStyle(skin.muted)
                    .frame(width: 28)

                TextField("120.0", text: $model.tempoText)
                    .font(.opticPixel(9))
                    .foregroundStyle(skin.text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 3)
                    .frame(width: 62, height: 20)
                    .background(skin.background)
                    .overlay(Rectangle().stroke(skin.accent, lineWidth: 1))
                    .onSubmit { model.commitTempoText() }

                PixelButton(label: "TAP", isSelected: false, skin: skin) {
                    model.tapTempo()
                }
                .frame(width: 40)

                PixelMenu(label: "ROOT", value: model.chordRoot, options: model.rootNames, skin: skin, onSelect: model.setRoot)
                    .frame(width: 76)
                PixelMenu(label: "CHORD", value: model.chordPreset, options: model.chordNames, skin: skin, onSelect: model.setChord)
                PixelMenu(label: "SCALE", value: model.scalePreset, options: model.scaleNames, skin: skin, onSelect: model.setScale)
            }
        }
    }

    private var pageTabs: some View {
        HStack(spacing: 4) {
            ForEach(["ARP", "OSC", "ENV", "DLY"].indices, id: \.self) { index in
                PixelButton(label: ["ARP", "OSC", "ENV", "DLY"][index],
                            isSelected: page == index,
                            skin: skin) {
                    page = index
                }
            }
        }
    }

    @ViewBuilder
    private var controlPage: some View {
        switch page {
        case 0: arpPanel
        case 1: synthPanel
        case 2: shapePanel
        case 3: delayPanel
        default: arpPanel
        }
    }

    private var arpPanel: some View {
        PixelPanel("ARP", skin: skin) {
            VStack(spacing: 5) {
                HStack(spacing: 3) {
                    ForEach(model.patternNames.indices, id: \.self) { index in
                        PixelButton(label: model.patternNames[index], isSelected: model.pattern == index, skin: skin) {
                            model.setPattern(index)
                        }
                    }

                    PixelButton(label: "SYNC", isSelected: model.arpTimingMode == 0, skin: skin) {
                        model.setArpTimingMode(0)
                    }
                    PixelButton(label: "FREE", isSelected: model.arpTimingMode == 1, skin: skin) {
                        model.setArpTimingMode(1)
                    }
                }

                if model.arpTimingMode == 0 {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 9), spacing: 3) {
                        ForEach(model.rateNames.indices, id: \.self) { index in
                            PixelButton(label: model.rateNames[index], isSelected: model.rate == index, skin: skin) {
                                model.setRate(index)
                            }
                        }
                    }
                } else {
                    PixelSlider(label: "SPEED",
                                value: model.freeRateSliderPosition,
                                range: 0...1,
                                display: "\(model.freeRateDisplay)  \(model.freeRateStepDisplay)",
                                skin: skin,
                                onEditingChanged: { editing in
                                    if editing { model.beginAutomation("freeRateHz") }
                                    else { model.endAutomation("freeRateHz") }
                                }) {
                        model.setFreeRateNormalized($0)
                    }
                }

                HStack(spacing: 7) {
                    HStack(spacing: 3) {
                        Text("OCT")
                            .font(.opticPixel(6.5))
                            .foregroundStyle(skin.muted)
                        ForEach(1...4, id: \.self) { octave in
                            PixelButton(label: "\(octave)", isSelected: model.octaves == octave, skin: skin) {
                                model.setOctaves(octave)
                            }
                            .frame(width: 27)
                        }
                    }

                    automatedSlider(identifier: "gate", label: "GATE", value: model.gate, range: 0.05...0.95,
                                    display: "\(Int(model.gate * 100))%")
                    automatedSlider(identifier: "swing", label: "SWING", value: model.swing, range: 0...0.45,
                                    display: "\(Int(model.swing * 100))%")
                }

                HStack(alignment: .top, spacing: 7) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            PixelToggle(label: "LATCH", value: model.latch, skin: skin) {
                                model.setLatch(!model.latch)
                            }
                            PixelToggle(label: "M OUT", value: model.midiOutEnabled, skin: skin) {
                                model.setMIDIOutEnabled(!model.midiOutEnabled)
                            }
                        }

                        Text("@0pticbox")
                            .font(.opticPixel(5.5))
                            .foregroundStyle(skin.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PixelButton(label: model.midiCaptureActive ? "STOP" : "REC",
                                isSelected: model.midiCaptureActive,
                                skin: skin) {
                        model.toggleMIDICapture()
                    }
                    .frame(width: 48)
                    PixelButton(label: "SAVE",
                                isSelected: model.capturedMIDIEventCount > 0,
                                skin: skin) {
                        model.saveMIDICapture()
                    }
                    .frame(width: 48)
                    PixelReadout(label: "EVT", value: "\(model.capturedMIDIEventCount)", skin: skin)
                        .frame(width: 47)
                }
            }
        }
    }

    private var synthPanel: some View {
        PixelPanel("OSC", skin: skin) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    waveSelector(label: "1", selected: model.osc1Wave, action: model.setWave1)
                    waveSelector(label: "2", selected: model.osc2Wave, action: model.setWave2)
                }

                HStack(spacing: 10) {
                    automatedSlider(identifier: "oscBlend", label: "BLEND", value: model.oscBlend, range: 0...1,
                                    display: "\(Int(model.oscBlend * 100))%")
                    automatedSlider(identifier: "detune", label: "DETUNE", value: model.detune, range: -24...24,
                                    display: String(format: "%.0fct", model.detune))
                    automatedSlider(identifier: "output", label: "OUT", value: model.output, range: 0...1,
                                    display: "\(Int(model.output * 100))%")
                }
            }
        }
    }

    private var shapePanel: some View {
        PixelPanel("ENV", skin: skin) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    automatedSlider(identifier: "attack", label: "ATK", value: model.attack, range: 0.001...2,
                                    display: timeText(model.attack))
                    automatedSlider(identifier: "decay", label: "DEC", value: model.decay, range: 0.005...2,
                                    display: timeText(model.decay))
                    automatedSlider(identifier: "sustain", label: "SUS", value: model.sustain, range: 0...1,
                                    display: "\(Int(model.sustain * 100))%")
                }
                HStack(spacing: 10) {
                    automatedSlider(identifier: "release", label: "REL", value: model.release, range: 0.005...4,
                                    display: timeText(model.release))
                    automatedSlider(identifier: "cutoff", label: "CUT", value: model.cutoff, range: 80...18000,
                                    display: frequencyText(model.cutoff))
                    automatedSlider(identifier: "resonance", label: "RES", value: model.resonance, range: 0...0.95,
                                    display: "\(Int(model.resonance * 100))%")
                }
            }
        }
    }

    private var delayPanel: some View {
        PixelPanel("DLY", skin: skin) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    PixelToggle(label: "DELAY", value: model.delayEnabled, skin: skin) {
                        model.setDelayEnabled(!model.delayEnabled)
                    }
                    automatedSlider(identifier: "delayTime", label: "TIME", value: model.delayTime, range: 0.03...1.20,
                                    display: timeText(model.delayTime))
                    automatedSlider(identifier: "delayFeedback", label: "FDBK", value: model.delayFeedback, range: 0...0.88,
                                    display: "\(Int(model.delayFeedback * 100))%")
                }

                HStack(spacing: 10) {
                    automatedSlider(identifier: "delayTone", label: "TONE", value: model.delayTone, range: 0...1,
                                    display: "\(Int(model.delayTone * 100))%")
                    automatedSlider(identifier: "delayMix", label: "MIX", value: model.delayMix, range: 0...0.75,
                                    display: "\(Int(model.delayMix * 100))%")
                }
            }
        }
    }

    private var savePresetOverlay: some View {
        ZStack {
            skin.shadow.opacity(0.72)
                .ignoresSafeArea()

            PixelPanel("SAVE PRESET", skin: skin) {
                VStack(spacing: 8) {
                    TextField("MY ARP", text: $presetNameDraft)
                        .font(.opticPixel(9))
                        .foregroundStyle(skin.text)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 6)
                        .frame(height: 24)
                        .background(skin.background)
                        .overlay(Rectangle().stroke(skin.muted, lineWidth: 1))
                        .onSubmit { saveNamedPreset() }

                    HStack(spacing: 6) {
                        PixelButton(label: "CANCEL", isSelected: false, skin: skin) {
                            showSavePreset = false
                        }
                        PixelButton(label: "SAVE", isSelected: true, skin: skin) {
                            saveNamedPreset()
                        }
                    }
                }
            }
            .frame(width: 250)
        }
    }

    private func saveNamedPreset() {
        if model.saveUserPreset(named: presetNameDraft) {
            showSavePreset = false
        }
    }

    private var helpOverlay: some View {
        ZStack {
            skin.shadow.opacity(0.72)
                .ignoresSafeArea()

            PixelPanel("HELP", skin: skin) {
                VStack(spacing: 7) {
                    HStack(spacing: 4) {
                        PixelButton(label: "QUICK", isSelected: helpPage == 0, skin: skin) {
                            helpPage = 0
                        }
                        PixelButton(label: "WORLD SCALES", isSelected: helpPage == 1, skin: skin) {
                            helpPage = 1
                        }
                    }

                    Group {
                        if helpPage == 0 {
                            quickHelpPage
                        } else {
                            worldScalesHelpPage
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    PixelButton(label: "CLOSE", isSelected: false, skin: skin) {
                        showHelp = false
                    }
                    .frame(width: 70)
                }
            }
            .frame(width: 500, height: 292)
        }
    }

    private var quickHelpPage: some View {
        HStack(alignment: .top, spacing: 18) {
            helpColumn([
                ("PLAY", "ARP ON/OFF"),
                ("BPM", "TYPE OR TAP"),
                ("PST", "LOAD PRESET"),
                ("SAVE", "NAME YOUR ARP")
            ])
            helpColumn([
                ("CHORD", "ADD NOTES"),
                ("SCALE", "49 SETS / AUTO"),
                ("SYNC/FREE", "CLOCK"),
                ("REC/SAVE", "MIDI FILE"),
                ("M OUT", "MIDI OUT")
            ])
        }
        .padding(.top, 4)
    }

    private var worldScalesHelpPage: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text("RAGAS ARE MORE THAN SCALES: PHRASES, BENDS, EMPHASIS, AND ORNAMENTS CREATE THEIR IDENTITY.")
                    .font(.opticPixel(6.2))
                    .foregroundStyle(skin.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(worldScaleLessons) { lesson in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(lesson.name)
                                .font(.opticPixel(7.2))
                                .foregroundStyle(skin.accent)
                            Text(lesson.formula)
                                .font(.opticPixel(6.2))
                                .foregroundStyle(skin.accent2)
                        }
                        Text(lesson.notes)
                            .font(.opticPixel(6.2))
                            .foregroundStyle(skin.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(lesson.character)
                            .font(.opticPixel(6.2))
                            .foregroundStyle(skin.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(5)
                    .background(skin.panelAlt)
                    .overlay(Rectangle().stroke(skin.muted.opacity(0.55), lineWidth: 1))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var worldScaleLessons: [WorldScaleLesson] {
        [
            .init(name: "BHAIRAV", formula: "1 b2 3 4 5 b6 7", notes: "C Db E F G Ab B", character: "SOLEMN, POWERFUL. THE b2 AND b6 ARE OFTEN OSCILLATED."),
            .init(name: "TODI", formula: "1 b2 b3 #4 5 b6 7", notes: "C Db Eb F# G Ab B", character: "SEARCHING, TENSE. CURVED SLIDES AND DELICATE INTONATION MATTER."),
            .init(name: "MARWA", formula: "1 b2 3 #4 6 7", notes: "C Db E F# A B", character: "SUSPENDED AND UNRESOLVED. THE PERFECT 5TH IS OMITTED."),
            .init(name: "MALKAUNS", formula: "1 b3 4 b6 b7", notes: "C Eb F Ab Bb", character: "DARK, SPACIOUS, MEDITATIVE. A FIVE-NOTE RAGA."),
            .init(name: "HAMSADHWANI", formula: "1 2 3 5 7", notes: "C D E G B", character: "BRIGHT, OPEN, CELEBRATORY. A FIVE-NOTE RAGA."),
            .init(name: "CHARUKESHI", formula: "1 2 3 4 5 b6 b7", notes: "C D E F G Ab Bb", character: "WARM AND BITTERSWEET; SIMILAR TO MIXOLYDIAN b6."),
        ]
    }

    private func helpColumn(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 7) {
                    Text(row.0)
                        .font(.opticPixel(6.5))
                        .foregroundStyle(skin.accent)
                        .frame(width: 62, alignment: .leading)
                    Text(row.1)
                        .font(.opticPixel(6.5))
                        .foregroundStyle(skin.text)
                }
            }
        }
    }

    private func automatedSlider(identifier: String,
                                 label: String,
                                 value: Float,
                                 range: ClosedRange<Float>,
                                 display: String) -> some View {
        PixelSlider(label: label,
                    value: value,
                    range: range,
                    display: display,
                    skin: skin,
                    onEditingChanged: { editing in
                        if editing { model.beginAutomation(identifier) }
                        else { model.endAutomation(identifier) }
                    }) {
            model.set(identifier, $0)
        }
    }

    private func waveSelector(label: String, selected: Int, action: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.opticPixel(7))
                .foregroundStyle(skin.muted)
                .frame(width: 10)
            ForEach(model.waveNames.indices, id: \.self) { index in
                PixelButton(label: model.waveNames[index], isSelected: selected == index, skin: skin) {
                    action(index)
                }
            }
        }
    }

    private func timeText(_ value: Float) -> String {
        value < 1 ? "\(Int(value * 1000))ms" : String(format: "%.2fs", value)
    }

    private func frequencyText(_ value: Float) -> String {
        value >= 1000 ? String(format: "%.1fk", value / 1000) : "\(Int(value))Hz"
    }
}


private struct WorldScaleLesson: Identifiable {
    let name: String
    let formula: String
    let notes: String
    let character: String
    var id: String { name }
}
