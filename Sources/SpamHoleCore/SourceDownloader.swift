import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SourceHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]
    public let finalURL: URL
    public init(data: Data, statusCode: Int, headers: [String: String] = [:], finalURL: URL) {
        self.data = data; self.statusCode = statusCode; self.headers = headers; self.finalURL = finalURL
    }
    public func header(_ name: String) -> String? { headers.first { $0.key.lowercased() == name.lowercased() }?.value }
}
public protocol SourceHTTPTransport: Sendable {
    func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> SourceHTTPResponse
}

/// Downloads a file rather than buffering an unbounded response in memory. Headers and URLs are never logged.
public final class URLSessionSourceTransport: NSObject, SourceHTTPTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    private let limitsLock = NSLock()
    private var sessionLimits: [ObjectIdentifier: Int] = [:]
    public override init() { super.init() }
    public func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> SourceHTTPResponse {
        try SourceCatalog.validateURL(url)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45; configuration.timeoutIntervalForResource = 120
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        limitsLock.withLock { sessionLimits[ObjectIdentifier(session)] = maximumBytes }
        defer {
            session.finishTasksAndInvalidate()
            _ = limitsLock.withLock { sessionLimits.removeValue(forKey: ObjectIdentifier(session)) }
        }
        var request = URLRequest(url: url); request.httpMethod = "GET"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (temporaryURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard let response = response as? HTTPURLResponse, let finalURL = response.url else { throw SourceImportError.invalidURL }
        guard response.expectedContentLength <= Int64(maximumBytes) else { throw SourceImportError.oversizedPayload }
        let handle = try FileHandle(forReadingFrom: temporaryURL); defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(64 * 1024, maximumBytes - data.count + 1)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximumBytes else { throw SourceImportError.oversizedPayload }
        }
        var responseHeaders: [String: String] = [:]
        for (key, value) in response.allHeaderFields { responseHeaders[String(describing: key)] = String(describing: value) }
        return SourceHTTPResponse(data: data, statusCode: response.statusCode, headers: responseHeaders, finalURL: finalURL)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let redirect = request.url,
              redirect.scheme == "https", redirect.host == original.host, redirect.port == original.port else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let limit = limitsLock.withLock { sessionLimits[ObjectIdentifier(session)] ?? 0 }
        if totalBytesWritten > Int64(limit) || totalBytesExpectedToWrite > Int64(limit) { downloadTask.cancel() }
    }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

public struct SourceRefreshResult: Sendable {
    public let sourceID: String
    public let recordCount: Int
    public let rejectedRecordCount: Int
    public let publisherWatermark: Date
    public let lastSuccessAt: Date
}

