import Foundation
import SwiftUI

/// Sunucudaki bir push: not, link ya da dosya.
struct Push: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case note, link, file }

    let id: String
    let createdAt: Double
    let type: Kind
    var title: String
    var body: String
    var url: String
    var fileId: String
    var fileName: String
    var fileMime: String
    var fileSize: Double
    var source: String
    var target: String
    var pinned: Bool

    var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }

    /// Kopyalanınca panoya giden metin.
    var copyText: String {
        switch type {
        case .note: [title, body].filter { !$0.isEmpty }.joined(separator: "\n")
        case .link, .file: url
        }
    }

    var fileExtension: String {
        let ext = (fileName as NSString).pathExtension
        return ext.isEmpty ? "DOSYA" : String(ext.prefix(4)).uppercased()
    }
}

/// Aynı erişim anahtarıyla bağlı cihaz.
struct Device: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var kind: String
    var lastSeen: Double

    var isPhone: Bool { kind == "ios" }

    var lastSeenText: String {
        guard lastSeen > 0 else { return "henüz görülmedi" }
        let minutes = Int(Date().timeIntervalSince1970 - lastSeen / 1000) / 60
        if minutes < 2 { return "şimdi çevrimiçi" }
        if minutes < 60 { return "\(minutes) dk önce" }
        if minutes < 60 * 24 { return "\(minutes / 60) sa önce" }
        return "\(minutes / (60 * 24)) gün önce"
    }

    var isOnline: Bool { lastSeen > 0 && Date().timeIntervalSince1970 - lastSeen / 1000 < 120 }
}

/// Gönderilmeyi bekleyen ek. Dosya belleğe alınmaz; yükleme sırasında diskten parça parça okunur.
struct Attachment: Equatable, Sendable {
    var name: String
    var mime: String
    var size: Int64
    var fileURL: URL
    /// Dosyalar uygulamasından seçilen dosyalara erişim izni yükleme sırasında açılır.
    var securityScoped: Bool

    static let maxBytes: Int64 = 5 * 1024 * 1024 * 1024
}

enum FeedFilter: Hashable {
    case all
    case pinned
    case device(String)
}

/// Marka renkleri: logodaki gece mavisi zemin ve elektrik mavisi ışıltı.
enum Brand {
    static let ink = Color(red: 0.008, green: 0.012, blue: 0.043)          // #02030B
    static let electric = Color(red: 0.122, green: 0.420, blue: 1.0)        // #1F6BFF
    static let bubbleMine = Color(red: 0.102, green: 0.361, blue: 1.0)      // #1A5CFF
    static let bubbleOther = Color(red: 0.071, green: 0.110, blue: 0.251)   // #121C40
    static let bubbleStroke = Color(red: 0.47, green: 0.63, blue: 1.0).opacity(0.22)
    static let meta = Color(red: 0.66, green: 0.76, blue: 1.0)              // #A9C3FF
    static let online = Color(red: 0.24, green: 0.86, blue: 0.59)
    static let pin = Color(red: 1.0, green: 0.79, blue: 0.30)
}

extension Double {
    var byteText: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
