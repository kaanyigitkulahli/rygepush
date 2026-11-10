import SwiftUI
import UIKit

// Ana ekran: push akışı.
// Functional layer (cam): sistem gezinme çubuğu ve araç çubuğu düğmeleri, cihaz filtresi,
// alttaki yazma çubuğu (tek bir GlassEffectContainer içinde) ve gönderme paneli (sistem sayfası).
// Content layer (cam yok): marka zemini ve push baloncukları.
struct FeedView: View {
    @Environment(PushStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var filter: FeedFilter = .all
    @State private var draft = ""
    @State private var attachment: Attachment?
    @State private var target = ""
    @State private var sending = false
    @State private var showSendOptions = false
    @State private var showDevices = false
    @FocusState private var inputFocused: Bool
    @Namespace private var composerNS

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if rows.isEmpty {
                            emptyState
                        }
                        ForEach(rows) { row in
                            switch row {
                            case .day(let date, _):
                                DayLabel(date: date)
                            case .push(let push):
                                bubble(for: push).id(push.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await store.sync() }
                .onChange(of: store.pushes.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .background { BrandBackground() }
            .navigationTitle("RygePush")
            .toolbar { toolbarContent }
            .safeAreaBar(edge: .top) { filterBar }
            .safeAreaInset(edge: .bottom) {
                composer
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            .sheet(isPresented: $showSendOptions) {
                SendOptionsSheet(target: $target, attachment: $attachment, draft: $draft)
            }
            .navigationDestination(isPresented: $showDevices) { DevicesView() }
        }
    }

    // MARK: Araç çubuğu (sistem camı; üstüne glassEffect eklenmez)

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Image("Logo")
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityLabel("RygePush")
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .topBarTrailing) {
            Button("Cihazlar ve ayarlar", systemImage: "iphone.and.arrow.forward") { showDevices = true }
        }
    }

    // MARK: Cihaz filtresi (özel cam, tek kap)

    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        filterChip("Tümü", value: .all)
                        ForEach(store.otherDevices) { device in
                            filterChip(device.name, value: .device(device.id))
                        }
                        filterChip("Sabit", value: .pinned, symbol: "pin")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            statusLine
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func filterChip(_ title: String, value: FeedFilter, symbol: String? = nil) -> some View {
        let selected = filter == value
        let label = Group {
            if let symbol { Label(title, systemImage: selected ? "\(symbol).fill" : symbol) } else { Text(title) }
        }
        .font(.subheadline.weight(selected ? .bold : .semibold))
        .padding(.horizontal, 4)

        if selected {
            Button { } label: { label }
                .buttonStyle(.glassProminent)
                .tint(Brand.electric)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button { withAnimation(.snappy) { filter = value } } label: { label }
                .buttonStyle(.glass)
                .tint(.white)
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let message = store.errorMessage {
            Button {
                store.errorMessage = nil
            } label: {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.7), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Kapatmak için dokun")
        } else if store.status == .offline {
            Label("Bağlantı yok, son kaydedilen pushlar gösteriliyor", systemImage: "wifi.slash")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Brand.meta)
        }
    }

    // MARK: Yazma çubuğu (tek GlassEffectContainer, safeAreaInset: @FocusState için)

    private var composer: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showSendOptions = true
                } label: {
                    Label("Kime: \(targetName)", systemImage: "chevron.down")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(.white)
                .accessibilityLabel("Kime gönderilecek: \(targetName). Değiştir")

                HStack(alignment: .bottom, spacing: 10) {
                    Button {
                        inputFocused = false
                        showSendOptions = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .tint(.white)
                    .accessibilityLabel("Fotoğraf ya da dosya ekle")
                    .glassEffectID("plus", in: composerNS)

                    VStack(alignment: .leading, spacing: 8) {
                        if let attachment {
                            attachmentChip(attachment)
                        }
                        HStack(alignment: .bottom, spacing: 8) {
                            TextField(attachment == nil ? "Not ya da link yaz…" : "Açıklama ekle (isteğe bağlı)",
                                      text: $draft, axis: .vertical)
                                .lineLimit(1...5)
                                .focused($inputFocused)
                                .padding(.vertical, 6)
                                .submitLabel(.send)

                            if canSend {
                                Button {
                                    Task { await send() }
                                } label: {
                                    Group {
                                        if sending { ProgressView().tint(.white) } else { Image(systemName: "arrow.up") }
                                    }
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Brand.electric, in: .circle)   // camın üstünde dolgu, ikinci cam değil
                                }
                                .disabled(sending)
                                .accessibilityLabel(sending ? "Gönderiliyor" : "Gönder")
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .glassEffectID("field", in: composerNS)
                }
            }
        }
        .animation(reduceMotion ? .smooth : .snappy, value: canSend)
        .animation(reduceMotion ? .smooth : .snappy, value: attachment)
    }

    private func attachmentChip(_ attachment: Attachment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill").foregroundStyle(Brand.electric)
            Text(attachment.name).lineLimit(1)
            Text(Double(attachment.data.count).byteText).foregroundStyle(.white.opacity(0.85))
            Button {
                self.attachment = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eki kaldır")
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.12), in: .capsule)   // camın üstünde dolgu
        .padding(.top, 6)
    }

