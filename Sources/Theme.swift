import SwiftUI
import AppKit

// MARK: - Palette

enum Theme {
    static let bg         = Color(red: 0.075, green: 0.086, blue: 0.082)
    static let card       = Color(red: 0.115, green: 0.129, blue: 0.122)
    static let cardStroke = Color.white.opacity(0.06)
    static let well       = Color.black.opacity(0.35)

    static let brand  = Color(red: 0.73, green: 0.85, blue: 0.77)

    /// Severity runs warm: brand → amber → red. Nothing green anywhere, and
    /// colour only escalates when a limit is actually worth looking at.
    static let amber  = Color(red: 0.914, green: 0.706, blue: 0.235)
    static let ember  = Color(red: 0.925, green: 0.514, blue: 0.196)
    static let alert  = Color(red: 0.882, green: 0.302, blue: 0.263)

    static let purple = Color(red: 0.600, green: 0.510, blue: 0.960)
    static let pink   = Color(red: 0.941, green: 0.471, blue: 0.659)
    static let blue   = Color(red: 0.427, green: 0.561, blue: 0.918)

    static let dim   = Color.white.opacity(0.68)
    static let faint = Color.white.opacity(0.48)

    /// Per-account accent colours, picked deterministically from the config dir.
    static let palette: [Color] = Array(repeating: brand, count: 5)

    /// How a usage percentage reads at a glance.
    static func vibe(_ percent: Double) -> (word: String, color: Color) {
        switch percent {
        case ..<70:  return ("Available", brand)
        case ..<85:  return ("In use", brand)
        case ..<95:  return ("Near limit", amber)
        case ..<100: return ("Almost at limit", ember)
        default:    return ("Limit reached", alert)
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

/// Provider-neutral application title.
struct Wordmark: View {
    var size: CGFloat = 15
    var body: some View {
        Text("Gauge")
            .foregroundStyle(.white)
            .font(.system(size: size, weight: .semibold))
            .tracking(-0.5)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.lowercased().prefix(1).uppercased() + text.lowercased().dropFirst())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.1)
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
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(filled ? 0.10 : 0)))
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
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.12 : 0.04)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(symbol == "arrow.clockwise" ? "Refresh usage" : "Manage accounts")
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
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 9).fill(color.opacity(hovering ? 0.24 : 0.12)))
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
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(hovering ? 0.12 : 0.04)))
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if showLabel {
                    Text(bar.label == "included" ? "Subscription" : bar.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let reset = bar.resetsAt {
                    Text(relativeReset(reset)).font(.system(size: 9)).foregroundStyle(Theme.faint)
                }
                Text("\(Int(bar.percent.rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(bar.percent >= 85 ? color : .white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.09))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * max(0, min(1, bar.percent / 100)))
                }
            }
            .frame(height: height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bar.label), \(Int(bar.percent.rounded())) percent used. \(relativeReset(bar.resetsAt))")
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
                .accessibilityLabel(title)
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
            .accessibilityLabel(placeholder)
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


// MARK: - Provider-neutral identity

struct GaugeMark: View {
    var height: CGFloat = 17
    var body: some View {
        HStack(alignment: .bottom, spacing: height * 0.16) {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: height * 0.08)
                    .fill(Theme.brand.opacity(index == 2 ? 0.45 : 1))
                    .frame(width: height * 0.22, height: height * [0.45, 1, 0.7][index])
            }
        }
        .frame(width: height, height: height)
        .accessibilityHidden(true)
    }
}

struct ProviderMark: View {
    let provider: AIProvider
    var size: CGFloat = 32

    var body: some View {
        Text(provider == .grok ? "x" : (provider == .codex ? "O" : "C"))
            .font(.system(size: size * 0.48, weight: .medium, design: .serif))
            .foregroundStyle(Theme.brand)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26).fill(Theme.brand.opacity(0.08)))
            .accessibilityLabel(provider.title)
    }
}

struct ProviderFilter: View {
    @Binding var selection: AIProvider?
    let profiles: [Profile]

    var body: some View {
        HStack(spacing: 4) {
            option(nil, title: "All")
            ForEach(AIProvider.allCases) { provider in
                option(provider, title: provider.title)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
    }

    private func option(_ provider: AIProvider?, title: String) -> some View {
        let active = selection == provider
        let count = profiles.filter { provider == nil || $0.provider == provider }.count
        return Button { selection = provider } label: {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 11, weight: active ? .semibold : .medium))
                Text("\(count)").font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(active ? Theme.brand : Theme.faint)
            }
            .foregroundStyle(active ? .white : Theme.dim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(active ? Color.white.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) accounts")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