public actor SourceDownloader {
    private let store: EvidenceStore
    private let transport: any SourceHTTPTransport
    public init(store: EvidenceStore, transport: any SourceHTTPTransport = URLSessionSourceTransport()) {
        self.store = store; self.transport = transport
    }
    @discardableResult
    /// Refreshes an existing enabled subscription. Registration and user changes belong to the app;
    /// a stale queued request cannot recreate a removed subscription or reenable a disabled one.
    public func refresh(source: SourceDefinition, now: Date = Date(), headers: [String: String] = [:]) async throws -> SourceRefreshResult {
        let requested = SourceCatalog.canonicalize(source)
        try SourceCatalog.validateURL(requested.url)
        try Task.checkCancellation()
        guard let canonical = try store.sources().first(where: { $0.id == source.id }), canonical.enabled,
              canonical.url == requested.url, canonical.format == requested.format, canonical.channels == requested.channels else {
            throw SourceImportError.sourceChanged
        }
        var previous = try store.sourceState(id: source.id) ?? SourceState(sourceID: source.id)
        previous.lastAttemptAt = now; previous.error = nil
        try store.saveSourceState(previous)
        do {
            let parsed: ParsedSourceImport; let lastResponse: SourceHTTPResponse
            switch canonical.format {
            case .ftcCSV:
                let landing = try await fetch(canonical.url, headers: headers, maximumBytes: 4 * 1024 * 1024)
                guard let html = String(data: landing.data, encoding: .utf8) else { throw SourceImportError.invalidEncoding }
                let links = try Self.discoverFTCFiles(html: html, pageURL: canonical.url)
                guard !links.isEmpty else { throw SourceImportError.noPublishedFiles }
                var records: [EvidenceRecord] = []; var rejected = 0; var coverage = Date.distantPast; var bytes = 0
                for link in links {
                    let response = try await fetch(link, headers: headers, maximumBytes: 8 * 1024 * 1024)
                    bytes += response.data.count
                    guard bytes <= 64 * 1024 * 1024 else { throw SourceImportError.oversizedPayload }
                    let file = try SourceAdapters.parse(data: response.data, source: canonical, now: now)
                    coverage = max(coverage, file.publisherWatermark); rejected += file.rejectedRecordCount
                    records.append(contentsOf: file.records)
                    guard records.count <= SourceAdapters.maximumRecords else { throw SourceImportError.tooManyRecords }
                }
                // Daily files are publication shards, not a complete deletion-capable snapshot.
                // Retain previously observed rows for the research retention window when old links roll off.
                var unique: [String: EvidenceRecord] = [:]
                for record in try store.evidence(enabledOnly: false) where record.sourceID == canonical.id
                    && (record.observedAt ?? record.reportedAt) > now.addingTimeInterval(-90 * 86400) {
                    unique[record.id] = record
                }
                for var record in records where (record.observedAt ?? record.reportedAt) > now.addingTimeInterval(-90 * 86400) {
                    record.publisherWatermark = coverage; unique[record.id] = record
                }
                for (id, var record) in unique { record.publisherWatermark = coverage; unique[id] = record }
                guard unique.count <= SourceAdapters.maximumRecords else { throw SourceImportError.tooManyRecords }
                parsed = ParsedSourceImport(records: unique.values.sorted { $0.id < $1.id }, publisherWatermark: coverage, rejectedRecordCount: rejected)
                lastResponse = landing
            case .fccJSON:
                var components = URLComponents(url: canonical.url, resolvingAgainstBaseURL: false)!
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
                let since = formatter.string(from: now.addingTimeInterval(-90 * 86400))
                var objects: [[String: Any]] = []; var offset = 0; var bytes = 0; var finalResponse: SourceHTTPResponse?
                repeat {
                    components.queryItems = [URLQueryItem(name: "$where", value: "type_of_call_or_messge='Text Message' AND issue_date IS NOT NULL AND issue_date >= '\(since)'"),
                                             URLQueryItem(name: "$order", value: "issue_date DESC, id ASC"),
                                             URLQueryItem(name: "$limit", value: "50000"), URLQueryItem(name: "$offset", value: String(offset))]
                    let response = try await fetch(components.url!, headers: headers, maximumBytes: 32 * 1024 * 1024)
                    finalResponse = response; bytes += response.data.count
                    guard bytes <= 64 * 1024 * 1024,
                          let page = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] else {
                        throw SourceImportError.invalidSchema("FCC response is not a bounded JSON array.")
                    }
                    objects.append(contentsOf: page)
                    guard objects.count <= SourceAdapters.maximumRecords else { throw SourceImportError.tooManyRecords }
                    if page.count < 50000 { break }; offset += page.count
                } while offset < SourceAdapters.maximumRecords
                guard offset < SourceAdapters.maximumRecords else { throw SourceImportError.tooManyRecords }
                parsed = try SourceAdapters.parse(data: JSONSerialization.data(withJSONObject: objects), source: canonical, now: now)
                lastResponse = finalResponse!
            default:
                var conditionalHeaders = headers
                if let etag = previous.etag { conditionalHeaders["If-None-Match"] = etag }
                if let modified = previous.lastModified { conditionalHeaders["If-Modified-Since"] = modified }
                let response = try await fetch(canonical.url, headers: conditionalHeaders, maximumBytes: 32 * 1024 * 1024, allowNotModified: true)
                if response.statusCode == 304 {
                    try Task.checkCancellation()
                    guard let watermark = previous.publisherWatermark, previous.lastSuccessAt != nil else {
                        throw SourceImportError.invalidSchema("Publisher returned Not Modified before any valid snapshot.")
                    }
                    previous.lastSuccessAt = now; previous.error = nil; try store.saveSourceState(previous)
                    return SourceRefreshResult(sourceID: source.id, recordCount: previous.recordCount, rejectedRecordCount: 0,
                                               publisherWatermark: watermark, lastSuccessAt: now)
                }
                parsed = try SourceAdapters.parse(data: response.data, source: canonical, now: now,
                                                  publisherWatermark: Self.httpDate(response.header("Last-Modified")))
                lastResponse = response
            }
            let state = SourceState(sourceID: canonical.id, lastAttemptAt: now, lastSuccessAt: now,
                                    publisherWatermark: parsed.publisherWatermark, etag: lastResponse.header("ETag"),
                                    lastModified: lastResponse.header("Last-Modified"), recordCount: parsed.records.count)
            try Task.checkCancellation()
            try store.replaceEvidence(parsed.records, source: canonical, state: state, requireCurrentSource: true)
            return SourceRefreshResult(sourceID: canonical.id, recordCount: parsed.records.count,
                                       rejectedRecordCount: parsed.rejectedRecordCount, publisherWatermark: parsed.publisherWatermark, lastSuccessAt: now)
        } catch {
            previous.error = Self.safeError(error); try? store.saveSourceState(previous)
            throw error
        }
    }
    private func fetch(_ url: URL, headers: [String: String], maximumBytes: Int,
                       allowNotModified: Bool = false) async throws -> SourceHTTPResponse {
        try SourceCatalog.validateURL(url)
        let response = try await transport.fetch(url: url, headers: headers, maximumBytes: maximumBytes)
        try Task.checkCancellation()
        guard response.finalURL.scheme == "https", response.finalURL.host == url.host, response.finalURL.port == url.port else { throw SourceImportError.invalidURL }
        guard response.data.count <= maximumBytes else { throw SourceImportError.oversizedPayload }
        guard response.statusCode == 200 || (allowNotModified && response.statusCode == 304) else { throw SourceImportError.httpStatus(response.statusCode) }
        if response.statusCode == 200 {
            try SourceAdapters.validateDigest(data: response.data, contentDigest: response.header("Content-Digest"), legacyDigest: response.header("Digest"))
        }
        return response
    }
    public static func discoverFTCFiles(html: String, pageURL: URL) throws -> [URL] {
        let regex = try NSRegularExpression(pattern: "href\\s*=\\s*[\"']([^\"']+\\.csv(?:\\?[^\"']*)?)[\"']", options: [.caseInsensitive])
        var seen = Set<URL>(); var urls: [URL] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let url = URL(string: String(html[range]).replacingOccurrences(of: "&amp;", with: "&"), relativeTo: pageURL)?.absoluteURL,
                  url.scheme == "https", url.host == pageURL.host,
                  url.path.hasSuffix(".csv"), seen.insert(url).inserted else { continue }
            urls.append(url)
        }
        guard urls.count <= 100 else { throw SourceImportError.tooManyRecords }
        return urls
    }
    private static func httpDate(_ text: String?) -> Date? {
        guard let text else { return nil }; let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"; return formatter.date(from: text)
    }
    private static func safeError(_ error: Error) -> String {
        // URLSession errors may include URL query credentials. Persist only our controlled messages/code.
        if let error = error as? SourceImportError { return error.localizedDescription }
        if error is CancellationError { return "Update cancelled; previous dataset retained." }
        return "Download or import failed; previous dataset retained."
    }
}
