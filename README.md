# RygePush

Pushbullet benzeri, cihazlar arasında not, link ve dosya gönderen iPhone uygulaması (SwiftUI, iOS 26+ Liquid Glass).

- `iOS/` — uygulama kaynağı; Xcode projesi `iOS/project.yml` dosyasından XcodeGen ile üretilir.
- `chrome-eklentisi/` — bilgisayar için Chrome eklentisi (chrome://extensions → Paketlenmemiş öğe yükle).
- `.github/workflows/testflight.yml` — GitHub'ın Mac makinesinde derler, imzalar ve TestFlight'a yükler.

Derleme için gereken altı sır (Settings → Secrets and variables → Actions): `APPLE_TEAM_ID`, `RYGE_BUNDLE_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `GOOGLE_SERVICE_INFO_PLIST`.
