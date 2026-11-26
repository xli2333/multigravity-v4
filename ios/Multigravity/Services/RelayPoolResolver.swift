import Foundation
import os

/// Stateless mobile auto-discovery for multi-VPS relay pools.
/// When a paired gateway fails over or migrates to a newly added VPS node in `RELAY_POOL`,
/// the client queries the public read-only pool manifest (`GET /api/relay/pool`), expands
/// the user's deterministic subdomain ID (`r-{sid}.*`), and concurrently probes `/healthz`
/// to re-lock onto the active VPS with zero app updates or user intervention.
public final class RelayPoolResolver: Sendable {
    public static let shared = RelayPoolResolver()

    public struct PoolNode: Decodable, Sendable {
        public let id: String
        public let region: String
        public let priority: Int?
        public let host_template: String
    }

    private struct CacheState {
        var nodes: [PoolNode] = []
        var fetchedAt: Date = .distantPast
        var trustedSuffixes: Set<String> = []
    }

    private let cacheLock = OSAllocatedUnfairLock(initialState: CacheState())
    private let inFlightResolveLock = OSAllocatedUnfairLock<[String: Task<String?, Never>]>(initialState: [:])

    private init() {}

    /// Extracts the deterministic 8-hex machine subdomain ID (`sid`) from a cloud URL,
    /// supporting both relay (`https://r-a1b2c3d4.jiuge.space`) and legacy CF (`https://a1b2c3d4.jiuge.space`).
    public static func extractSID(from cloudURL: String?) -> String? {
        guard let raw = cloudURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              let host = url.host?.lowercased(),
              let firstLabel = host.split(separator: ".").first.map(String.init) else {
            return nil
        }
        let candidate = firstLabel.hasPrefix("r-") ? String(firstLabel.dropFirst(2)) : firstLabel
        guard candidate.count >= 6, candidate.count <= 16,
              candidate.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return candidate
    }

    /// Returns true if `host` belongs to a domain suffix published by the official relay pool manifest.
    public func isPoolDomainHost(_ host: String) -> Bool {
        let clean = NetworkTransport.extractHost(from: host)
        guard !clean.isEmpty else { return false }
        let suffixes = cacheLock.withLock { $0.trustedSuffixes }
        return suffixes.contains { clean.hasSuffix($0) }
    }

    /// Self-hosted mode: third-party relay pool discovery (`dispatcher.jiuge.space`) is disabled
    /// so zero network traffic ever leaves the user's own Cloudflare / LAN endpoints.
    public func fetchPoolNodes(forceRefresh: Bool = false) async -> [PoolNode] {
        return []
    }

    /// Discovers which VPS node in `RELAY_POOL` currently serves this paired gateway.
    /// Concurrent callers for the same failed URL share one in-flight probe (single-flight).
    /// Returns the lowest-latency reachable HTTPS base URL, or nil if no pool node is online.
    public func resolveReachableCloudURL(currentCloudURL: String?) async -> String? {
        guard E2EECrypto.shared.isReady,
              Self.extractSID(from: currentCloudURL) != nil else {
            return nil
        }
        let key = (currentCloudURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        let task: Task<String?, Never> = inFlightResolveLock.withLock { map in
            if let existing = map[key] {
                return existing
            }
            let created = Task<String?, Never> { [self] in
                await self.performResolveReachableCloudURL(currentCloudURL: currentCloudURL)
            }
            map[key] = created
            return created
        }

        let result = await task.value
        inFlightResolveLock.withLock { map in
            if map[key] == task {
                map.removeValue(forKey: key)
            }
        }
        return result
    }

    /// Discovers an active peer VPS relay node when `failedURL` returns HTTP 502/503 (`gateway_offline`),
    /// updates `AppSettings` active/primary cloud URLs, and returns the new base URL if migration succeeded.
    public func migrateRelayHostIfNeeded(failedURL: URL) async -> URL? {
        guard let scheme = failedURL.scheme?.lowercased(), scheme == "https",
              let failedHost = failedURL.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased(),
              !failedHost.isEmpty,
              !NetworkTransport.isLocalOrPrivateHost(failedHost) else {
            return nil
        }
        let portSuffix: String
        if let port = failedURL.port, port != 443 {
            portSuffix = ":\(port)"
        } else {
            portSuffix = ""
        }
        let failedOrigin = "https://\(failedHost)\(portSuffix)"
        guard let migratedStr = await resolveReachableCloudURL(currentCloudURL: failedOrigin),
              let migratedURL = URL(string: migratedStr),
              let migratedHost = migratedURL.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased(),
              !migratedHost.isEmpty,
              migratedHost != failedHost else {
            return nil
        }

        E2EECrypto.shared.markHostRequiresE2EE(migratedHost)
        await MainActor.run {
            let settings = AppSettings.shared
            let oldActive = settings.activeServerURL?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let cleanMigrated = migratedStr.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            settings.primaryCloudURL = cleanMigrated
            settings.activeServerURL = cleanMigrated
            settings.syncWidgetConfiguration(reloadWidget: false)
            if oldActive != cleanMigrated {
                NotificationCenter.default.post(name: .networkRoutingPreferenceChanged, object: nil)
            }
        }
        return migratedURL
    }

    private func performResolveReachableCloudURL(currentCloudURL: String?) async -> String? {
        guard E2EECrypto.shared.isReady,
              let sid = Self.extractSID(from: currentCloudURL) else {
            return nil
        }
        let currentClean = currentCloudURL?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        let nodes = await fetchPoolNodes(forceRefresh: true)
        guard !nodes.isEmpty else { return nil }

        var candidateURLs: [String] = []
        var seen = Set<String>()
        for node in nodes {
            let host = node.host_template
                .replacingOccurrences(of: "{sid}", with: sid)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !host.isEmpty, host.contains(".") else { continue }
            let urlStr = "https://\(host)"
            if urlStr == currentClean { continue }
            if seen.insert(urlStr).inserted {
                candidateURLs.append(urlStr)
            }
        }
        guard !candidateURLs.isEmpty else { return nil }

        var statuses: [EndpointHealthStatus] = []
        await withTaskGroup(of: EndpointHealthStatus.self) { group in
            for cand in candidateURLs {
                group.addTask {
                    await ConnectionManager.testSingleEndpoint(urlString: cand)
                }
            }
            for await status in group {
                statuses.append(status)
            }
        }

        let best = statuses
            .filter { $0.isReachable }
            .min(by: { $0.latencyMs < $1.latencyMs })
        if let best {
            if let host = URL(string: best.urlString)?.host {
                E2EECrypto.shared.markHostRequiresE2EE(host)
            }
            return best.urlString
        }
        return nil
    }
}
