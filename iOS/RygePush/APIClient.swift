import Foundation

struct APIError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

/// Google Apps Script sunucusuyla konuşur. Her istek, erişim anahtarıyla birlikte JSON POST'tur.
/// Apps Script yanıtı bir yönlendirmeyle döndürür; URLSession bunu kendisi takip eder.
struct APIClient: Sendable {
    let baseURL: URL
    let key: String

    struct SyncResponse: Decodable, Sendable {
        let ok: Bool
        let error: String?
        let pushes: [Push]?
        let devices: [Device]?
    }

    struct UploadStartResponse: Decodable, Sendable {
        let ok: Bool
        let error: String?
        let uploadUrl: String?
    }

    struct BasicResponse: Decodable, Sendable {
        let ok: Bool
        let error: String?
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func sync(deviceId: String) async throws -> SyncResponse {
        try await call(["action": "sync", "deviceId": deviceId], as: SyncResponse.self)
    }

    /// Drive'da devam ettirilebilir yükleme oturumu açar; dosya bu adrese doğrudan gönderilir.
    func startUpload(name: String, mime: String, size: Int64) async throws -> URL {
        let response = try await call(["action": "uploadStart", "name": name, "mime": mime, "size": size],
                                      as: UploadStartResponse.self)
        guard let raw = response.uploadUrl, let url = URL(string: raw) else {
            throw APIError(message: "Yükleme başlatılamadı.")
        }
        return url
    }

    @discardableResult
    func send(_ fields: [String: any Sendable]) async throws -> BasicResponse {
        try await call(fields, as: BasicResponse.self)
    }

    private func call<T: Decodable & Sendable>(_ fields: [String: any Sendable], as type: T.Type) async throws -> T {
        var body: [String: Any] = ["key": key]
        for (k, v) in fields { body[k] = v }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            (data, _) = try await Self.session.data(for: request)
        } catch {
            throw APIError(message: "Sunucuya ulaşılamadı. İnternet bağlantını kontrol et.")
        }

        if let basic = try? JSONDecoder().decode(BasicResponse.self, from: data), !basic.ok {
            throw APIError(message: basic.error ?? "İstek başarısız oldu.")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(message: "Sunucu yanıtı okunamadı. Sunucu adresinin /exec ile bittiğinden emin ol.")
        }
    }
}
