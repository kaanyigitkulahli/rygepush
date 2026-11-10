import BackgroundTasks
import SwiftUI
import UserNotifications
#if canImport(FirebaseCore) && canImport(FirebaseMessaging)
import FirebaseCore
import FirebaseMessaging
#endif

@main
struct RygePushApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let store = PushStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Brand.electric)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.start()
            case .background:
                store.stop()
                BackgroundRefresh.schedule()
            default:
                store.stop()
            }
        }
        // iOS uygulamayı arka planda ara sıra uyandırır: yeni push varsa yerel bildirim gösterilir.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.schedule()
            await PushStore.shared.checkForNewPushesInBackground()
        }
    }
}

enum BackgroundRefresh {
    static let identifier = "rygepush.yenile"

    /// En erken 15 dakika sonra bir yenileme ister. Ne zaman çalışacağına iOS karar verir.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Bildirim izni ve (varsa) Firebase ile uzaktan bildirim kaydı.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        var remotePush = false
        #if canImport(FirebaseCore) && canImport(FirebaseMessaging)
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            Messaging.messaging().delegate = self
            remotePush = true
        }
        #endif
        let usesRemotePush = remotePush

        Task { @MainActor in
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                if !granted {
                    PushStore.shared.setNotificationStatus("Bildirim izni yok. Ayarlar > RygePush > Bildirimler'den açabilirsin.")
                } else if usesRemotePush {
                    UIApplication.shared.registerForRemoteNotifications()
                    PushStore.shared.setNotificationStatus("Anlık bildirimler açılıyor")
                } else {
                    PushStore.shared.setNotificationStatus("Arka planda kontrol (gecikmeli)")
                }
            } catch {
                PushStore.shared.setNotificationStatus("Bildirim izni istenemedi")
            }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        #endif
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushStore.shared.setNotificationStatus("Anlık bildirim kaydı başarısız, arka planda kontrol ediliyor")
        }
    }

    // Uygulama açıkken gelen bildirimi de göster ve akışı yenile.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Task { @MainActor in await PushStore.shared.sync() }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        Task { @MainActor in await PushStore.shared.sync() }
    }
}

#if canImport(FirebaseMessaging)
extension AppDelegate: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            PushStore.shared.pushToken = fcmToken
            PushStore.shared.setNotificationStatus("Anlık bildirimler açık")
        }
    }
}
#endif
