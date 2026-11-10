import Foundation

/// Dosyayı Google Drive'ın devam ettirilebilir yükleme adresine parça parça gönderir.
/// Dosya hiçbir zaman tamamen belleğe alınmaz; 16 MB'lık parçalar diskten okunur.
/// Bağlantı koparsa Drive'a kaç bayt aldığı sorulur ve oradan devam edilir.
enum ResumableUploader {
    static let chunkSize = 16 * 1024 * 1024   // 256 KB'nin katı olmalı

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60 * 6
        return URLSession(configuration: config)
    }()

    private struct DriveFile: Decodable { let id: String }

    /// Yüklemeyi bitirir ve Drive dosya kimliğini döndürür.
    static func upload(fileURL: URL, size: Int64, to uploadURL: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var offset: Int64 = 0
        var failures = 0

        while true {
            try Task.checkCancellation()
            do {
                try handle.seek(toOffset: UInt64(offset))
                let chunk = try handle.read(upToCount: chunkSize) ?? Data()
                let end = offset + Int64(chunk.count) - 1

                var request = URLRequest(url: uploadURL)
                request.httpMethod = "PUT"
                request.setValue("bytes \(offset)-\(end)/\(size)", forHTTPHeaderField: "Content-Range")
                let (data, response) = try await session.upload(for: request, from: chunk)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0

                if status == 200 || status == 201 {
                    progress(1)
                    return try JSONDecoder().decode(DriveFile.self, from: data).id
                }
                guard status == 308 else { throw APIError(message: "Drive yüklemeyi kabul etmedi (\(status)).") }
                offset = receivedBytes(response) ?? (end + 1)
                failures = 0
                progress(Double(offset) / Double(size))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures += 1
                if failures > 5 {
                    throw APIError(message: "Yükleme yarıda kaldı. İnternet bağlantını kontrol edip tekrar dene.")
                }
                try await Task.sleep(for: .seconds(Double(failures) * 1.5))
                if let resumed = try? await status(of: uploadURL, size: size) {
                    switch resumed {
                    case .finished(let id): progress(1); return id
                    case .received(let bytes): offset = bytes
                    }
                }
            }
        }
    }

    private enum UploadState { case finished(String), received(Int64) }

    /// Drive'a kaç bayt ulaştığını sorar (boş PUT, Content-Range: bytes */boyut).
    private static func status(of uploadURL: URL, size: Int64) async throws -> UploadState {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("bytes */\(size)", forHTTPHeaderField: "Content-Range")
        let (data, response) = try await session.upload(for: request, from: Data())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 || status == 201 {
            return .finished(try JSONDecoder().decode(DriveFile.self, from: data).id)
        }
        return .received(receivedBytes(response) ?? 0)
    }

    /// 308 yanıtındaki "Range: bytes=0-N" başlığından alınan bayt sayısını çıkarır.
    private static func receivedBytes(_ response: URLResponse) -> Int64? {
        guard let range = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Range"),
              let last = range.split(separator: "-").last, let n = Int64(last) else { return nil }
        return n + 1
    }
}
