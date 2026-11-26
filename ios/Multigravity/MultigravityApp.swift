import SwiftUI

@main
struct MultigravityApp: App {
    @UIApplicationDelegateAdaptor(MultigravityAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = AppSettings.shared

    init() {
        let memoryCapacity = 50 * 1024 * 1024 // 50 MB
        let diskCapacity = 200 * 1024 * 1024  // 200 MB
        URLCache.shared = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: "multigravity_url_cache"
        )
    }

    var body: some Scene {
        WindowGroup {
            ConversationListView()
                .tint(AGPalette.adaptiveAccentColor)
                .onAppear {
                    settings.applyAppearance()
                    ActivityManager.shared.startRemoteTokenObservers()
                    PushNotificationManager.shared.syncAllTokensIfPaired()
                    BackgroundKeepAliveManager.shared.refreshKeepAliveState()
                    if settings.isPaired && !settings.isDemoMode && settings.enablePushNotifications {
                        Task {
                            await PushNotificationManager.shared.refreshAuthorizationStatus()
                            if PushNotificationManager.shared.authorizationStatus == .notDetermined {
                                _ = await PushNotificationManager.shared.requestAuthorizationAndRegister()
                            }
                        }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        settings.applyAppearance()
                        BackgroundKeepAliveManager.shared.refreshKeepAliveState()
                    } else if newPhase == .background {
                        settings.syncWidgetConfiguration(reloadWidget: true)
                        BackgroundKeepAliveManager.shared.refreshKeepAliveState()
                    }
                }
        }
    }
}
