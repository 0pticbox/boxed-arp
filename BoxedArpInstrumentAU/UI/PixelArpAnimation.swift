import SwiftUI

struct CRTArpAnimation: View {
    let currentStep: Int
    let currentNote: Int
    let heldNotes: Int
    let pattern: Int
    let phase: Double
    let distortion: Double
    let isRunning: Bool
    let skin: PicoSkin

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas(opaque: true, rendersAsynchronously: true) { context, size in
                drawBezel(context: &context, size: size)
                let screen = CGRect(x: 8, y: 7, width: max(1, size.width - 16), height: max(1, size.height - 14))
                context.clip(to: Path(roundedRect: screen, cornerRadius: 12))
                context.fill(Path(screen), with: .color(skin.background))

                drawSignal(context: &context, screen: screen)
                drawArpSprite(context: &context, screen: screen)
                drawScanlines(context: &context, screen: screen)
                drawStatic(context: &context, screen: screen)
                    drawRollBar(context: &context, screen: screen)
                }
                .opacity(isRunning ? 1.0 : 0.42)

                if !isRunning {
                    Text("ARP STOP")
                        .font(.opticPixel(7))
                        .foregroundStyle(skin.danger)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(skin.background.opacity(0.88))
                        .overlay(Rectangle().stroke(skin.danger, lineWidth: 1))
                }
            }
        }
        .accessibilityLabel(isRunning ? "Running CRT arpeggiator monitor" : "Stopped CRT arpeggiator monitor")
    }

    private func drawBezel(context: inout GraphicsContext, size: CGSize) {
        let outer = CGRect(origin: .zero, size: size)
        context.fill(Path(roundedRect: outer, cornerRadius: 15), with: .color(skin.panelAlt))
        context.stroke(Path(roundedRect: outer.insetBy(dx: 1, dy: 1), cornerRadius: 14),
                       with: .color(skin.text.opacity(0.85)), lineWidth: 2)
        context.fill(Path(ellipseIn: CGRect(x: size.width - 8, y: size.height - 7, width: 3, height: 3)),
                     with: .color(skin.accent))
    }

    private func drawSignal(context: inout GraphicsContext, screen: CGRect) {
        let rows = 9
        let active = currentStep >= 0 ? currentStep % rows : Int(abs(sin(phase * 0.7)) * Double(rows - 1))
        let note = max(0, currentNote)

        for index in 0..<rows {
            let progress = CGFloat(index) / CGFloat(max(1, rows - 1))
            let barWidth = screen.width * (0.16 + CGFloat((index * 5 + note) % 10) / 14.0)
            let y = screen.maxY - 12 - progress * (screen.height - 26)
            let wobble = sin(phase * 3.0 + Double(index) * 1.7) * distortion * 9.0
            let x = screen.midX - barWidth / 2 + CGFloat(wobble)
            let color = index == active ? skin.accent2 : skin.panelAlt.opacity(0.88)
            context.fill(Path(CGRect(x: x, y: y, width: barWidth, height: 4)), with: .color(color))
        }

        var path = Path()
        let points = 42
        for index in 0..<points {
            let t = CGFloat(index) / CGFloat(points - 1)
            let x = screen.minX + t * screen.width
            let harmonic = sin(Double(t) * .pi * Double(3 + (currentStep >= 0 ? currentStep % 5 : 2)) + phase * 2.6)
            let noise = sin(Double(index * 11) + phase * 8.0) * distortion
            let y = screen.midY + CGFloat(harmonic * 11.0 + noise * 7.0)
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(skin.accent.opacity(0.85)), lineWidth: 2)
    }

    private func drawArpSprite(context: inout GraphicsContext, screen: CGRect) {
        let pixel = max(2, floor(min(screen.width / 82, screen.height / 42)))
        let idle = Int(abs(sin(phase * 0.8)) * 7.0)
        let step = currentStep >= 0 ? currentStep % 8 : idle
        let xBase = screen.minX + 12 + CGFloat(step) * max(pixel * 4, (screen.width - 40) / 8)
        let noteLift = currentNote >= 0 ? CGFloat(currentNote % 12) / 11.0 : CGFloat((sin(phase) + 1) * 0.25)
        let yBase = screen.maxY - 34 - noteLift * max(10, screen.height * 0.30)
        let glitch = CGFloat(sin(phase * 17.0) * distortion * 8.0)
        let x = xBase + glitch

        let pixels: [(CGFloat, CGFloat, Color)] = [
            (2, 0, skin.text),
            (1, 1, skin.accent), (2, 1, skin.accent2), (3, 1, skin.accent),
            (0, 2, skin.text), (1, 2, skin.accent2), (2, 2, skin.accent2), (3, 2, skin.accent2), (4, 2, skin.text),
            (1, 3, skin.panelAlt), (2, 3, skin.text), (3, 3, skin.panelAlt)
        ]

        let split = CGFloat(distortion * 3.0)
        for (px, py, color) in pixels {
            let rect = CGRect(x: x + px * pixel, y: yBase + py * pixel, width: pixel, height: pixel)
            if distortion > 0.18 {
                context.fill(Path(rect.offsetBy(dx: -split, dy: 0)), with: .color(skin.danger.opacity(0.34)))
                context.fill(Path(rect.offsetBy(dx: split, dy: 0)), with: .color(skin.accent2.opacity(0.34)))
            }
            context.fill(Path(rect), with: .color(color))
        }

        let direction: CGFloat = pattern == 1 ? 1 : -1
        for trail in 1...3 {
            let rect = CGRect(x: x + direction * CGFloat(trail) * pixel * 2,
                              y: yBase + pixel * 2,
                              width: pixel,
                              height: pixel)
            context.fill(Path(rect), with: .color(skin.accent.opacity(0.8 - Double(trail) * 0.16)))
        }
    }

    private func drawScanlines(context: inout GraphicsContext, screen: CGRect) {
        let alpha = 0.07 + distortion * 0.08
        var y = screen.minY
        while y < screen.maxY {
            context.fill(Path(CGRect(x: screen.minX, y: y, width: screen.width, height: 1)),
                         with: .color(skin.shadow.opacity(alpha)))
            y += 3
        }
    }

    private func drawStatic(context: inout GraphicsContext, screen: CGRect) {
        let count = 6 + Int(distortion * 34)
        for index in 0..<count {
            let seed = Double(index * 97 + currentStep * 19 + heldNotes * 31)
            let xUnit = abs(sin(seed + phase * 13.1)).truncatingRemainder(dividingBy: 1)
            let yUnit = abs(sin(seed * 0.41 + phase * 19.7)).truncatingRemainder(dividingBy: 1)
            let width = 1 + CGFloat(abs(sin(seed)) * distortion * 12)
            let rect = CGRect(x: screen.minX + CGFloat(xUnit) * screen.width,
                              y: screen.minY + CGFloat(yUnit) * screen.height,
                              width: width,
                              height: 1)
            context.fill(Path(rect), with: .color((index % 3 == 0 ? skin.text : skin.accent).opacity(0.20 + distortion * 0.45)))
        }
    }

    private func drawRollBar(context: inout GraphicsContext, screen: CGRect) {
        guard distortion > 0.28 else { return }
        let position = CGFloat((phase * (0.12 + distortion * 0.25)).truncatingRemainder(dividingBy: 1.0))
        let y = screen.minY + position * screen.height
        context.fill(Path(CGRect(x: screen.minX, y: y, width: screen.width, height: 5 + CGFloat(distortion * 8))),
                     with: .color(skin.text.opacity(0.05 + distortion * 0.12)))
    }
}
