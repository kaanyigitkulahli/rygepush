import SwiftUI

// Cihazlar ve ayarlar. Gezinme çubuğu sistem camı; liste satırları content layer.
struct DevicesView: View {
    @Environment(PushStore.self) private var store
    @State private var name = ""
    @State private var confirmDisconnect = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image("Logo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .shadow(color: Brand.electric.opacity(0.55), radius: 16)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(store.devices.count) cihaz bağlı").font(.headline)
                        Text("Aynı erişim anahtarını kullanan tüm cihazlar").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section("Cihazlar") {
                ForEach(store.devices) { device in
                    HStack(spacing: 12) {
                        DeviceIcon(device: device, highlighted: device.id == store.deviceId)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.id == store.deviceId ? "\(device.name) (bu cihaz)" : device.name)
                                .font(.body.weight(.semibold))
                            HStack(spacing: 5) {
                                if device.isOnline {
                                    Circle().fill(Brand.online).frame(width: 7, height: 7).accessibilityHidden(true)
                                }
                                Text(device.lastSeenText)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section("Bu cihazın adı") {
                TextField("Cihaz adı", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { Task { await store.rename(to: name) } }
                if name.trimmingCharacters(in: .whitespaces) != store.deviceName {
                    Button("Adı kaydet") { Task { await store.rename(to: name) } }
                }
            }

            Section("Durum") {
                LabeledContent("Bildirimler", value: store.notificationStatus)
                LabeledContent("Sunucu") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(store.status == .live ? Brand.online : .red)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(store.status == .live ? "Bağlı" : "Bağlantı yok")
                    }
                }
                LabeledContent("Dosya sınırı", value: "20 MB")
            }

            Section {
                Button("Bu cihazın bağlantısını kes", role: .destructive) { confirmDisconnect = true }
                    .confirmationDialog("Bu iPhone sunucudan kaldırılsın mı?", isPresented: $confirmDisconnect,
                                        titleVisibility: .visible) {
                        Button("Bağlantıyı kes", role: .destructive) { Task { await store.disconnect() } }
                    } message: {
                        Text("Pushların silinmez. Tekrar bağlanmak için sunucu adresini ve erişim anahtarını yeniden girmen gerekir.")
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .background { BrandBackground() }
        .navigationTitle("Cihazlar")
        .onAppear { name = store.deviceName }
        .refreshable { await store.sync() }
    }
}
