import Foundation
import Observation
import Security
import UIKit
import UserNotifications

/// Uygulamanın tüm durumu: ayarlar, pushlar, cihazlar ve sunucuyla eşitleme.
@MainActor
@Observable
final class PushStore {
    static let shared = PushStore()

    enum Status: Equatable { case connecting, live, offline }

    // Ayarlar
    private(set) var serverURL: String
    private(set) var accessKey: String
    private(set) var deviceName: String
    let deviceId: String

    // Veri
    private(set) var pushes: [Push] = []
    private(set) var devices: [Device] = []
    private(set) var status: Status = .connecting
    var errorMessage: String?
    private(set) var notificationStatus = "Bildirim izni bekleniyor"

    /// Firebase'in verdiği bildirim kodu. Gelince sunucuya kaydedilir.
    var pushToken: String? {
        didSet {
            guard pushToken != oldValue else { return }
            defaults.set(pushToken != nil, forKey: "remotePushActive")
            Task { await register() }
        }
    }

    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    var isConfigured: Bool { client != nil }

    private var client: APIClient? {
        guard let url = URL(string: serverURL), !accessKey.isEmpty, serverURL.hasSuffix("/exec") else { return nil }
        return APIClient(baseURL: url, key: accessKey)
    }

    private init() {
        let store = UserDefaults.standard
        serverURL = store.string(forKey: "serverURL") ?? ""
        accessKey = Keychain.read("accessKey") ?? ""
        deviceName = store.string(forKey: "deviceName") ?? UIDevice.current.name
        if let id = store.string(forKey: "deviceId") {
            deviceId = id
        } else {
            let id = "i" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20).lowercased()
            store.set(id, forKey: "deviceId")
            deviceId = id
        }
        loadCache()
    }

    // MARK: Ayarlar

    /// Önce bilgileri dener; sunucu kabul ederse kaydeder.
    func configure(serverURL: String, key: String, name: String) async {
        let cleanURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanURL) else {
            errorMessage = "Sunucu adresi geçersiz."
            return
        }
        do {
            _ = try await APIClient(baseURL: url, key: cleanKey).sync(deviceId: deviceId)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        self.serverURL = cleanURL
        self.accessKey = cleanKey
        self.deviceName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(self.serverURL, forKey: "serverURL")
        defaults.set(self.deviceName, forKey: "deviceName")
        Keychain.write("accessKey", value: self.accessKey)
        await register()
        await sync()
        start()
    }

    func rename(to name: String) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let client else { return }
        deviceName = clean
        defaults.set(clean, forKey: "deviceName")
        do {
            try await client.send(["action": "rename", "deviceId": deviceId, "name": clean])
            await sync()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Bu cihazı sunucudan kaldırır ve ayarları siler.
    func disconnect() async {
        if let client {
            try? await client.send(["action": "removeDevice", "deviceId": deviceId])
        }
        syncTask?.cancel()
        serverURL = ""
        accessKey = ""
        pushes = []
        devices = []
        defaults.removeObject(forKey: "serverURL")
        Keychain.delete("accessKey")
        try? FileManager.default.removeItem(at: cacheURL)
    }

    func setNotificationStatus(_ text: String) { notificationStatus = text }

    // MARK: Eşitleme

    /// Uygulama öndeyken birkaç saniyede bir yeniler. Bildirim gelince de hemen yenilenir.
    func start() {
        syncTask?.cancel()
        guard isConfigured else { return }
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        syncTask?.cancel()
        syncTask = nil
    }

    func register() async {
        guard let client else { return }
        do {
            try await client.send([
                "action": "register", "deviceId": deviceId, "name": deviceName,
                "kind": "ios", "pushToken": pushToken ?? "",
            ])
        } catch { errorMessage = error.localizedDescription }
    }

    func sync() async {
        guard let client else { return }
        do {
            let response = try await client.sync(deviceId: deviceId)
            let newPushes = response.pushes ?? []
            let newDevices = response.devices ?? []
            if newPushes != pushes { pushes = newPushes }
            if newDevices != devices { devices = newDevices }
            status = .live
            saveCache()
            // Ekrandayken gelenleri görülmüş say; arka planda tekrar bildirilmesinler.
            if UIApplication.shared.applicationState == .active { markAllSeen() }
        } catch {
            status = .offline
        }
    }

    // MARK: Arka plan kontrolü (ücretsiz hesap: uzaktan bildirim yerine)

    private var lastSeenCreatedAt: Double {
        get { defaults.double(forKey: "lastSeenCreatedAt") }
        set { defaults.set(newValue, forKey: "lastSeenCreatedAt") }
    }

    private func markAllSeen() {
        let newest = pushes.map(\.createdAt).max() ?? 0
        if newest > lastSeenCreatedAt { lastSeenCreatedAt = newest }
    }

    /// iOS uygulamayı arka planda uyandırınca çağrılır. Bu cihaza gelen yeni pushlar için yerel bildirim gösterir.
    func checkForNewPushesInBackground() async {
        guard let client, let response = try? await client.sync(deviceId: deviceId) else { return }
        pushes = response.pushes ?? pushes
        devices = response.devices ?? devices
        saveCache()

        let since = lastSeenCreatedAt
        let fresh = pushes.filter { push in
            push.createdAt > since && push.source != deviceId && (push.target.isEmpty || push.target == deviceId)
        }
        guard !fresh.isEmpty else { return }
        markAllSeen()
        // Anlık bildirim (Firebase) açıksa bu pushlar zaten bildirildi; ikinci kez gösterme.
        guard !defaults.bool(forKey: "remotePushActive") else { return }

        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        for push in fresh.suffix(5) {
            let content = UNMutableNotificationContent()
            let kind = switch push.type {
            case .note: push.title.isEmpty ? "Not" : push.title
            case .link: push.title.isEmpty ? "Link" : push.title
            case .file: push.title.isEmpty ? "Dosya" : push.title
            }
            content.title = "\(deviceName(for: push.source)) · \(kind)"
            content.body = switch push.type {
            case .note: push.body
            case .link: push.body.isEmpty ? push.url : push.body
            case .file: push.body.isEmpty ? push.fileName : push.body
            }
            content.sound = .default
            content.threadIdentifier = "rygepush"
            try? await center.add(UNNotificationRequest(identifier: push.id, content: content, trigger: nil))
        }
    }

    // MARK: Eylemler

    /// Metin bir linkse link, ek varsa dosya, yoksa not olarak gönderir.
    func send(text: String, attachment: Attachment?, target: String) async -> Bool {
        guard let client else { return false }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: any Sendable] = ["action": "push", "source": deviceId, "target": target]

        if let attachment {
            fields["type"] = "file"
            fields["body"] = clean
            fields["file"] = [
                "name": attachment.name,
                "mime": attachment.mime,
                "base64": attachment.data.base64EncodedString(),
            ]
        } else if Self.isLink(clean) {
            fields["type"] = "link"
            fields["url"] = clean
        } else {
            guard !clean.isEmpty else { return false }
            fields["type"] = "note"
            fields["body"] = clean
        }

        do {
            try await client.send(fields)
            await sync()
            return true
        } catch {
            errorMessage = "Gönderilemedi. \(error.localizedDescription)"
            return false
        }
    }

    func togglePin(_ push: Push) async {
        guard let client, let index = pushes.firstIndex(where: { $0.id == push.id }) else { return }
        pushes[index].pinned.toggle()
        do {
            try await client.send(["action": "pin", "id": push.id, "pinned": pushes[index].pinned])
        } catch {
            errorMessage = "Kaydedilemedi. \(error.localizedDescription)"
            await sync()
        }
    }

    func delete(_ push: Push) async {
        guard let client else { return }
        pushes.removeAll { $0.id == push.id }
        do {
            try await client.send(["action": "delete", "id": push.id])
        } catch {
            errorMessage = "Silinemedi. \(error.localizedDescription)"
            await sync()
        }
    }

    // MARK: Yardımcılar

    func deviceName(for id: String) -> String {
        if id == deviceId { return "Bu iPhone" }
        return devices.first { $0.id == id }?.name ?? "Silinmiş cihaz"
    }

    var otherDevices: [Device] { devices.filter { $0.id != deviceId } }

    static func isLink(_ text: String) -> Bool {
        guard !text.contains(" "), !text.contains("\n"),
              let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private var cacheURL: URL {
        URL.cachesDirectory.appending(path: "rygepush-cache.json")
    }

    private struct Cache: Codable { var pushes: [Push]; var devices: [Device] }

    private func saveCache() {
        let snapshot = Cache(pushes: pushes, devices: devices)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: cacheURL, options: .atomic) }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        pushes = cache.pushes
        devices = cache.devices
    }
}

/// Erişim anahtarını Anahtar Zinciri'nde tutar.
enum Keychain {
    private static let service = "RygePush"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, value: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
