import SwiftUI

struct PixelPanel<Content: View>: View {
    let title: String
    let skin: PicoSkin
    let content: Content

    init(_ title: String, skin: PicoSkin, @ViewBuilder content: () -> Content) {
        self.title = title
        self.skin = skin
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Rectangle()
                    .fill(skin.accent)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.opticPixel(6.5))
                    .foregroundStyle(skin.text)
                Spacer(minLength: 0)
            }
            content
        }
        .padding(5)
        .background(skin.panel)
        .overlay(Rectangle().stroke(skin.text.opacity(0.82), lineWidth: 1.5))
        .shadow(color: skin.shadow.opacity(0.65), radius: 0, x: 2, y: 2)
    }
}

struct PixelButton: View {
    let label: String
    let isSelected: Bool
    let skin: PicoSkin
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.opticPixel(6.5))
                .foregroundStyle(isSelected ? skin.background : skin.text)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(maxWidth: .infinity, minHeight: 18)
                .padding(.horizontal, 3)
                .background(isSelected ? skin.accent : skin.panelAlt)
                .overlay(Rectangle().stroke(isSelected ? skin.text : skin.muted.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct PixelMenu: View {
    let label: String
    let value: Int
    let options: [String]
    let skin: PicoSkin
    let onSelect: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                Button(options[index]) { onSelect(index) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.opticPixel(6.5))
                    .foregroundStyle(skin.muted)
                Spacer(minLength: 2)
                Text(options[min(max(value, 0), options.count - 1)])
                    .font(.opticPixel(6.5))
                    .foregroundStyle(skin.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
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
}

struct PixelToggle: View {
    let label: String
    let value: Bool
    let skin: PicoSkin
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                ZStack {
                    Rectangle()
                        .fill(value ? skin.accent : skin.panelAlt)
                        .frame(width: 16, height: 16)
                    if value {
                        Rectangle()
                            .fill(skin.background)
                            .frame(width: 6, height: 6)
                    }
                }
                .overlay(Rectangle().stroke(skin.text, lineWidth: 1))

                Text(label)
                    .font(.opticPixel(6.5))
                    .foregroundStyle(skin.text)
                Spacer()
                Text(value ? "ON" : "OFF")
                    .font(.opticPixel(6.5))
                    .foregroundStyle(value ? skin.accent : skin.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PixelSlider: View {
    let label: String
    let value: Float
    let range: ClosedRange<Float>
    let display: String
    let skin: PicoSkin
    let onEditingChanged: (Bool) -> Void
    let onChange: (Float) -> Void

    @State private var editing = false

    init(label: String,
         value: Float,
         range: ClosedRange<Float>,
         display: String,
         skin: PicoSkin,
         onEditingChanged: @escaping (Bool) -> Void = { _ in },
         onChange: @escaping (Float) -> Void) {
        self.label = label
        self.value = value
        self.range = range
        self.display = display
        self.skin = skin
        self.onEditingChanged = onEditingChanged
        self.onChange = onChange
    }

    var normalized: CGFloat {
        let width = max(0.0001, range.upperBound - range.lowerBound)
        return CGFloat((value - range.lowerBound) / width).clamped(to: 0...1)
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.opticPixel(6.5))
                    .foregroundStyle(skin.muted)
                Spacer(minLength: 2)
                Text(display)
                    .font(.opticPixel(6.5))
                    .foregroundStyle(skin.text)
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                let trackWidth = max(1, proxy.size.width)
                ZStack(alignment: .leading) {
                    Rectangle().fill(skin.background)
                    Rectangle()
                        .fill(skin.accent2)
                        .frame(width: trackWidth * normalized)
                    Rectangle()
                        .fill(skin.text)
                        .frame(width: 3)
                        .offset(x: max(0, trackWidth * normalized - 1.5))
                }
                .overlay(Rectangle().stroke(skin.muted, lineWidth: 1))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !editing {
                                editing = true
                                onEditingChanged(true)
                            }
                            let fraction = Float((gesture.location.x / trackWidth).clamped(to: 0...1))
                            onChange(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
                        }
                        .onEnded { _ in
                            if editing {
                                editing = false
                                onEditingChanged(false)
                            }
                        }
                )
            }
            .frame(height: 9)
        }
    }
}

struct PixelReadout: View {
    let label: String
    let value: String
    let skin: PicoSkin

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.opticPixel(6.5))
                .foregroundStyle(skin.muted)
            Text(value)
                .font(.opticPixel(9))
                .foregroundStyle(skin.accent)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .background(skin.background)
        .overlay(Rectangle().stroke(skin.panelAlt, lineWidth: 1))
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