    // MARK: Akış

    private enum Row: Identifiable {
        case day(Date, String)
        case push(Push)
        var id: String {
            switch self {
            case .day(_, let key): "day-\(key)"
            case .push(let push): push.id
            }
        }
    }

    private var visiblePushes: [Push] {
        store.pushes.filter { push in
            switch filter {
            case .all: true
            case .pinned: push.pinned
            case .device(let id): push.source == id || push.target == id
            }
        }
    }

    private var rows: [Row] {
        var result: [Row] = []
        var lastDay: DateComponents?
        for push in visiblePushes {
            let day = Calendar.current.dateComponents([.year, .month, .day], from: push.date)
            if day != lastDay {
                result.append(.day(push.date, "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"))
                lastDay = day
            }
            result.append(.push(push))
        }
        return result
    }

    private func bubble(for push: Push) -> some View {
        let mine = push.source == store.deviceId
        let route = "\(store.deviceName(for: push.source)) → \(push.target.isEmpty ? "tümü" : store.deviceName(for: push.target))"
        return PushBubble(push: push, isMine: mine, route: route)
            .contentShape(Rectangle())
            .onTapGesture { open(push) }
            .contextMenu {
                if push.type != .note {
                    Button(push.type == .file ? "Dosyayı aç" : "Linki aç", systemImage: "arrow.up.right.square") { open(push) }
                }
                Button("Kopyala", systemImage: "doc.on.doc") { UIPasteboard.general.string = push.copyText }
                Button(push.pinned ? "Sabitlemeyi kaldır" : "Sabitle", systemImage: push.pinned ? "pin.slash" : "pin") {
                    Task { await store.togglePin(push) }
                }
                Button("Sil", systemImage: "trash", role: .destructive) {
                    Task { await store.delete(push) }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(push.type == .note ? "Seçenekler için basılı tut" : "Açmak için dokun, seçenekler için basılı tut")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(store.pushes.isEmpty ? "İlk pushunu gönder" : "Burada push yok")
                .font(.title3.weight(.heavy))
            Text(store.pushes.isEmpty
                 ? "Aşağıya bir not ya da link yaz, istersen fotoğraf veya dosya ekle. Diğer cihazlarına anında gider."
                 : "Başka bir cihaz seç.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Brand.meta)
        }
        .padding(.horizontal, 24)
        .padding(.top, 120)
    }

    // MARK: Eylemler

    private var canSend: Bool {
        attachment != nil || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var targetName: String {
        target.isEmpty ? "Tüm cihazlarım" : store.deviceName(for: target)
    }

    private func send() async {
        guard canSend, !sending else { return }
        sending = true
        let ok = await store.send(text: draft, attachment: attachment, target: target)
        if ok {
            draft = ""
            attachment = nil
        }
        sending = false
    }

    private func open(_ push: Push) {
        guard push.type != .note, let url = URL(string: push.url) else { return }
        openURL(url)
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}
