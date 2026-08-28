import SwiftUI
import AppKit

// MARK: - Palette

enum Theme {
    static let bg         = Color(red: 0.055, green: 0.067, blue: 0.086)   // #0E1116
    static let card       = Color(red: 0.090, green: 0.102, blue: 0.129)   // #171A21
    static let cardStroke = Color.white.opacity(0.06)
    static let well       = Color.black.opacity(0.35)

    /// The brand colour — the mascot's terracotta, rgb(202, 124, 94).
    static let brand  = Color(red: 202/255, green: 124/255, blue: 94/255)  // #CA7C5E

    /// Severity runs warm: brand → amber → red. Nothing green anywhere, and
    /// colour only escalates when a limit is actually worth looking at.
    static let amber  = Color(red: 0.914, green: 0.706, blue: 0.235)
    static let ember  = Color(red: 0.925, green: 0.514, blue: 0.196)
    static let alert  = Color(red: 0.882, green: 0.302, blue: 0.263)

    static let purple = Color(red: 0.600, green: 0.510, blue: 0.960)
    static let pink   = Color(red: 0.941, green: 0.471, blue: 0.659)
    static let blue   = Color(red: 0.427, green: 0.561, blue: 0.918)

    static let dim   = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.35)

    /// Per-account accent colours, picked deterministically from the config dir.
    static let palette: [Color] = [brand, pink, purple, blue, amber]

    /// How a usage percentage reads at a glance.
    static func vibe(_ percent: Double) -> (word: String, color: Color) {
        switch percent {
        case ..<40:  return ("plenty left", brand)
        case ..<70:  return ("cruising", brand)
        case ..<85:  return ("watch it", amber)
        case ..<95:  return ("almost cooked", ember)
        default:     return ("cooked", alert)
        }
    }
}

// MARK: - Building blocks

extension View {
    /// A soft, borderless surface. Outlined cards made every screen read as a
    /// stack of boxes, so surfaces now only appear on hover or selection.
    func softSurface(_ on: Bool = true, radius: CGFloat = 16,
                     opacity: Double = 0.055) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(on ? opacity : 0)))
    }
}

/// A one-pixel rule. Rows are separated by these instead of being boxed.
struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// The two-tone wordmark. HY in white, DRA in neon, heavy and italic.
struct Wordmark: View {
    var size: CGFloat = 15
    var body: some View {
        HStack(spacing: 0) {
            Text("CLAUDE").foregroundStyle(.white)
            Text("SWITCH").foregroundStyle(Theme.brand)
        }
        .font(.system(size: size, weight: .black, design: .rounded))
        .italic()
        .tracking(0.5)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(1.3)
            .foregroundStyle(Theme.faint)
    }
}

/// Small capsule tag — plan tier, "default", "shared quota".
struct Chip: View {
    let text: String
    var color: Color = Theme.dim
    var filled = true

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(filled ? 0.14 : 0)))
            .overlay(Capsule().stroke(color.opacity(filled ? 0.45 : 0.35), lineWidth: 1))
            .foregroundStyle(color)
    }
}

struct CircleButton: View {
    let symbol: String
    var size: CGFloat = 28
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.39, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The big pill CTA: tinted fill, solid stroke, chevron on the right.
struct ActionButton: View {
    let title: String
    var symbol: String = "play.fill"
    var color: Color = Theme.brand
    var height: CGFloat = 44
    /// Narrow, inline uses drop the chevron so the label keeps its room.
    var showChevron = true
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(Capsule().fill(color.opacity(hovering ? 0.26 : 0.16)))
            .overlay(Capsule().stroke(color.opacity(hovering ? 0.95 : 0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Flat capsule button used in footers and toolbars.
struct PillButton: View {
    let title: String
    var symbol: String?
    var color: Color = .white
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                }
                Text(title).font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Rounded-square monogram tile, tinted with the account's accent.
struct Monogram: View {
    let text: String
    let color: Color
    var size: CGFloat = 34

    /// First letter of each word when the name has separators, so "work-alt"
    /// and "workday" don't both come out as "WO".
    private var initials: String {
        let parts = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if parts.count >= 2 {
            return (parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(text.filter { $0.isLetter || $0.isNumber }.prefix(2)).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.16)))
            .overlay(Circle().stroke(color.opacity(0.40), lineWidth: 1))
    }
}

/// Thin usage bar with a label and a percentage.
struct MiniBar: View {
    let bar: LimitBar
    var showLabel = true
    var height: CGFloat = 6

    private var color: Color { Theme.vibe(bar.percent).color }

    var body: some View {
        HStack(spacing: 7) {
            if showLabel {
                Text(bar.label)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .frame(width: 38, alignment: .leading)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.09))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.75), color],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(height, geo.size.width * min(1, bar.percent / 100)))
                }
            }
            .frame(height: height)
            Text("\(Int(bar.percent.rounded()))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(bar.percent >= 85 ? color : Theme.dim)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

/// Toggle row styled for the dark theme.
struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.dim)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.brand)
                .controlSize(.small)
        }
    }
}

/// Dark text field with a well background.
struct WellField: View {
    let placeholder: String
    var mono = false
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium,
                          design: mono ? .monospaced : .default))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.well))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10)))
    }
}


// MARK: - Bundled artwork

enum Art {
    private static func bundled(_ name: String, template: Bool) -> NSImage? {
        guard let img = NSImage(named: name) else { return nil }
        img.isTemplate = template
        return img
    }
    /// Full-colour mascot for in-app chrome.
    static let mascot = bundled("mascot", template: false)
    /// Silhouette for the menu bar; macOS tints template images to match.
    static let menuBar = bundled("menubar", template: true)
}

/// The mascot, falling back to a symbol if the bundle resource is missing.
struct MascotMark: View {
    var height: CGFloat = 17
    var body: some View {
        if let m = Art.mascot {
            Image(nsImage: m)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
        } else {
            Image(systemName: "bolt.fill")
                .font(.system(size: height * 0.75))
                .foregroundStyle(Theme.brand)
        }
    }
}
