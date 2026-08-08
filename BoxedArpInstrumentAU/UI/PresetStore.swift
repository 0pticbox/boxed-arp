import Foundation

struct BoxedArpSnapshot: Codable {
    let values: [String: Float]
    let skinIndex: Int
}

// Legacy v8/v9 slot format. Kept only so old favorites can migrate.
struct BoxedArpMemorySlot: Codable {
    let name: String
    let snapshot: BoxedArpSnapshot
}

struct BoxedArpUserPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    var snapshot: BoxedArpSnapshot
}

struct BoxedArpFactoryPreset {
    let name: String
    let snapshot: BoxedArpSnapshot
}

enum BoxedArpPresetLibrary {
    static let defaults: [String: Float] = [
        "osc1Wave": 0, "osc2Wave": 1, "oscBlend": 0.28, "detune": 7,
        "attack": 0.008, "decay": 0.18, "sustain": 0.72, "release": 0.20,
        "cutoff": 7200, "resonance": 0.15,
        "pattern": 2, "rate": 4, "arpTimingMode": 0, "freeRateHz": 8,
        "octaves": 2, "gate": 0.62, "swing": 0, "latch": 0,
        "output": 0.78, "arpEnabled": 1,
        "tempoBPM": 120,
        "chordRoot": 0, "chordPreset": 0, "scalePreset": 0,
        "delayEnabled": 0, "delayTime": 0.32, "delayFeedback": 0.38,
        "delayTone": 0.42, "delayMix": 0.24,
        "midiOutEnabled": 1
    ]

