import Foundation

public struct TaggedPhoto: Codable, Equatable, Sendable {
    public var id: String
    public var originalName: String
    public var sha256: String?
    public var tags: [String]

    public init(id: String, originalName: String, sha256: String? = nil, tags: [String]) {
        self.id = id
        self.originalName = originalName
        self.sha256 = sha256
        self.tags = TaggedPhoto.normalizeTags(tags)
    }

    public static func normalizeTags(_ tags: [String]) -> [String] {
        let cleaned = tags
            .flatMap { $0.replacingOccurrences(of: "，", with: ",").split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(Set(cleaned)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}

public struct SyncPhoto: Codable, Equatable, Sendable {
    public var original_name: String
    public var file_sha256: String?
    public var tags: [String]

    public init(original_name: String, file_sha256: String? = nil, tags: [String]) {
        self.original_name = original_name
        self.file_sha256 = file_sha256
        self.tags = TaggedPhoto.normalizeTags(tags)
    }
}

public struct SyncPayload: Codable, Equatable, Sendable {
    public var version: Int
    public var photos: [SyncPhoto]

    public init(version: Int = 1, photos: [SyncPhoto]) {
        self.version = version
        self.photos = photos
    }
}
