import Foundation

public final class TagIndexStore: @unchecked Sendable {
    public enum StoreError: Error {
        case failedToEncode
        case failedToDecode
    }

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> TagIndex {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TagIndex()
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(TagIndex.self, from: data)
    }

    public func save(_ tagIndex: TagIndex) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(tagIndex)
        try data.write(to: fileURL, options: .atomic)
    }

    public func exportSyncPayloadData(from tagIndex: TagIndex) throws -> Data {
        let payload = tagIndex.exportSyncPayload()
        return try encoder.encode(payload)
    }

    public func importSyncPayloadData(_ data: Data, into tagIndex: inout TagIndex) throws {
        let payload = try decoder.decode(SyncPayload.self, from: data)
        tagIndex.merge(syncPayload: payload)
    }
}
