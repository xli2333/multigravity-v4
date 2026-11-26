import Foundation
import os

extension APIClient {
    /// Uploads a local file to the gateway (POST /api/v1/attachments) as a raw streamed body.
    /// `onProgress` receives 0...0.95 as bytes are streamed, leaving the final 100% for the gateway's 200 OK.
    public func uploadAttachment(
        fileURL: URL,
        displayName: String,
        baseURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> UploadedAttachment {
        let endpoint = baseURL.appendingPathComponent("api/v1/attachments")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let encodedName = displayName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? displayName
        request.setValue(encodedName, forHTTPHeaderField: "X-File-Name")
        request.timeoutInterval = 120
        if let token = KeychainHelper.shared.read(key: .deviceToken), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let isDemoEndpoint = DemoGateway.isEnabled
            && endpoint.host == DemoGateway.host
            && endpoint.port == DemoGateway.port

        let data: Data
        let response: URLResponse
        if !isDemoEndpoint, E2EECrypto.shared.shouldEncrypt(url: endpoint) {
            do {
                request.httpBody = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                onProgress?(0.25)
                (data, response) = try await transport.send(request: request)
                onProgress?(0.95)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw APIError.networkError(error.localizedDescription)
            }
        } else if NetworkTransport.requiresCleartextATSBypass(endpoint) {
            // App Transport Security blocks cleartext HTTP to Tailscale hosts; stream 32 KB chunks over Network.framework.
            do {
                (data, response) = try await transport.uploadCleartextHTTP(
                    request: request,
                    fileURL: fileURL,
                    onProgress: onProgress
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw APIError.networkError(error.localizedDescription)
            }
        } else if !isDemoEndpoint,
                  endpoint.scheme?.lowercased() == "https",
                  CloudflareAnycastAccelerator.isCloudflareTunnelHost(endpoint.host ?? "") {
            // Try accelerated Anycast edge first; fall back to native URLSession file upload on transport or edge error.
            var acceleratedResult: (Data, URLResponse)? = nil
            do {
                let candidate = try await transport.uploadCloudflareAcceleratedHTTPS(
                    request: request,
                    fileURL: fileURL,
                    onProgress: onProgress
                )
                if let http = candidate.1 as? HTTPURLResponse,
                   (200...299).contains(http.statusCode) || [401, 413, 415, 426].contains(http.statusCode) {
                    acceleratedResult = candidate
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                acceleratedResult = nil
            }

            if let acceleratedResult {
                (data, response) = acceleratedResult
            } else {
                (data, response) = try await Self.uploadViaURLSession(
                    request: request,
                    fileURL: fileURL,
                    onProgress: onProgress
                )
            }
        } else {
            (data, response) = try await Self.uploadViaURLSession(
                request: request,
                fileURL: fileURL,
                onProgress: onProgress
            )
        }

        var finalData = data
        var finalResponse = response
        if !isDemoEndpoint,
           let http = finalResponse as? HTTPURLResponse,
           http.statusCode == 426,
           E2EECrypto.shared.isReady,
           let host = endpoint.host,
           !NetworkTransport.isLocalOrPrivateHost(host) {
            E2EECrypto.shared.markHostRequiresE2EE(host)
            do {
                request.httpBody = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                onProgress?(0.25)
                (finalData, finalResponse) = try await transport.send(request: request)
                onProgress?(0.95)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw APIError.networkError(error.localizedDescription)
            }
        }

        guard let http = finalResponse as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response type")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 {
                NotificationCenter.default.post(name: .deviceTokenRevoked, object: nil)
            }
            struct ErrBody: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(ErrBody.self, from: finalData))?.message
                ?? String(data: finalData, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw APIError.serverError(statusCode: http.statusCode, message: message)
        }
        do {
            return try JSONDecoder().decode(UploadedAttachment.self, from: finalData)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Streams a file directly from disk via `URLSession.upload(for:fromFile:delegate:)`,
    /// preserving automatic stream rewinding across HTTP/2, Cloudflare edges, and system VPN/proxies.
    private static func uploadViaURLSession(
        request: URLRequest,
        fileURL: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> (Data, URLResponse) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        config.httpShouldSetCookies = false
        config.protocolClasses = [DemoURLProtocol.self] + (config.protocolClasses ?? [])
        let reporter = UploadProgressReporter(onProgress: onProgress)
        let delegate = UploadProgressDelegate(reporter: reporter)
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        onProgress?(0.05)
        do {
            return try await session.upload(for: request, fromFile: fileURL, delegate: delegate)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
    }
}

/// Thread-safe monotonic progress reporter that scales streamed bytes into 0...0.95
/// so the UI does not appear stuck at 100% while waiting for the gateway to persist and reply.
nonisolated private final class UploadProgressReporter: Sendable {
    private let onProgress: (@Sendable (Double) -> Void)?
    private let lastPercent = OSAllocatedUnfairLock(initialState: -1)

    init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func report(bytesSent: Int64, totalBytes: Int64) {
        guard totalBytes > 0, bytesSent > 0 else { return }
        let raw = max(0, min(1, Double(bytesSent) / Double(totalBytes)))
        let scaled = min(0.95, max(0.05, raw * 0.95))
        let percent = Int((scaled * 100).rounded(.down))
        let shouldEmit = lastPercent.withLock { last -> Bool in
            if percent > last {
                last = percent
                return true
            }
            return false
        }
        if shouldEmit {
            onProgress?(scaled)
        }
    }
}

nonisolated private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let reporter: UploadProgressReporter

    init(reporter: UploadProgressReporter) {
        self.reporter = reporter
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        reporter.report(bytesSent: totalBytesSent, totalBytes: totalBytesExpectedToSend)
    }
}
