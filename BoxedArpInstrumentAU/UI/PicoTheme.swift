import SwiftUI

struct PicoSkin {
    let name: String
    let background: Color
    let panel: Color
    let panelAlt: Color
    let text: Color
    let muted: Color
    let accent: Color
    let accent2: Color
    let danger: Color
    let shadow: Color

    static let skins: [PicoSkin] = [
        PicoSkin(
            name: "NIGHT",
            background: Color(hex: 0x1D2B53),
            panel: Color(hex: 0x0B1636),
            panelAlt: Color(hex: 0x263D68),
            text: Color(hex: 0xFFF1E8),
            muted: Color(hex: 0xC2C3C7),
            accent: Color(hex: 0xFF77A8),
            accent2: Color(hex: 0x29ADFF),
            danger: Color(hex: 0xFF004D),
            shadow: Color(hex: 0x000000)
        ),
        PicoSkin(
            name: "SKY",
            background: Color(hex: 0x125359),
            panel: Color(hex: 0x1A345A),
            panelAlt: Color(hex: 0x277E8E),
            text: Color(hex: 0xFFF7D6),
            muted: Color(hex: 0xABF1EA),
            accent: Color(hex: 0xFFCC4A),
            accent2: Color(hex: 0x5DE4C7),
            danger: Color(hex: 0xFF6B6B),
            shadow: Color(hex: 0x082A35)
        ),
        PicoSkin(
            name: "CRISIS",
            background: Color(hex: 0x2A0E32),
            panel: Color(hex: 0x441752),
            panelAlt: Color(hex: 0x6B245D),
            text: Color(hex: 0xFFF1E8),
            muted: Color(hex: 0xD8B4D8),
            accent: Color(hex: 0xFFEC27),
            accent2: Color(hex: 0xFF77A8),
            danger: Color(hex: 0xFF3B30),
            shadow: Color(hex: 0x120519)
        ),
        PicoSkin(
            name: "VOID",
            background: Color(hex: 0x090B18),
            panel: Color(hex: 0x11152A),
            panelAlt: Color(hex: 0x1B2344),
            text: Color(hex: 0xEDE7FF),
            muted: Color(hex: 0x8D94B8),
            accent: Color(hex: 0x9D7BFF),
            accent2: Color(hex: 0x5EF2C2),
            danger: Color(hex: 0xFF477E),
            shadow: Color(hex: 0x000000)
        ),
        PicoSkin(
            name: "AMBER",
            background: Color(hex: 0x2A1C0F),
            panel: Color(hex: 0x160F08),
            panelAlt: Color(hex: 0x49301A),
            text: Color(hex: 0xFFE8B5),
            muted: Color(hex: 0xC6A46A),
            accent: Color(hex: 0xFFB000),
            accent2: Color(hex: 0xFF6B35),
            danger: Color(hex: 0xFF3B30),
            shadow: Color(hex: 0x080402)
        ),
        PicoSkin(
            name: "ICE",
            background: Color(hex: 0x13212C),
            panel: Color(hex: 0x08131B),
            panelAlt: Color(hex: 0x244457),
            text: Color(hex: 0xF4FBFF),
            muted: Color(hex: 0xA5C4D4),
            accent: Color(hex: 0x66E3FF),
            accent2: Color(hex: 0xB7F7FF),
            danger: Color(hex: 0xFF5D8F),
            shadow: Color(hex: 0x02080C)
        ),
        PicoSkin(
            name: "PHOSPHOR",
            background: Color(hex: 0x102018),
            panel: Color(hex: 0x07110C),
            panelAlt: Color(hex: 0x1D3A29),
            text: Color(hex: 0xE8FFD9),
            muted: Color(hex: 0x8FCB91),
            accent: Color(hex: 0x66FF66),
            accent2: Color(hex: 0xD5FF40),
            danger: Color(hex: 0xFF4F64),
            shadow: Color(hex: 0x020502)
        )
    ]
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

extension Font {
    static func opticPixel(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
