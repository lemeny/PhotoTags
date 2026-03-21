import Foundation
import Testing
@testable import PhotoTagsCore

struct TagIndexTests {
    @Test
    func normalizeTags_supportsChineseCommaAndDedup() {
        let tags = TaggedPhoto.normalizeTags(["cat，dog", " dog", "CAT", ""])
        #expect(tags.count == 3)
        #expect(tags.contains("cat"))
        #expect(tags.contains("dog"))
        #expect(tags.contains("CAT"))
    }

    @Test
    func search_requiresAllSelectedTags() {
        var index = TagIndex()
        index.upsert(photoID: "1", originalName: "a.jpg", tags: ["cat", "sunny"])
        index.upsert(photoID: "2", originalName: "b.jpg", tags: ["cat"])

        let results = index.search(allTags: ["cat", "sunny"])
        #expect(results.map(\.id) == ["1"])
    }

    @Test
    func merge_prefersSha256_thenFallsBackToOriginalName() {
        var index = TagIndex()
        index.upsert(photoID: "local-1", originalName: "IMG_1.HEIC", sha256: "abc", tags: ["old"])
        index.upsert(photoID: "local-2", originalName: "IMG_2.HEIC", tags: ["x"])

        let payload = SyncPayload(photos: [
            .init(original_name: "renamed.HEIC", file_sha256: "abc", tags: ["new"]),
            .init(original_name: "IMG_2.HEIC", tags: ["y"])
        ])

        index.merge(syncPayload: payload)

        let photo1 = index.photosByID["local-1"]
        let photo2 = index.photosByID["local-2"]

        #expect(photo1?.tags.contains("old") == true)
        #expect(photo1?.tags.contains("new") == true)
        #expect(photo2?.tags.contains("x") == true)
        #expect(photo2?.tags.contains("y") == true)
    }

    @Test
    func exportPayload_matchesServerContractShape() throws {
        var index = TagIndex()
        index.upsert(photoID: "1", originalName: "IMG_1.HEIC", sha256: "abc", tags: ["cat"])

        let store = TagIndexStore(fileURL: URL(fileURLWithPath: "/tmp/phototags-tests/index.json"))
        let data = try store.exportSyncPayloadData(from: index)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["version"] as? Int == 1)
        let photos = json?["photos"] as? [[String: Any]]
        #expect(photos?.count == 1)
        #expect(photos?.first?["original_name"] as? String == "IMG_1.HEIC")
        #expect(photos?.first?["file_sha256"] as? String == "abc")
    }

    @Test
    func lanEnvelope_roundtripMergesPayload() throws {
        var sender = TagIndex()
        sender.upsert(photoID: "A", originalName: "IMG_A.HEIC", sha256: "sha-a", tags: ["trip"])

        var receiver = TagIndex()
        receiver.upsert(photoID: "local-a", originalName: "IMG_A.HEIC", tags: ["old"])

        let store = TagIndexStore(fileURL: URL(fileURLWithPath: "/tmp/phototags-tests/index.json"))
        let data = try store.exportLANEnvelopeData(from: sender, senderDeviceName: "Alice-iPhone")

        let envelope = try JSONDecoder().decode(LANTransferEnvelope.self, from: data)
        #expect(envelope.appID == "com.phototags.sync")
        #expect(envelope.senderDeviceName == "Alice-iPhone")
        #expect(envelope.payload.photos.count == 1)

        try store.importLANEnvelopeData(data, into: &receiver)
        let merged = receiver.photosByID["local-a"]
        #expect(merged?.tags.contains("old") == true)
        #expect(merged?.tags.contains("trip") == true)
    }
}
