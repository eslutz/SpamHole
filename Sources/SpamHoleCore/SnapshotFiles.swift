import Foundation

public struct SnapshotFiles: Sendable {
    public static let sharedRelativePath = "SpamHole/Protection"
    private static let publicationLock = NSLock()
    public let rootURL: URL
    public init(rootURL: URL) { self.rootURL = rootURL }
    private struct Pointer: Codable {
        var schemaVersion = 1
        var generationID: UUID
        var previousGenerationIDs: [UUID]? = nil
    }
    private var currentURL: URL { rootURL.appendingPathComponent("current.json") }
    private var receiptURL: URL { rootURL.appendingPathComponent("installed-call-generation.json") }
    private func generationURL(_ id: UUID) -> URL {
        rootURL.appendingPathComponent("generations", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    }
    public func publish(snapshot: ProtectionSnapshot) throws {
        try Self.publicationLock.withLock { try publishUnlocked(snapshot: snapshot) }
    }
    private func publishUnlocked(snapshot: ProtectionSnapshot) throws {
        try snapshot.validate()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let prior = try? decoder().decode(Pointer.self, from: boundedRead(currentURL, maximumBytes: 4096))
        let history = ([prior?.generationID].compactMap { $0 } + (prior?.previousGenerationIDs ?? []))
            .filter { $0 != snapshot.metadata.id }.prefix(2)
        let pointer = Pointer(generationID: snapshot.metadata.id, previousGenerationIDs: Array(history))
        let directory = generationURL(snapshot.metadata.id)
        guard !fileManager.fileExists(atPath: directory.path) else {
            throw SpamHoleCoreError.invalidSnapshot("Generation IDs are immutable; create a new generation")
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try encoder().encode(snapshot).write(to: directory.appendingPathComponent("snapshot.json"), options: .atomic)
            try encoder().encode(snapshot.metadata).write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
            try CallDirectorySnapshotReader.write(snapshot: snapshot, directory: directory)
            // Point readers at the new, complete generation only after its payload has been persisted.
            try encoder().encode(pointer).write(to: currentURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
        // Cleanup is best-effort after commitment. It must never roll back or remove the newly active generation.
        try? pruneGenerations(keeping: pointer)
    }
    public func callDirectoryReader() throws -> CallDirectorySnapshotReader {
        let pointer = try decoder().decode(Pointer.self, from: boundedRead(currentURL, maximumBytes: 4096))
        guard pointer.schemaVersion == 1 else { throw SpamHoleCoreError.unsupportedSchema }
        let directory = generationURL(pointer.generationID)
        let metadata = try decoder().decode(GenerationMetadata.self, from: boundedRead(directory.appendingPathComponent("metadata.json"), maximumBytes: 4096))
        guard metadata.id == pointer.generationID else { throw SpamHoleCoreError.invalidSnapshot("Generation identity mismatch") }
        return try CallDirectorySnapshotReader(metadata: metadata, directory: directory)
    }
    public func loadCurrent() throws -> ProtectionSnapshot {
        guard FileManager.default.fileExists(atPath: currentURL.path) else { throw SpamHoleCoreError.snapshotUnavailable }
        let pointer = try decoder().decode(Pointer.self, from: boundedRead(currentURL, maximumBytes: 4096))
        guard pointer.schemaVersion == 1 else { throw SpamHoleCoreError.unsupportedSchema }
        let snapshot = try decoder().decode(ProtectionSnapshot.self,
            from: boundedRead(generationURL(pointer.generationID).appendingPathComponent("snapshot.json"), maximumBytes: 128 * 1024 * 1024))
        guard snapshot.metadata.id == pointer.generationID else { throw SpamHoleCoreError.invalidSnapshot("Generation identity mismatch") }
        try snapshot.validate()
        return snapshot
    }
    public func loadInstallationReceipt() throws -> CallInstallationReceipt? {
        guard FileManager.default.fileExists(atPath: receiptURL.path) else { return nil }
        return try decoder().decode(CallInstallationReceipt.self, from: boundedRead(receiptURL, maximumBytes: 4096))
    }
    public func writeInstallationReceipt(_ receipt: CallInstallationReceipt) throws {
        guard receipt.identificationCount >= 0, receipt.blockingCount >= 0 else {
            throw SpamHoleCoreError.invalidSnapshot("Invalid installed entry counts")
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try encoder().encode(receipt).write(to: receiptURL, options: .atomic)
    }
    private func pruneGenerations(keeping pointer: Pointer) throws {
        var protected = Set([pointer.generationID] + (pointer.previousGenerationIDs ?? []))
        if let receipt = try? loadInstallationReceipt() { protected.insert(receipt.generationID) }
        let directory = rootURL.appendingPathComponent("generations", isDirectory: true)
        let children = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        for child in children {
            guard let id = UUID(uuidString: child.lastPathComponent), !protected.contains(id) else { continue }
            let properties = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard properties.isDirectory == true, properties.isSymbolicLink != true else { continue }
            try? FileManager.default.removeItem(at: child)
        }
    }
    private func boundedRead(_ url: URL, maximumBytes: Int) throws -> Data {
        // Read through a bounded file handle rather than mapping an unbounded publisher-generated file.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw SpamHoleCoreError.invalidSnapshot("Snapshot exceeds size limit") }
        return data
    }
    private func encoder() -> JSONEncoder {
        let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; value.outputFormatting = [.sortedKeys]; return value
    }
    private func decoder() -> JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}
