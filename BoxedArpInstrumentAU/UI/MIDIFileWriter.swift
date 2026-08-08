import Foundation

/// Writes BOXED ARP's generated note stream as a Standard MIDI File (format 0).
/// The exported file contains the post-arp, post-scale notes — exactly what the
/// synth engine was asked to play — rather than only the chord used as input.
enum MIDIFileWriter {
    private static let ticksPerQuarter: UInt16 = 480

    private struct TrackEvent {
        let tick: Int
        let order: Int
        let bytes: [UInt8]
    }

    static func makeFile(events sourceEvents: [BoxedArpMIDIEvent],
                         fallbackTempo: Double) -> Data? {
        let supportedCommands: Set<UInt8> = [0x80, 0x90, 0xB0, 0xE0]
        let source = sourceEvents.enumerated()
            .filter { supportedCommands.contains($0.element.status & 0xF0) }
            .sorted { lhs, rhs in
                if lhs.element.sampleTime != rhs.element.sampleTime {
                    return lhs.element.sampleTime < rhs.element.sampleTime
                }
                return lhs.offset < rhs.offset
            }
        guard let firstPair = source.first else { return nil }
        let first = firstPair.element

        var trackEvents: [TrackEvent] = []
        let initialTempo = validTempo(first.tempo, fallback: fallbackTempo)
        trackEvents.append(TrackEvent(tick: 0, order: -2, bytes: tempoMetaEvent(initialTempo)))
        trackEvents.append(TrackEvent(tick: 0, order: -1, bytes: [0xFF, 0x03, 0x09] + Array("BOXED ARP".utf8)))

        var previousSampleTime = first.sampleTime
        var previousSampleRate = validSampleRate(first.sampleRate)
        var previousTempo = initialTempo
        var accumulatedTicks = 0.0
        var lastTempoMeta = initialTempo
        var sequence = 0

        for pair in source {
            let event = pair.element
            let deltaSamples = max(Int64(0), event.sampleTime - previousSampleTime)
            accumulatedTicks += Double(deltaSamples) / previousSampleRate
                * previousTempo / 60.0
                * Double(ticksPerQuarter)
            let tick = max(0, Int(accumulatedTicks.rounded()))

            let eventTempo = validTempo(event.tempo, fallback: previousTempo)
            if abs(eventTempo - lastTempoMeta) >= 0.05 {
                trackEvents.append(TrackEvent(tick: tick, order: sequence, bytes: tempoMetaEvent(eventTempo)))
                sequence += 1
                lastTempoMeta = eventTempo
            }

            trackEvents.append(TrackEvent(tick: tick, order: sequence,
                                          bytes: [event.status, event.data1, event.data2]))
            sequence += 1
            previousSampleTime = event.sampleTime
            previousSampleRate = validSampleRate(event.sampleRate)
            previousTempo = eventTempo
        }

        trackEvents.sort {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            return $0.order < $1.order
        }

        var activeCounts: [Int: Int] = [:]
        for event in trackEvents where event.bytes.count == 3 && event.bytes[0] < 0xF0 {
            let command = event.bytes[0] & 0xF0
            guard command == 0x80 || command == 0x90 else { continue }
            let key = Int(event.bytes[0] & 0x0F) * 128 + Int(event.bytes[1])
            if command == 0x90 && event.bytes[2] > 0 {
                activeCounts[key, default: 0] += 1
            } else if let count = activeCounts[key], count > 0 {
                activeCounts[key] = count - 1
            }
        }

        let closingTick = (trackEvents.last?.tick ?? 0) + max(1, Int(ticksPerQuarter) / 16)
        var closingOrder = sequence
        for (key, count) in activeCounts where count > 0 {
            let channel = UInt8((key / 128) & 0x0F)
            let note = UInt8(key % 128)
            for _ in 0..<count {
                trackEvents.append(TrackEvent(tick: closingTick, order: closingOrder,
                                              bytes: [0x80 | channel, note, 0]))
                closingOrder += 1
            }
        }
        trackEvents.append(TrackEvent(tick: closingTick, order: closingOrder,
                                      bytes: [0xE0, 0x00, 0x40]))

        trackEvents.sort {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            return $0.order < $1.order
        }

        var track = Data()
        var previousTick = 0
        for event in trackEvents {
            let delta = max(0, event.tick - previousTick)
            track.append(contentsOf: variableLength(delta))
            track.append(contentsOf: event.bytes)
            previousTick = event.tick
        }
        track.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])

        var file = Data()
        file.append(contentsOf: Array("MThd".utf8))
        file.appendBE(UInt32(6))
        file.appendBE(UInt16(0))
        file.appendBE(UInt16(1))
        file.appendBE(ticksPerQuarter)
        file.append(contentsOf: Array("MTrk".utf8))
        file.appendBE(UInt32(track.count))
        file.append(track)
        return file
    }

    private static func validTempo(_ tempo: Double, fallback: Double) -> Double {
        tempo.isFinite && tempo >= 20 && tempo <= 400 ? tempo : max(20, min(400, fallback))
    }

    private static func validSampleRate(_ sampleRate: Double) -> Double {
        sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 44_100
    }

    private static func tempoMetaEvent(_ tempo: Double) -> [UInt8] {
        let microseconds = UInt32(max(1, min(0xFF_FF_FF, Int((60_000_000.0 / tempo).rounded()))))
        return [0xFF, 0x51, 0x03,
                UInt8((microseconds >> 16) & 0xFF),
                UInt8((microseconds >> 8) & 0xFF),
                UInt8(microseconds & 0xFF)]
    }

    private static func variableLength(_ value: Int) -> [UInt8] {
        var value = max(0, value)
        var buffer = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 {
            buffer.insert(UInt8((value & 0x7F) | 0x80), at: 0)
            value >>= 7
        }
        return buffer
    }
}

private extension Data {
    mutating func appendBE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendBE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
