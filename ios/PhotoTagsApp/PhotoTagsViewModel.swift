import Foundation
import Photos
import SwiftUI
import MultipeerConnectivity
import PhotoTagsCore

@MainActor
final class PhotoTagsViewModel: ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var selectedAssetIDs: Set<String> = []
    @Published var currentTagInput: String = ""
    @Published var selectedFilterTags: Set<String> = []
    @Published var message: String?
    @Published var nearbyPeers: [MCPeerID] = []

    @Published private(set) var index: TagIndex = .init()

    private let store: TagIndexStore
    private let lanTransfer: LANTransferService

    init(store: TagIndexStore, lanTransfer: LANTransferService = LANTransferService()) {
        self.store = store
        self.lanTransfer = lanTransfer
        bindLANTransferCallbacks()
        loadIndex()
    }

    static func makeDefault() -> PhotoTagsViewModel {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = docs.appendingPathComponent("PhotoTags/tag_index.json")
        return PhotoTagsViewModel(store: TagIndexStore(fileURL: fileURL))
    }

    func requestPermissionAndLoadAssets() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let granted: Bool

        switch status {
        case .authorized, .limited:
            granted = true
        case .notDetermined:
            let requested = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            granted = requested == .authorized || requested == .limited
        default:
            granted = false
        }

        guard granted else {
            message = "未获得照片权限，请到系统设置里允许访问照片。"
            return
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var items: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            items.append(asset)
        }
        assets = items
    }

    func startLANDiscovery() {
        lanTransfer.start()
    }

    func stopLANDiscovery() {
        lanTransfer.stop()
    }

    var localDeviceName: String {
        lanTransfer.deviceName
    }

    var allTags: [String] {
        index.allTags
    }

    var filteredAssets: [PHAsset] {
        let filters = Array(selectedFilterTags)
        guard !filters.isEmpty else { return assets }
        let ids = Set(index.search(allTags: filters).map(\.id))
        return assets.filter { ids.contains($0.localIdentifier) }
    }

    func addTagsToSelection() {
        let parsed = TaggedPhoto.normalizeTags([currentTagInput])
        guard !parsed.isEmpty else { return }

        for id in selectedAssetIDs {
            let assetName = id
            index.upsert(photoID: id, originalName: assetName, tags: parsed)
        }

        saveIndex()
        currentTagInput = ""
        message = "已为选中照片添加标签。"
    }

    func tags(for asset: PHAsset) -> [String] {
        index.photosByID[asset.localIdentifier]?.tags ?? []
    }

    func exportSyncJSON() -> URL? {
        do {
            let data = try store.exportSyncPayloadData(from: index)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("phototags_sync.json")
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
