import AudioToolbox

enum BAParameterAddress: AUParameterAddress {
    case pattern = 0
    case division = 1
    case octaves = 2
    case gate = 3
    case swing = 4
    case latch = 5
    case hostSync = 6
    case freeBPM = 7
    case scaleLock = 8
    case root = 9
    case scale = 10
}
