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
                        Text("Ekli: \(attachment.name) · \(Double(attachment.size).byteText)")
                    } else {
                        Text("En fazla 100 GB. Büyük dosyalar yüklenirken uygulamayı açık ve ekranda tut; 100 GB ev internetinde saatler sürebilir. Link yapıştırırsan link olarak gider.")
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

    private func accept(name: String, mime: String, fileURL: URL, securityScoped: Bool) {
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size > 0 else {
            problem = "Dosya boş ya da okunamadı."
            return
        }
        guard size <= Attachment.maxBytes else {
            problem = "Dosya en fazla 100 GB olabilir."
            if !securityScoped { try? FileManager.default.removeItem(at: fileURL) }
            return
        }
        problem = nil
        attachment = Attachment(name: name, mime: mime, size: size, fileURL: fileURL, securityScoped: securityScoped)
        dismiss()
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        loading = true
        defer { loading = false; photoItem = nil }
        do {
            // Fotoğraf ya da video belleğe alınmadan geçici bir dosyaya kopyalanır.
            guard let picked = try await item.loadTransferable(type: PickedMedia.self) else {
                problem = "Fotoğraf okunamadı."
                return
            }
            let type = UTType(filenameExtension: picked.url.pathExtension) ?? item.supportedContentTypes.first ?? .data
            accept(name: picked.url.lastPathComponent, mime: type.preferredMIMEType ?? "application/octet-stream",
                   fileURL: picked.url, securityScoped: false)
        } catch {
            problem = "Fotoğraf okunamadı."
        }
    }

    private func loadFile(_ url: URL) {
        // Dosyalar uygulamasındaki dosya yerinde kalır; yükleme sırasında doğrudan oradan okunur.
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        accept(name: url.lastPathComponent, mime: mime, fileURL: url, securityScoped: true)
    }

    private func pasteFromClipboard() {
        let board = UIPasteboard.general
        if let image = board.image, let data = image.pngData() {
            let url = URL.temporaryDirectory.appending(path: "pano-\(Int(Date().timeIntervalSince1970)).png")
            do {
                try data.write(to: url)
                accept(name: url.lastPathComponent, mime: "image/png", fileURL: url, securityScoped: false)
            } catch {
                problem = "Panodaki resim kaydedilemedi."
            }
        } else if let text = board.string, !text.isEmpty {
            draft = text
            dismiss()
        } else {
            problem = "Panoda gönderilecek bir şey yok."
        }
    }
}

/// Fotoğraf arşivinden seçilen öğeyi geçici bir dosya olarak alır (büyük videolar için bellek dostu).
struct PickedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .data) { received in
            let name = received.file.lastPathComponent.isEmpty ? "medya-\(Int(Date().timeIntervalSince1970))" : received.file.lastPathComponent
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appending(path: name)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMedia(url: destination)
        }
    }
}
