import SwiftUI
import UIKit

struct RootView: View {
    @Environment(PushStore.self) private var store

    var body: some View {
        if store.isConfigured {
            FeedView()
        } else {
            SetupView()
        }
    }
}

// İlk açılış: sunucuya bağlanma. Alanlar content layer; tek ana eylem glassProminent.
struct SetupView: View {
    @Environment(PushStore.self) private var store
    @State private var url = ""
    @State private var key = ""
    @State private var name = UIDevice.current.name
    @State private var connecting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image("Logo")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: Brand.electric.opacity(0.6), radius: 24)
                            .accessibilityHidden(true)
                        Text("RygePush'a hoş geldin")
                            .font(.largeTitle.weight(.heavy))
                        Text("Cihazlarının arasında not, link ve dosya gönder. Başlamak için sunucu bilgilerini gir.")
                            .font(.body)
                            .foregroundStyle(Brand.meta)
                    }
                    .padding(.bottom, 8)

                    field("Sunucu adresi", text: $url, prompt: "https://script.google.com/macros/s/…/exec", secure: false)
                    field("Erişim anahtarı", text: $key, prompt: "Code.gs içindeki ERISIM_ANAHTARI", secure: true)
                    field("Bu cihazın adı", text: $name, prompt: "iPhone", secure: false)

                    if !url.isEmpty && !urlLooksRight {
                        Text("Adres https://script.google.com/ ile başlayıp /exec ile bitmeli.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let message = store.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }

                    Button {
                        Task {
                            connecting = true
                            store.errorMessage = nil
                            await store.configure(serverURL: url, key: key, name: name)
                            connecting = false
                        }
                    } label: {
                        Group {
                            if connecting { ProgressView() } else { Text("Bağlan") }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Brand.electric)
                    .controlSize(.large)
                    .disabled(!formValid || connecting)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { BrandBackground() }
        }
    }

    private var urlLooksRight: Bool {
        let u = url.trimmingCharacters(in: .whitespaces)
        return u.hasPrefix("https://script.google.com/") && u.hasSuffix("/exec")
    }

    private var formValid: Bool {
        urlLooksRight && key.trimmingCharacters(in: .whitespaces).count > 8
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func field(_ title: String, text: Binding<String>, prompt: String, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased(with: Locale(identifier: "tr_TR")))
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(Brand.meta)
            Group {
                if secure {
                    SecureField(title, text: text, prompt: Text(prompt))
                } else {
                    TextField(title, text: text, prompt: Text(prompt))
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Brand.bubbleOther.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.bubbleStroke) }
        }
    }
}
