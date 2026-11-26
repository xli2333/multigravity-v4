import Foundation
import SwiftUI

@main
struct MultigravityWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = WatchSessionStore.shared
    @State private var selectedRootTab: Int = 0
    @State private var deepLinkedCascadeId: String?

    var body: some Scene {
        WindowGroup {
            let palette = store.palette
            TabView(selection: $selectedRootTab) {
                WatchRadarScreen(deepLinkedCascadeId: $deepLinkedCascadeId)
                    .tag(0)

                WatchQuotaPagerScreen()
                    .tag(1)
            }
            .tabViewStyle(.page)
            .preferredColorScheme(palette.isDark ? .dark : .light)
            .tint(palette.geminiFill)
            .overlay(alignment: .top) {
                if let banner = store.statusBannerMessage {
                    Text(banner)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primaryFg)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(palette.cardBg)
                                .shadow(color: Color.black.opacity(palette.isDark ? 0.45 : 0.12), radius: 6, x: 0, y: 2)
                        )
                        .overlay(
                            Capsule()
                                .stroke(palette.cardBorder, lineWidth: 1)
                        )
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.statusBannerMessage)
            .onAppear {
                store.isForegroundActive = true
                store.activate()
            }
            .onChange(of: scenePhase) { _, newPhase in
                store.isForegroundActive = (newPhase == .active)
                if newPhase == .active {
                    store.activate()
                    Task {
                        await store.refreshSnapshot()
                    }
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let host = (url.host ?? "").lowercased()
        if host == "quota" || path.hasSuffix("quota") {
            selectedRootTab = 1
            return
        }
        if host == "cascade", !path.isEmpty {
            selectedRootTab = 0
            deepLinkedCascadeId = path
            return
        }
        if path.hasPrefix("cascade/") {
            let cid = String(path.dropFirst("cascade/".count))
            if !cid.isEmpty {
                selectedRootTab = 0
                deepLinkedCascadeId = cid
            }
        }
    }
}
