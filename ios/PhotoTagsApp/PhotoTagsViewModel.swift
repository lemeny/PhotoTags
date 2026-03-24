import Foundation
import Photos
import SwiftUI
import MultipeerConnectivity
import PhotoTagsCore

@MainActor
final class PhotoTagsViewModel: ObservableObject {
    enum AssetScope: String, CaseIterable {
        case all = "All"
        case untagged = "Untagged"
    }

    @Published var assets: [PHAsset] = []
    @Published var selectedAssetIDs: Set<String> = []
    @Published var currentTagInput: String = ""
    @Published var selectedFilterTags: Set<String> = []
    @Published var selectedScope: AssetScope = .all
    @Published var message: String?
    @Published var nearbyPeers: [MCPeerID] = []
    @Published var quickTags: [String] = ["clay", "texture", "reference", "ui", "logo", "inspiration", "3d", "material"]

    @Published private(set) var index: TagIndex = .init()
    @Published private(set) var annotatedAtByID: [String: Date?] = [:]

    private let store: TagIndexStore
    private let lanTransfer: LANTransferService
    private let photoProvider: PhotoProvider
    private let coreDataStore: CoreDataTagStore
    private let exportService = ExportService()

    init(
        store: TagIndexStore,
        lanTransfer: LANTransferService = LANTransferService(),
        photoProvider: PhotoProvider = PhotoProvider(),
        coreDataStore: CoreDataTagStore = CoreDataTagStore()
    ) {
        self.store = store
        self.lanTransfer = lanTransfer
        self.photoProvider = photoProvider
        self.coreDataStore = coreDataStore
        bindLANTransferCallbacks()
        loadIndex()
    }

    static func makeDefault() -> PhotoTagsViewModel {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = docs.appendingPathComponent("PhotoTags/tag_index.json")
        return PhotoTagsViewModel(store: TagIndexStore(fileURL: fileURL))
    }

    func requestPermissionAndLoadAssets() async {
        let granted = await photoProvider.requestPhotoPermission()
        guard granted else {
            message = "未获得照片权限，请到系统设置里允许访问照片。"
            return
        }

        assets = photoProvider.loadAssets()
        photoProvider.startCaching(assets: assets)

        do {
            let rows = try coreDataStore.allRecords()
            for row in rows {
                index.upsert(photoID: row.id, originalName: row.id, tags: row.tags)
                annotatedAtByID[row.id] = row.annotatedAt
            }
        } catch {
            message = "加载 CoreData 标签失败：\(error.localizedDescription)"
        }
    }

    func startLANDiscovery() { lanTransfer.start() }
    func stopLANDiscovery() { lanTransfer.stop() }

    var localDeviceName: String { lanTransfer.deviceName }
    var allTags: [String] { index.allTags }

    var visibleAssets: [PHAsset] {
        switch selectedScope {
        case .all: return assets
        case .untagged:
            return assets.filter { tags(for: $0).isEmpty }
        }
    }

    var filteredAssets: [PHAsset] {
        let base = visibleAssets
        let filters = Array(selectedFilterTags)
        guard !filters.isEmpty else { return base }
        let ids = Set(index.search(allTags: filters).map(\.id))
        return base.filter { ids.contains($0.localIdentifier) }
    }

    func addTagsToSelection() {
        let parsed = TaggedPhoto.normalizeTags([currentTagInput])
        guard !parsed.isEmpty else { return }

        for id in selectedAssetIDs {
            index.upsert(photoID: id, originalName: id, tags: parsed)
            try? coreDataStore.upsert(assetID: id, tags: parsed)
            annotatedAtByID[id] = .now
        }

        saveIndex()
        currentTagInput = ""
        message = "已为选中照片添加标签。"
    }

    func addQuickTagAndMoveNext(tag: String, asset: PHAsset) -> PHAsset? {
        let normalized = TaggedPhoto.normalizeTags([tag])
        guard !normalized.isEmpty else { return nil }

        index.upsert(photoID: asset.localIdentifier, originalName: asset.localIdentifier, tags: normalized)
        try? coreDataStore.upsert(assetID: asset.localIdentifier, tags: normalized)
        annotatedAtByID[asset.localIdentifier] = .now
        saveIndex()

        guard let current = filteredAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else {
            return nil
        }
        let nextIndex = min(current + 1, max(filteredAssets.count - 1, 0))
        return filteredAssets.indices.contains(nextIndex) ? filteredAssets[nextIndex] : nil
    }

    func tags(for asset: PHAsset) -> [String] {
        index.photosByID[asset.localIdentifier]?.tags ?? []
    }

    func exportSelectedAssetsPackage() async -> URL? {
        let selected = assets.filter { selectedAssetIDs.contains($0.localIdentifier) }
        guard !selected.isEmpty else {
            message = "请先选择至少一张素材。"
            return nil
        }

        let tagsByID = Dictionary(uniqueKeysWithValues: selected.map { ($0.localIdentifier, tags(for: $0)) })
        do {
            let url = try await exportService.export(assets: selected, tagsByID: tagsByID, annotatedAtByID: annotatedAtByID)
            message = "导出成功（HEIC + JSON）。"
            return url
        } catch {
            message = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    func exportSyncJSON() -> URL? {
        do {
            let data = try store.exportSyncPayloadData(from: index)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("phototags_sync.json")
            try data.write(to: tmp, options: .atomic)
            message = "导出成功，可分享到电脑。"
            return tmp
        } catch {
            message = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    func importSyncJSON(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            var mutable = index
            try store.importSyncPayloadData(data, into: &mutable)
            index = mutable
            saveIndex()
            message = "导入并合并成功。"
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }

    func sendCurrentTagsToPeer(_ peer: MCPeerID) {
        do {
            let data = try store.exportLANEnvelopeData(from: index, senderDeviceName: localDeviceName)
            try lanTransfer.send(envelopeData: data, to: peer)
            message = "标签数据已发送到：\(peer.displayName)"
        } catch {
            message = "发送失败：\(error.localizedDescription)"
        }
    }

    private func bindLANTransferCallbacks() {
        lanTransfer.onStateMessage = { [weak self] text in
            self?.message = text
            self?.nearbyPeers = self?.lanTransfer.nearbyPeers ?? []
        }

        lanTransfer.onReceiveEnvelopeData = { [weak self] data, peer in
            guard let self else { return }
            do {
                var mutable = self.index
                try self.store.importLANEnvelopeData(data, into: &mutable)
                self.index = mutable
                self.saveIndex()
                self.message = "已接收并合并来自 \(peer.displayName) 的标签数据。"
            } catch {
                self.message = "接收数据解析失败：\(error.localizedDescription)"
            }
        }
    }

    private func loadIndex() {
        do {
            index = try store.load()
        } catch {
            message = "加载标签失败：\(error.localizedDescription)"
        }
    }

    private func saveIndex() {
        do {
            try store.save(index)
        } catch {
            message = "保存标签失败：\(error.localizedDescription)"
        }
    }
}
