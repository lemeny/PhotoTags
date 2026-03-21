import Foundation

public struct TagIndex: Codable, Equatable, Sendable {
    public private(set) var photosByID: [String: TaggedPhoto]

    public init(photosByID: [String: TaggedPhoto] = [:]) {
        self.photosByID = photosByID
    }

    public mutating func upsert(photoID: String, originalName: String, sha256: String? = nil, tags: [String]) {
        let normalized = TaggedPhoto.normalizeTags(tags)
        guard !normalized.isEmpty else { return }

        if var existing = photosByID[photoID] {
            existing.tags = TaggedPhoto.normalizeTags(existing.tags + normalized)
            if existing.sha256 == nil {
                existing.sha256 = sha256
            }
            if existing.originalName.isEmpty {
                existing.originalName = originalName
            }
            photosByID[photoID] = existing
            return
        }

        photosByID[photoID] = TaggedPhoto(
            id: photoID,
            originalName: originalName,
            sha256: sha256,
            tags: normalized
        )
    }

    public func search(allTags selectedTags: [String]) -> [TaggedPhoto] {
        let normalizedFilters = TaggedPhoto.normalizeTags(selectedTags)
        let values = photosByID.values

        guard !normalizedFilters.isEmpty else {
            return values.sorted {
                $0.originalName.localizedCaseInsensitiveCompare($1.originalName) == .orderedAscending
            }
        }

        return values
            .filter { photo in
                Set(normalizedFilters).isSubset(of: Set(photo.tags))
            }
            .sorted {
                $0.originalName.localizedCaseInsensitiveCompare($1.originalName) == .orderedAscending
            }
    }

    public var allTags: [String] {
        let tags = photosByID.values.flatMap(\.tags)
        return Array(Set(tags)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    public func exportSyncPayload() -> SyncPayload {
        let photos = photosByID.values.map {
            SyncPhoto(original_name: $0.originalName, file_sha256: $0.sha256, tags: $0.tags)
        }
        .sorted {
            $0.original_name.localizedCaseInsensitiveCompare($1.original_name) == .orderedAscending
        }

        return SyncPayload(photos: photos)
    }

    public mutating func merge(syncPayload: SyncPayload) {
        for photo in syncPayload.photos {
            if let sha = photo.file_sha256,
               let existingID = photosByID.first(where: { $0.value.sha256 == sha })?.key {
                upsert(
                    photoID: existingID,
                    originalName: photo.original_name,
                    sha256: sha,
                    tags: photo.tags
                )
                continue
            }

            if let existingID = photosByID.first(
                where: { $0.value.originalName == photo.original_name }
            )?.key {
                upsert(
                    photoID: existingID,
                    originalName: photo.original_name,
                    sha256: photo.file_sha256,
                    tags: photo.tags
                )
                continue
            }

            let fallbackID = photo.file_sha256 ?? photo.original_name
            upsert(
                photoID: fallbackID,
                originalName: photo.original_name,
                sha256: photo.file_sha256,
                tags: photo.tags
            )
        }
    }
}
