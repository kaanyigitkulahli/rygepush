import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// Gönderme paneli: hedef cihaz ve ek seçimi.
// Sistem sayfası zaten cam; içine glassEffect eklenmez. Satırlar liste (content layer).
struct SendOptionsSheet: View {
    @Environment(PushStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Binding var target: String
    @Binding var attachment: Attachment?
    @Binding var draft: String

    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var loading = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Kime gönderilsin?") {
                    targetRow(title: "Tüm cihazlarım",
                              subtitle: "\(store.otherDevices.count) cihaza gider",
                              device: nil, id: "")
                    ForEach(store.otherDevices) { device in
                        targetRow(title: device.name, subtitle: device.lastSeenText, device: device, id: device.id)
                    }
                }

                Section {
                    PhotosPicker(selection: $photoItem, matching: .any(of: [.images, .videos])) {
                        Label("Fotoğraf ya da video", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Dosya", systemImage: "doc")
                    }
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Panodan yapıştır", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Ekle")
                } footer: {
                    if loading {
                        Text("Hazırlanıyor…")
                    } else if let problem {
                        Text(problem).foregroundStyle(.red)
                    } else if let attachment {
                        Text("Ekli: \(attachment.name) · \(Double(attachment.data.count).byteText)")
                    } else {
                        Text("En fazla 20 MB. Link yapıştırırsan link olarak gider.")
                    }
                }
            }
            .navigationTitle("Gönder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url): loadFile(url)
                case .failure: problem = "Dosya açılamadı."
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func targetRow(title: String, subtitle: String, device: Device?, id: String) -> some View {
        Button {
            target = id
        } label: {
            HStack(spacing: 12) {
                DeviceIcon(device: device, highlighted: target == id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if target == id {
                    Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(Brand.electric)
                }
            }
        }
        .accessibilityAddTraits(target == id ? .isSelected : [])
    }

    private func accept(name: String, mime: String, data: Data) {
        guard data.count <= Attachment.maxBytes else {
            problem = "Dosya en fazla 20 MB olabilir."
            return
        }
        problem = nil
        attachment = Attachment(name: name, mime: mime, data: data)
        dismiss()
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        loading = true
        defer { loading = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                problem = "Fotoğraf okunamadı."
                return
            }
            let type = item.supportedContentTypes.first ?? .jpeg
            let ext = type.preferredFilenameExtension ?? "jpg"
            let stamp = Int(Date().timeIntervalSince1970)
            accept(name: "foto-\(stamp).\(ext)", mime: type.preferredMIMEType ?? "image/jpeg", data: data)
        } catch {
            problem = "Fotoğraf okunamadı."
        }
    }

    private func loadFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            problem = "Dosya okunamadı."
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        accept(name: url.lastPathComponent, mime: mime, data: data)
    }

    private func pasteFromClipboard() {
        let board = UIPasteboard.general
        if let image = board.image, let data = image.pngData() {
            accept(name: "pano-\(Int(Date().timeIntervalSince1970)).png", mime: "image/png", data: data)
        } else if let text = board.string, !text.isEmpty {
            draft = text
            dismiss()
        } else {
            problem = "Panoda gönderilecek bir şey yok."
        }
    }
}
