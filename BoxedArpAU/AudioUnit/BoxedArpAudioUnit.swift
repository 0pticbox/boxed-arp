import AudioToolbox
import AVFoundation

/// AUv3 MIDI-processor shell for BOXED ARP.
/// Add BoxedArpDSP.h to the extension target's bridging header.
final class BoxedArpAudioUnit: AUAudioUnit {
    private let dsp = BoxedArpDSP()
    private var parameterTreeStorage: AUParameterTree!
    private var emptyInputBusses: AUAudioUnitBusArray!
    private var emptyOutputBusses: AUAudioUnitBusArray!

    private var pattern: AUParameter!
    private var division: AUParameter!
    private var octaves: AUParameter!
    private var gate: AUParameter!
    private var swing: AUParameter!
    private var latch: AUParameter!
    private var hostSync: AUParameter!
    private var freeBPM: AUParameter!
    private var scaleLock: AUParameter!
    private var root: AUParameter!
    private var scale: AUParameter!

    // MIDI processors have no audio bus to query for sample rate, so infer it
    // from host sample-time/beat deltas once transport information is available.
    private var timingSampleRate: Double = 44_100
    private var lastHostSampleTime: Int64?
    private var lastHostBeatPosition: Double?

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        emptyInputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [])
        emptyOutputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [])
        maximumFramesToRender = 4096
        buildParameterTree()
    }

    override var inputBusses: AUAudioUnitBusArray { emptyInputBusses }
    override var outputBusses: AUAudioUnitBusArray { emptyOutputBusses }
    override var parameterTree: AUParameterTree? { parameterTreeStorage }
    override var virtualMIDICableCount: Int { 1 }
    override var midiOutputNames: [String] { ["BOXED ARP OUT"] }

    private func buildParameterTree() {
        func p(_ id: String, _ name: String, _ address: BAParameterAddress,
               _ min: AUValue, _ max: AUValue, _ unit: AudioUnitParameterUnit = .generic) -> AUParameter {
            AUParameterTree.createParameter(withIdentifier: id,
                                            name: name,
                                            address: address.rawValue,
                                            min: min,
                                            max: max,
                                            unit: unit,
                                            unitName: nil,
                                            flags: [.flag_IsWritable, .flag_IsReadable],
                                            valueStrings: nil,
                                            dependentParameters: nil)
        }

        pattern = p("pattern", "Pattern", .pattern, 0, 3)
        division = p("division", "Division", .division, 0, 8)
        octaves = p("octaves", "Octaves", .octaves, 1, 4)
        gate = p("gate", "Gate", .gate, 0.05, 0.98, .percent)
        swing = p("swing", "Swing", .swing, 0, 0.45, .percent)
        latch = p("latch", "Latch", .latch, 0, 1, .boolean)
        hostSync = p("sync", "Host Sync", .hostSync, 0, 1, .boolean)
        freeBPM = p("bpm", "Free BPM", .freeBPM, 20, 400, .beatsPerMinute)
        scaleLock = p("scaleLock", "Scale Lock", .scaleLock, 0, 1, .boolean)
        root = p("root", "Root", .root, 0, 11)
        scale = p("scale", "Scale", .scale, 0, 11)

        pattern.value = 0
        division.value = 3
        octaves.value = 1
        gate.value = 0.72
        swing.value = 0
        latch.value = 0
        hostSync.value = 1
        freeBPM.value = 120
        scaleLock.value = 0
        root.value = 0
        scale.value = 0

        parameterTreeStorage = AUParameterTree.createTree(withChildren: [
            pattern, division, octaves, gate, swing, latch,
            hostSync, freeBPM, scaleLock, root, scale
        ])

        parameterTreeStorage.implementorValueObserver = { [weak self] parameter, value in
            self?.apply(parameter.address, value)
        }
        parameterTreeStorage.implementorValueProvider = { [weak self] parameter in
            self?.value(for: parameter.address) ?? parameter.value
        }
        syncDSPFromParameters()
    }

    private func scaleMask(_ index: Int) -> UInt16 {
        // Chromatic, Major, Minor, Dorian, Lydian, Hirajoshi,
        // Bhairav, Todi, Marwa, Malkauns, Hamsadhwani, Charukeshi.
        let masks: [UInt16] = [
            0x0FFF,
            0b101010110101,
            0b010110101101,
            0b010101101101,
            (1<<0)|(1<<2)|(1<<4)|(1<<6)|(1<<7)|(1<<9)|(1<<11),
            (1<<0)|(1<<2)|(1<<3)|(1<<7)|(1<<8),
            (1<<0)|(1<<1)|(1<<4)|(1<<5)|(1<<7)|(1<<8)|(1<<11),
            (1<<0)|(1<<1)|(1<<3)|(1<<6)|(1<<7)|(1<<8)|(1<<11),
            (1<<0)|(1<<1)|(1<<4)|(1<<6)|(1<<7)|(1<<9)|(1<<11),
            (1<<0)|(1<<3)|(1<<5)|(1<<8)|(1<<10),
            (1<<0)|(1<<2)|(1<<4)|(1<<7)|(1<<11),
            (1<<0)|(1<<2)|(1<<4)|(1<<5)|(1<<7)|(1<<8)|(1<<10)
        ]
        return masks[max(0, min(masks.count - 1, index))]
    }

    private func syncDSPFromParameters() {
        apply(BAParameterAddress.pattern.rawValue, pattern.value)
        apply(BAParameterAddress.division.rawValue, division.value)
        apply(BAParameterAddress.octaves.rawValue, octaves.value)
        apply(BAParameterAddress.gate.rawValue, gate.value)
        apply(BAParameterAddress.swing.rawValue, swing.value)
        apply(BAParameterAddress.latch.rawValue, latch.value)
        apply(BAParameterAddress.hostSync.rawValue, hostSync.value)
        apply(BAParameterAddress.freeBPM.rawValue, freeBPM.value)
        apply(BAParameterAddress.scaleLock.rawValue, scaleLock.value)
        apply(BAParameterAddress.root.rawValue, root.value)
        apply(BAParameterAddress.scale.rawValue, scale.value)
    }

    private func apply(_ address: AUParameterAddress, _ value: AUValue) {
        switch address {
        case BAParameterAddress.pattern.rawValue: dsp.pattern = BAArpPattern(rawValue: Int(value)) ?? .up
        case BAParameterAddress.division.rawValue: dsp.division = BAArpDivision(rawValue: Int(value)) ?? .sixteenth
        case BAParameterAddress.octaves.rawValue: dsp.octaves = Int(value.rounded())
        case BAParameterAddress.gate.rawValue: dsp.gate = value
        case BAParameterAddress.swing.rawValue: dsp.swing = value
        case BAParameterAddress.latch.rawValue: dsp.latch = value >= 0.5
        case BAParameterAddress.hostSync.rawValue: dsp.hostSync = value >= 0.5
        case BAParameterAddress.freeBPM.rawValue: dsp.freeBPM = Double(value)
        case BAParameterAddress.scaleLock.rawValue: dsp.scaleLock = value >= 0.5
        case BAParameterAddress.root.rawValue: dsp.rootPitchClass = Int(value.rounded())
        case BAParameterAddress.scale.rawValue: dsp.scaleMask = scaleMask(Int(value.rounded()))
        default: break
        }
    }

    private func value(for address: AUParameterAddress) -> AUValue {
        switch address {
        case BAParameterAddress.pattern.rawValue: return AUValue(dsp.pattern.rawValue)
        case BAParameterAddress.division.rawValue: return AUValue(dsp.division.rawValue)
        case BAParameterAddress.octaves.rawValue: return AUValue(dsp.octaves)
        case BAParameterAddress.gate.rawValue: return dsp.gate
        case BAParameterAddress.swing.rawValue: return dsp.swing
        case BAParameterAddress.latch.rawValue: return dsp.latch ? 1 : 0
        case BAParameterAddress.hostSync.rawValue: return dsp.hostSync ? 1 : 0
        case BAParameterAddress.freeBPM.rawValue: return AUValue(dsp.freeBPM)
        case BAParameterAddress.scaleLock.rawValue: return dsp.scaleLock ? 1 : 0
        case BAParameterAddress.root.rawValue: return AUValue(dsp.rootPitchClass)
        case BAParameterAddress.scale.rawValue: return scale.value
        default: return 0
        }
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        // The host calls this on the real-time render thread. This starter parses
        // incoming MIDI 1.0 events, asks the C++ kernel for arp output, and forwards
        // the generated MIDI through midiOutputEventBlock.
        return { [weak self] actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let self else { return noErr }

            var tempo = self.dsp.hostSync ? 120.0 : self.dsp.freeBPM
            var beatPosition = 0.0
            if let musicalContext = self.musicalContextBlock {
                var timeSigNumerator: Double = 4
                var timeSigDenominator: Int = 4
                var sampleOffsetToNextBeat: Int = 0
                var currentMeasureDownbeat: Double = 0
                _ = musicalContext(&tempo,
                                   &timeSigNumerator,
                                   &timeSigDenominator,
                                   &beatPosition,
                                   &sampleOffsetToNextBeat,
                                   &currentMeasureDownbeat)
            }

            let blockStart = Int64(timestamp.pointee.mSampleTime.rounded(.towardZero))

            if self.dsp.hostSync,
               let previousSample = self.lastHostSampleTime,
               let previousBeat = self.lastHostBeatPosition {
                let sampleDelta = Double(blockStart - previousSample)
                let beatDelta = beatPosition - previousBeat
                if sampleDelta > 0, beatDelta > 0.000001, tempo > 1 {
                    let estimate = sampleDelta * tempo / (60.0 * beatDelta)
                    if estimate >= 8_000, estimate <= 384_000 {
                        self.timingSampleRate = estimate
                    }
                }
            }
            self.lastHostSampleTime = blockStart
            self.lastHostBeatPosition = beatPosition

            var incoming = [BAMidiEvent]()
            incoming.reserveCapacity(32)
            var event = realtimeEventListHead
            while let e = event {
                if e.pointee.head.eventType == .MIDI {
                    let m = e.pointee.MIDI
                    let offset64 = Int64(m.eventSampleTime) - blockStart
                    let maxOffset = max(Int64(0), Int64(frameCount) - 1)
                    let offset = Int32(max(Int64(0), min(maxOffset, offset64)))
                    let data = m.data
                    incoming.append(BAMidiEvent(sampleOffset: offset,
                                                status: data.0,
                                                data1: m.length > 1 ? data.1 : 0,
                                                data2: m.length > 2 ? data.2 : 0))
                }
                event = e.pointee.head.next
            }

            let out = self.midiOutputEventBlock
            incoming.withUnsafeBufferPointer { buffer in
                self.dsp.processBlockStartSampleTime(blockStart,
                                                     frameCount: Int32(frameCount),
                                                     sampleRate: self.timingSampleRate,
                                                     hostTempo: tempo,
                                                     hostBeatPosition: beatPosition,
                                                     inputEvents: buffer.baseAddress,
                                                     inputCount: Int32(buffer.count)) { midi in
                    var bytes = (midi.status, midi.data1, midi.data2)
                    withUnsafeBytes(of: &bytes) { raw in
                        guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                        _ = out?(AUEventSampleTimeImmediate + AUEventSampleTime(midi.sampleOffset),
                                 0,
                                 3,
                                 base)
                    }
                }
            }
            return noErr
        }
    }
}
