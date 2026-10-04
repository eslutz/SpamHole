import Foundation

/// Streams immutable binary exports using bounded reads, so CallKit never decodes app assessments.
public struct CallDirectorySnapshotReader: Sendable {
    public let metadata: GenerationMetadata
    private let files: PinnedCallExportFiles
    private static let blockingMagic = Data("SPHBL001".utf8)
    private static let identificationMagic = Data("SPHID001".utf8)
    init(metadata: GenerationMetadata, directory: URL) throws {
        guard metadata.schemaVersion == 1 else { throw SpamHoleCoreError.unsupportedSchema }
        guard (0...1_000_000).contains(metadata.callIdentificationCount),
              (0...1_000_000).contains(metadata.callBlockCount) else {
            throw SpamHoleCoreError.invalidSnapshot("Call export exceeds capacity")
        }
        self.metadata = metadata; self.files = try PinnedCallExportFiles(directory: directory)
    }
    public func streamBlocking(_ body: (Int64) throws -> Void) throws {
        try files.lock.withLock { try streamBlockingUnlocked(body) }
    }
    private func streamBlockingUnlocked(_ body: (Int64) throws -> Void) throws {
        let handle = try open("call-blocking.bin", magic: Self.blockingMagic, count: metadata.callBlockCount)
        var last: Int64 = 0
        for _ in 0..<metadata.callBlockCount {
            let number = try readNumber(handle)
            guard number > last else { throw invalid("Unsorted or duplicate call block") }
            last = number; try body(number)
        }
        try requireEnd(handle)
    }
    public func streamIdentification(_ body: (CallIdentificationEntry) throws -> Void) throws {
        try files.lock.withLock { try streamIdentificationUnlocked(body) }
    }
    private func streamIdentificationUnlocked(_ body: (CallIdentificationEntry) throws -> Void) throws {
        let identification = try open("call-identification.bin", magic: Self.identificationMagic, count: metadata.callIdentificationCount)
        let blocking = try open("call-blocking.bin", magic: Self.blockingMagic, count: metadata.callBlockCount)
        var blockRemaining = metadata.callBlockCount
        var lastBlock: Int64 = 0
        func nextBlock() throws -> Int64? {
            guard blockRemaining > 0 else { return nil }
            let number = try readNumber(blocking)
            guard number > lastBlock else { throw invalid("Unsorted or duplicate call block") }
            lastBlock = number; blockRemaining -= 1
            return number
        }
        var upcomingBlock = try nextBlock()
        var previous: Int64 = 0
        for _ in 0..<metadata.callIdentificationCount {
            let number = try readNumber(identification)
            guard number > previous else { throw invalid("Unsorted or duplicate call identification") }
            previous = number
            while let candidate = upcomingBlock, candidate < number { upcomingBlock = try nextBlock() }
            guard upcomingBlock != number else { throw invalid("Number appears in both call exports") }
            let lengthData = try readExactly(identification, count: 2)
            let length = Int(lengthData.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self)) })
            guard (1...128).contains(length),
                  let label = String(data: try readExactly(identification, count: length), encoding: .utf8),
                  !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw invalid("Invalid call identification label")
            }
            try body(.init(number: number, label: label))
        }
        while blockRemaining > 0 { _ = try nextBlock() }
        try requireEnd(identification); try requireEnd(blocking)
    }
    private func open(_ name: String, magic: Data, count: Int) throws -> FileHandle {
        let handle = name == "call-blocking.bin" ? files.blocking : files.identification
        try handle.seek(toOffset: 0)
        guard try readExactly(handle, count: 8) == magic else { throw invalid("Invalid call export header") }
        let countData = try readExactly(handle, count: 8)
        let storedCount = countData.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
        guard storedCount == UInt64(count) else { throw invalid("Call export count mismatch") }
        return handle
    }
    private func readNumber(_ handle: FileHandle) throws -> Int64 {
        let bytes = try readExactly(handle, count: 8)
        let number = bytes.withUnsafeBytes { Int64(littleEndian: $0.loadUnaligned(as: Int64.self)) }
        guard number > 0, (try? PhoneNormalizer.callDirectoryNumber("+\(number)")) == number else {
            throw invalid("Invalid exact call number")
        }
        return number
    }
    private func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data(); result.reserveCapacity(count)
        while result.count < count {
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else {
                throw invalid("Truncated call export")
            }
            result.append(chunk)
        }
        return result
    }
    private func requireEnd(_ handle: FileHandle) throws {
        guard (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw invalid("Trailing bytes in call export") }
    }
    private func invalid(_ message: String) -> SpamHoleCoreError { .invalidSnapshot(message) }
    static func write(snapshot: ProtectionSnapshot, directory: URL) throws {
        func writer(_ name: String, magic: Data, count: Int, body: (FileHandle) throws -> Void) throws {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw SpamHoleCoreError.invalidSnapshot("Cannot create call export")
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.write(contentsOf: magic)
            var storedCount = UInt64(count).littleEndian
            try withUnsafeBytes(of: &storedCount) { try handle.write(contentsOf: Data($0)) }
            try body(handle)
            try handle.synchronize()
        }
        try writer("call-blocking.bin", magic: blockingMagic, count: snapshot.callBlocking.count) { handle in
            for entry in snapshot.callBlocking {
                var number = entry.littleEndian
                try withUnsafeBytes(of: &number) { try handle.write(contentsOf: Data($0)) }
            }
        }
        try writer("call-identification.bin", magic: identificationMagic, count: snapshot.callIdentification.count) { handle in
            for entry in snapshot.callIdentification {
                var number = entry.number.littleEndian
                let label = Data(entry.label.utf8)
                var length = UInt16(label.count).littleEndian
                try withUnsafeBytes(of: &number) { try handle.write(contentsOf: Data($0)) }
                try withUnsafeBytes(of: &length) { try handle.write(contentsOf: Data($0)) }
                try handle.write(contentsOf: label)
            }
        }
    }
}

/// Open descriptors retain their immutable file contents even when a later publication prunes the directory.
/// The lock serializes shared descriptor positions across copied readers and concurrent callers.
private final class PinnedCallExportFiles: @unchecked Sendable {
    let lock = NSLock()
    let blocking: FileHandle
    let identification: FileHandle
    init(directory: URL) throws {
        let opened = try FileHandle(forReadingFrom: directory.appendingPathComponent("call-blocking.bin"))
        do {
            identification = try FileHandle(forReadingFrom: directory.appendingPathComponent("call-identification.bin"))
            blocking = opened
        } catch { try? opened.close(); throw error }
    }
    deinit { try? blocking.close(); try? identification.close() }
}
