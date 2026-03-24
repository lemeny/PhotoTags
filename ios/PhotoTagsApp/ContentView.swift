import SwiftUI
import Photos
import PhotoTagsCore

struct ContentView: View {
    @ObservedObject var viewModel: PhotoTagsViewModel
    @State private var exportURL: URL?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var focusAsset: PHAsset?

    private let imageManager = PHCachingImageManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                scopePicker
                filterBar
                tagEditor
                actionBar
                lanTransferPanel

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(viewModel.filteredAssets, id: \.localIdentifier) { asset in
                            AssetCell(
                                asset: asset,
                                tags: viewModel.tags(for: asset),
                                selected: viewModel.selectedAssetIDs.contains(asset.localIdentifier),
                                imageManager: imageManager
                            ) {
                                toggleSelection(asset.localIdentifier)
                            }
                            .onLongPressGesture {
                                focusAsset = asset
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .padding(.top, 8)
            .navigationTitle("PhotoTags iOS")
            .task {
                await viewModel.requestPermissionAndLoadAssets()
                viewModel.startLANDiscovery()
            }
            .onDisappear { viewModel.stopLANDiscovery() }
            .alert("提示", isPresented: Binding(get: {
                viewModel.message != nil
            }, set: { shown in
                if !shown { viewModel.message = nil }
            })) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(viewModel.message ?? "")
            }
            .sheet(isPresented: $showExporter) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(item: $focusAsset) { asset in
                FastTaggingView(viewModel: viewModel, asset: asset) { next in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        focusAsset = next
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                if case let .success(urls) = result, let first = urls.first {
                    viewModel.importSyncJSON(from: first)
                }
            }
        }
    }

    private var scopePicker: some View {
        Picker("Scope", selection: $viewModel.selectedScope) {
            ForEach(PhotoTagsViewModel.AssetScope.allCases, id: \.self) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 8)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(viewModel.allTags, id: \.self) { tag in
                    let selected = viewModel.selectedFilterTags.contains(tag)
                    Button(tag) {
                        if selected { viewModel.selectedFilterTags.remove(tag) }
                        else { viewModel.selectedFilterTags.insert(tag) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selected ? .blue : .gray)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var tagEditor: some View {
        HStack {
            TextField("输入标签，逗号分隔", text: $viewModel.currentTagInput)
                .textFieldStyle(.roundedBorder)
            Button("添加到选中") { viewModel.addTagsToSelection() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 8)
    }

    private var actionBar: some View {
        HStack {
            Button("导出 HEIC+JSON") {
                Task {
                    exportURL = await viewModel.exportSelectedAssetsPackage()
                    showExporter = exportURL != nil
                }
            }
            .buttonStyle(.borderedProminent)

            Button("导出标签JSON") {
                exportURL = viewModel.exportSyncJSON()
                showExporter = exportURL != nil
            }
            .buttonStyle(.bordered)

            Button("导入 JSON") { showImporter = true }
                .buttonStyle(.bordered)
        }
    }

    private var lanTransferPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("局域网传输（LocalSend 风格）")
                .font(.headline)
            Text("当前设备：\(viewModel.localDeviceName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.nearbyPeers.isEmpty {
                Text("未发现可用设备，请确保双方都打开本页面且在同一 Wi‑Fi。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.nearbyPeers, id: \.self) { peer in
                    HStack {
                        Text(peer.displayName)
                        Spacer()
                        Button("发送标签") { viewModel.sendCurrentTagsToPeer(peer) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
    }

    private func toggleSelection(_ id: String) {
        if viewModel.selectedAssetIDs.contains(id) { viewModel.selectedAssetIDs.remove(id) }
        else { viewModel.selectedAssetIDs.insert(id) }
    }
}

private struct FastTaggingView: View {
    @ObservedObject var viewModel: PhotoTagsViewModel
    let asset: PHAsset
    let onMoveNext: (PHAsset?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var customInput = ""
    private let imageManager = PHCachingImageManager()

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ProgressView()
                }
            }
            .frame(maxHeight: 320)

            Text(viewModel.tags(for: asset).joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(viewModel.quickTags, id: \.self) { tag in
                    Button(tag) {
                        let next = viewModel.addQuickTagAndMoveNext(tag: tag, asset: asset)
                        onMoveNext(next)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack {
                TextField("手动输入标签", text: $customInput)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    let chunks = TaggedPhoto.normalizeTags([customInput])
                    guard let first = chunks.first else { return }
                    let next = viewModel.addQuickTagAndMoveNext(tag: first, asset: asset)
                    customInput = ""
                    onMoveNext(next)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .presentationDetents([.large])
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { dismiss() }
            }
        }
        .task { loadLargePreview() }
    }

    private func loadLargePreview() {
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 1400, height: 1400),
            contentMode: .aspectFit,
            options: nil
        ) { image, _ in
            self.image = image
        }
    }
}

extension PHAsset: Identifiable {
    public var id: String { localIdentifier }
}
