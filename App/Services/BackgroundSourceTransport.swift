import Foundation
import SpamHoleCore

/// Public datasets can finish transferring while the app is suspended. Credentialed
/// requests use the core's redirect-controlled foreground transport instead.
final class BackgroundSourceTransport: NSObject, SourceHTTPTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = BackgroundSourceTransport()
    static var identifier: String { AppIdentity.current?.downloadIdentifier ?? "unconfigured.SpamHole.source-downloads" }
    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]
    private var completed: [Int: Result<SourceHTTPResponse, Error>] = [:]
    private var completionHandler: (() -> Void)?
    private let foreground = URLSessionSourceTransport()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private struct Pending {
        let url: URL
        let maximumBytes: Int
        let continuation: CheckedContinuation<SourceHTTPResponse, Error>
    }
    private struct Descriptor: Codable {
        let url: URL
        let maximumBytes: Int
    }
    private struct Cached: Codable {
        let requestedURL: URL
        let data: Data
        let statusCode: Int
        let headers: [String: String]
        let finalURL: URL
        let downloadedAt: Date
    }

    private override init() { super.init() }

    func reconnect(completion: @escaping () -> Void) {
        lock.withLock { completionHandler = completion }
        _ = session
    }

    func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> SourceHTTPResponse {
        // Background sessions do not offer the same redirect control. Only public
        // cache validators belong here; Authorization and any other custom headers
        // stay in the redirect-controlled, nonpersistent foreground transport.
        let backgroundHeaders: Set<String> = ["if-none-match", "if-modified-since"]
        if !headers.keys.allSatisfy({ backgroundHeaders.contains($0.lowercased()) }) {
            return try await foreground.fetch(url: url, headers: headers, maximumBytes: maximumBytes)
        }
        guard url.scheme == "https", url.user == nil, url.password == nil else { throw URLError(.badURL) }
        if let cached = consumeCache(for: url, maximumBytes: maximumBytes) { return cached }
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("SpamHole/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 90
        let task = session.downloadTask(with: request)
        task.taskDescription = String(data: try JSONEncoder().encode(Descriptor(url: url, maximumBytes: maximumBytes)), encoding: .utf8)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { pending[task.taskIdentifier] = Pending(url: url, maximumBytes: maximumBytes, continuation: continuation) }
                if Task.isCancelled {
                    cancelWaiter(taskID: task.taskIdentifier)
                    task.cancel()
                } else { task.resume() }
            }
        } onCancel: { self.cancelWaiter(taskID: task.taskIdentifier) }
    }

    private func cancelWaiter(taskID: Int) {
        let waiter = lock.withLock { pending.removeValue(forKey: taskID) }
        waiter?.continuation.resume(throwing: CancellationError())
        // A suspended app may still receive the completed file on its next wake.
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let result: Result<SourceHTTPResponse, Error> = Result {
            guard let description = downloadTask.taskDescription?.data(using: .utf8),
                  let descriptor = try? JSONDecoder().decode(Descriptor.self, from: description),
                  let response = downloadTask.response as? HTTPURLResponse,
                  let finalURL = response.url, finalURL.scheme == "https",
                  finalURL.host == descriptor.url.host, finalURL.port == descriptor.url.port else {
                throw URLError(.badServerResponse)
            }
            let handle = try FileHandle(forReadingFrom: location)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: descriptor.maximumBytes + 1) ?? Data()
            guard data.count <= descriptor.maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
                if let key = item.key as? String { result[key.lowercased()] = String(describing: item.value) }
            }
            let output = SourceHTTPResponse(data: data, statusCode: response.statusCode, headers: headers, finalURL: finalURL)
            // Recovery after process termination does not refresh the source watermark.
            let cached = Cached(requestedURL: descriptor.url, data: data, statusCode: response.statusCode, headers: headers, finalURL: finalURL, downloadedAt: Date())
            if let url = cacheURL(for: descriptor.url), let encoded = try? JSONEncoder().encode(cached) {
                try? encoded.write(to: url, options: .atomic)
            }
            return output
        }
        lock.withLock { completed[downloadTask.taskIdentifier] = result }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let description = downloadTask.taskDescription?.data(using: .utf8),
              let descriptor = try? JSONDecoder().decode(Descriptor.self, from: description) else { downloadTask.cancel(); return }
        if totalBytesWritten > descriptor.maximumBytes || totalBytesExpectedToWrite > descriptor.maximumBytes {
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (waiter, result) = lock.withLock { (pending.removeValue(forKey: task.taskIdentifier), completed.removeValue(forKey: task.taskIdentifier)) }
        guard let waiter else { return }
        if let error { waiter.continuation.resume(throwing: error) }
        else if let result {
            try? FileManager.default.removeItem(at: cacheURL(for: waiter.url) ?? URL(fileURLWithPath: "/nonexistent"))
            waiter.continuation.resume(with: result)
        } else { waiter.continuation.resume(throwing: URLError(.badServerResponse)) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock { let value = completionHandler; completionHandler = nil; return value }
        DispatchQueue.main.async { completion?() }
    }

    private func cacheURL(for url: URL) -> URL? {
        guard let identity = AppIdentity.current, let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identity.appGroupIdentifier) else { return nil }
        let directory = group.appendingPathComponent("SpamHole/DownloadRecovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A deterministic filename, not an anonymity or integrity mechanism.
        let key = url.absoluteString.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return directory.appendingPathComponent(String(key, radix: 16) + ".json")
    }

    private func consumeCache(for url: URL, maximumBytes: Int) -> SourceHTTPResponse? {
        guard let file = cacheURL(for: url) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let limit = maximumBytes * 2 + 100_000
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit,
              let cached = try? JSONDecoder().decode(Cached.self, from: data), cached.data.count <= maximumBytes,
              cached.requestedURL == url, cached.finalURL.scheme == "https", cached.finalURL.host == url.host,
              cached.finalURL.port == url.port,
              Date().timeIntervalSince(cached.downloadedAt) < 24 * 60 * 60 else { return nil }
        return SourceHTTPResponse(data: cached.data, statusCode: cached.statusCode, headers: cached.headers, finalURL: cached.finalURL)
    }
}
