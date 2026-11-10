import SwiftUI

// Content layer: marka zemini. Cam değil; camın kırdığı ışığı veren arka plan.
struct BrandBackground: View {
    var body: some View {
        ZStack {
            Brand.ink
            RadialGradient(colors: [Brand.electric.opacity(0.55), .clear],
                           center: UnitPoint(x: 0.1, y: 0.3), startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Color(red: 0, green: 0.28, blue: 1).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.95, y: 0.75), startRadius: 0, endRadius: 300)
            RadialGradient(colors: [Color(red: 0.25, green: 0.59, blue: 1).opacity(0.22), .clear],
                           center: UnitPoint(x: 0.6, y: 0.0), startRadius: 0, endRadius: 200)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// Content layer: bir push baloncuğu. Düz renkli, cam yok.
struct PushBubble: View {
    let push: Push
    let isMine: Bool
    let route: String

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .foregroundStyle(.white)
                .background { bubbleShape.fill(isMine ? Brand.bubbleMine : Brand.bubbleOther.opacity(0.85)) }
                .overlay { bubbleShape.stroke(isMine ? Color.white.opacity(0.18) : Brand.bubbleStroke, lineWidth: 1) }
                .shadow(color: isMine ? Brand.bubbleMine.opacity(0.45) : .clear, radius: 14, y: 6)

            HStack(spacing: 6) {
                Text(route)
                if push.pinned {
                    Label("Sabit", systemImage: "pin.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Brand.pin)
                }
                Text(push.date, format: .dateTime.hour().minute())
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Brand.meta)
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .padding(isMine ? .leading : .trailing, 48)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 20,
            bottomLeadingRadius: isMine ? 20 : 6,
            bottomTrailingRadius: isMine ? 6 : 20,
            topTrailingRadius: 20,
            style: .continuous
        )
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !push.title.isEmpty {
                Text(push.title).font(.headline.weight(.heavy))
            }
            switch push.type {
            case .note:
                Text(push.body).font(.body)
            case .link:
                Text("LİNK")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(isMine ? Color.white.opacity(0.85) : Brand.meta)
                Text(displayURL)
                    .font(.body.weight(.bold))
                    .lineLimit(3)
                if !push.body.isEmpty { Text(push.body).font(.subheadline) }
            case .file:
                HStack(spacing: 12) {
                    Text(push.fileExtension)
                        .font(.caption2.weight(.heavy))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(isMine ? 0.18 : 0.1),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(push.fileName).font(.body.weight(.bold)).lineLimit(2)
                        Text("\(push.fileSize.byteText) · açmak için dokun")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }
                if !push.body.isEmpty { Text(push.body).font(.subheadline).padding(.top, 4) }
            }
        }
    }

    private var displayURL: String {
        guard let url = URL(string: push.url), let host = url.host() else { return push.url }
        let path = url.path() == "/" ? "" : url.path()
        return host.replacingOccurrences(of: "www.", with: "") + path
    }
}

struct DayLabel: View {
    let date: Date

    var body: some View {
        Text(label.uppercased(with: Locale(identifier: "tr_TR")))
            .font(.caption2.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(Brand.meta)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Bugün" }
        if cal.isDateInYesterday(date) { return "Dün" }
        return date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "tr_TR")))
    }
}

struct DeviceIcon: View {
    let device: Device?
    var highlighted = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(highlighted ? AnyShapeStyle(Brand.electric) : AnyShapeStyle(Color.white.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityHidden(true)
    }

    private var symbol: String {
        guard let device else { return "dot.radiowaves.left.and.right" }
        return device.isPhone ? "iphone" : "laptopcomputer"
    }
}