    static let factoryPresets: [BoxedArpFactoryPreset] = [
        make("INIT", skin: 0, [:]),
        make("SKY RUN", skin: 1, [
            "chordRoot": 0, "chordPreset": 1, "scalePreset": 1,
            "pattern": 2, "rate": 4, "octaves": 2,
            "osc1Wave": 0, "osc2Wave": 1, "oscBlend": 0.32,
            "detune": 8, "cutoff": 8600, "resonance": 0.12,
            "gate": 0.64, "delayEnabled": 0
        ]),
        make("BOSS RUSH", skin: 2, [
            "chordRoot": 2, "chordPreset": 2, "scalePreset": 4,
            "pattern": 3, "rate": 7, "octaves": 3,
            "gate": 0.42, "swing": 0.08,
            "osc1Wave": 0, "osc2Wave": 1, "oscBlend": 0.42,
            "detune": 13, "cutoff": 4300, "resonance": 0.34,
            "delayEnabled": 1, "delayTime": 0.19,
            "delayFeedback": 0.47, "delayTone": 0.28, "delayMix": 0.24
        ]),
        make("CRT DREAM", skin: 0, [
            "chordRoot": 9, "chordPreset": 4, "scalePreset": 6,
            "pattern": 2, "rate": 3, "octaves": 2,
            "osc1Wave": 2, "osc2Wave": 1, "oscBlend": 0.44,
            "detune": 5, "attack": 0.035, "release": 0.82,
            "cutoff": 3600, "resonance": 0.22,
            "gate": 0.72, "delayEnabled": 1, "delayTime": 0.46,
            "delayFeedback": 0.56, "delayTone": 0.26, "delayMix": 0.34
        ]),
        make("CHIP FLIGHT", skin: 1, [
            "chordRoot": 4, "chordPreset": 8, "scalePreset": 7,
            "pattern": 0, "rate": 5, "octaves": 3,
            "osc1Wave": 1, "osc2Wave": 1, "oscBlend": 0.18,
            "detune": 0, "attack": 0.002, "decay": 0.09,
            "sustain": 0.58, "release": 0.08,
            "cutoff": 10400, "resonance": 0.08, "gate": 0.54
        ]),
        make("DARK TOWER", skin: 2, [
            "chordRoot": 5, "chordPreset": 2, "scalePreset": 3,
            "pattern": 1, "rate": 2, "octaves": 2,
            "osc1Wave": 0, "osc2Wave": 2, "oscBlend": 0.25,
            "detune": -9, "attack": 0.02, "release": 0.42,
            "cutoff": 2100, "resonance": 0.48, "gate": 0.76,
            "delayEnabled": 1, "delayTime": 0.61,
            "delayFeedback": 0.51, "delayTone": 0.14, "delayMix": 0.29
        ]),
        make("FREE GLITCH", skin: 2, [
            "chordRoot": 0, "chordPreset": 3, "scalePreset": 5,
            "pattern": 3, "arpTimingMode": 1, "freeRateHz": 22,
            "octaves": 4, "gate": 0.18, "swing": 0.17,
            "osc1Wave": 1, "osc2Wave": 0, "oscBlend": 0.56,
            "detune": 18, "cutoff": 5900, "resonance": 0.52,
            "delayEnabled": 1, "delayTime": 0.11,
            "delayFeedback": 0.68, "delayTone": 0.62, "delayMix": 0.31
        ]),
        make("AIRSHIP", skin: 1, [
            "chordRoot": 7, "chordPreset": 3, "scalePreset": 1,
            "pattern": 0, "rate": 4, "octaves": 3,
            "gate": 0.68, "swing": 0.03,
            "osc1Wave": 0, "osc2Wave": 2, "oscBlend": 0.22,
            "detune": 6, "attack": 0.018, "release": 0.36,
            "cutoff": 9300, "resonance": 0.17,
            "delayEnabled": 1, "delayTime": 0.27,
            "delayFeedback": 0.31, "delayTone": 0.58, "delayMix": 0.18
        ]),
        make("MOON TEMPLE", skin: 0, [
            "chordRoot": 9, "chordPreset": 4, "scalePreset": 6,
            "pattern": 1, "rate": 3, "octaves": 2,
            "gate": 0.81, "swing": 0.05,
            "osc1Wave": 2, "osc2Wave": 0, "oscBlend": 0.31,
            "detune": -4, "attack": 0.065, "release": 1.10,
            "cutoff": 2750, "resonance": 0.29,
            "delayEnabled": 1, "delayTime": 0.72,
            "delayFeedback": 0.59, "delayTone": 0.18, "delayMix": 0.38
        ]),
        make("NEON CASTLE", skin: 2, [
            "chordRoot": 3, "chordPreset": 5, "scalePreset": 4,
            "pattern": 2, "rate": 5, "octaves": 3,
            "gate": 0.47, "swing": 0.11,
            "osc1Wave": 0, "osc2Wave": 1, "oscBlend": 0.51,
            "detune": 15, "attack": 0.004, "release": 0.24,
            "cutoff": 5100, "resonance": 0.41,
            "delayEnabled": 1, "delayTime": 0.16,
            "delayFeedback": 0.43, "delayTone": 0.47, "delayMix": 0.22
        ]),
        make("STAR CIRCUIT", skin: 1, [
            "chordRoot": 11, "chordPreset": 7, "scalePreset": 7,
            "pattern": 3, "rate": 6, "octaves": 4,
            "gate": 0.31, "swing": 0.02,
            "osc1Wave": 1, "osc2Wave": 2, "oscBlend": 0.37,
            "detune": 3, "attack": 0.001, "release": 0.12,
            "cutoff": 12800, "resonance": 0.11,
            "delayEnabled": 1, "delayTime": 0.09,
            "delayFeedback": 0.24, "delayTone": 0.76, "delayMix": 0.16
        ]),
        make("FINAL PHASE", skin: 2, [
            "chordRoot": 1, "chordPreset": 2, "scalePreset": 3,
            "pattern": 2, "rate": 8, "octaves": 4,
            "gate": 0.23, "swing": 0.14,
            "osc1Wave": 0, "osc2Wave": 1, "oscBlend": 0.61,
            "detune": 20, "attack": 0.003, "release": 0.19,
            "cutoff": 6700, "resonance": 0.57,
            "delayEnabled": 1, "delayTime": 0.13,
            "delayFeedback": 0.62, "delayTone": 0.34, "delayMix": 0.33
        ]),
        make("SUNSET SAVE", skin: 1, [
            "chordRoot": 5, "chordPreset": 3, "scalePreset": 2,
            "pattern": 0, "rate": 2, "octaves": 2,
            "gate": 0.86, "swing": 0.08,
            "osc1Wave": 2, "osc2Wave": 0, "oscBlend": 0.18,
            "detune": 2, "attack": 0.09, "release": 1.45,
            "cutoff": 4200, "resonance": 0.14,
            "delayEnabled": 1, "delayTime": 0.54,
            "delayFeedback": 0.46, "delayTone": 0.24, "delayMix": 0.30
        ]),
        make("ABYSS CHOIR", skin: 3, [
            "chordRoot": 3, "chordPreset": 4, "scalePreset": 4,
            "pattern": 2, "rate": 3, "octaves": 3,
            "gate": 0.70, "swing": 0.06,
            "osc1Wave": 2, "osc2Wave": 0, "oscBlend": 0.38,
            "detune": -7, "attack": 0.08, "decay": 0.45,
            "sustain": 0.74, "release": 1.35,
            "cutoff": 1850, "resonance": 0.44,
            "delayEnabled": 1, "delayTime": 0.78,
            "delayFeedback": 0.61, "delayTone": 0.12, "delayMix": 0.42
        ]),
        make("ECHO SHRINE", skin: 6, [
            "chordRoot": 1, "chordPreset": 2, "scalePreset": 6,
            "pattern": 1, "rate": 4, "octaves": 2,
            "gate": 0.78, "swing": 0.09,
            "osc1Wave": 2, "osc2Wave": 1, "oscBlend": 0.35,
            "detune": 2, "attack": 0.045, "release": 1.20,
            "cutoff": 2400, "resonance": 0.33,
            "delayEnabled": 1, "delayTime": 0.54,
            "delayFeedback": 0.64, "delayTone": 0.15, "delayMix": 0.39
        ]),
        make("VIOLET RUINS", skin: 3, [
            "chordRoot": 9, "chordPreset": 5, "scalePreset": 3,
            "pattern": 3, "rate": 5, "octaves": 3,
            "gate": 0.38, "swing": 0.13,
            "osc1Wave": 0, "osc2Wave": 1, "oscBlend": 0.48,
            "detune": 12, "attack": 0.01, "release": 0.35,
            "cutoff": 3200, "resonance": 0.51,
            "delayEnabled": 1, "delayTime": 0.22,
            "delayFeedback": 0.58, "delayTone": 0.25, "delayMix": 0.31
        ]),
        make("GLASS CATHEDRAL", skin: 5, [
            "chordRoot": 4, "chordPreset": 3, "scalePreset": 1,
            "pattern": 2, "rate": 3, "octaves": 3,
            "gate": 0.84, "swing": 0.02,
            "osc1Wave": 2, "osc2Wave": 0, "oscBlend": 0.29,
            "detune": 4, "attack": 0.09, "release": 1.60,
            "cutoff": 6800, "resonance": 0.27,
            "delayEnabled": 1, "delayTime": 0.67,
            "delayFeedback": 0.52, "delayTone": 0.44, "delayMix": 0.41
        ]),
        make("GHOST SIGNAL", skin: 6, [
            "chordRoot": 11, "chordPreset": 6, "scalePreset": 5,
            "pattern": 3, "arpTimingMode": 1, "freeRateHz": 6.4,
            "octaves": 4, "gate": 0.22, "swing": 0.18,
            "osc1Wave": 1, "osc2Wave": 2, "oscBlend": 0.46,
            "detune": 17, "attack": 0.003, "release": 0.28,
            "cutoff": 5300, "resonance": 0.61,
            "delayEnabled": 1, "delayTime": 0.14,
            "delayFeedback": 0.72, "delayTone": 0.69, "delayMix": 0.37
        ]),
        make("DREAM VAULT", skin: 5, [
            "chordRoot": 7, "chordPreset": 4, "scalePreset": 6,
            "pattern": 2, "rate": 4, "octaves": 2,
            "gate": 0.75, "swing": 0.04,
            "osc1Wave": 2, "osc2Wave": 1, "oscBlend": 0.41,
            "detune": -3, "attack": 0.055, "release": 1.05,
            "cutoff": 3100, "resonance": 0.25,
            "delayEnabled": 1, "delayTime": 0.63,
            "delayFeedback": 0.57, "delayTone": 0.21, "delayMix": 0.36
        ]),
        make("NIGHT ENGINE", skin: 2, [
            "chordRoot": 2, "chordPreset": 8, "scalePreset": 3,
            "pattern": 0, "rate": 7, "octaves": 4,
            "gate": 0.29, "swing": 0.12,
            "osc1Wave": 0, "osc2Wave": 1, "oscBlend": 0.59,
            "detune": 19, "attack": 0.002, "release": 0.15,
            "cutoff": 7200, "resonance": 0.49,
            "delayEnabled": 1, "delayTime": 0.12,
            "delayFeedback": 0.55, "delayTone": 0.42, "delayMix": 0.28
        ])
    ]

    private static func make(_ name: String,
                             skin: Int,
                             _ overrides: [String: Float]) -> BoxedArpFactoryPreset {
        var values = defaults
        values.merge(overrides) { _, new in new }
        return BoxedArpFactoryPreset(name: name,
                                     snapshot: BoxedArpSnapshot(values: values,
                                                                skinIndex: skin))
    }
}
