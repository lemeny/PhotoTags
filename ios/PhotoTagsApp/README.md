# PhotoTags iOS App (SwiftUI)

这是可安装到 iPhone 的 V1.0.0 源码（需在 macOS + Xcode 16+ 构建）。

## V1.0.0 功能
- 原生相册扫描：`PhotoProvider` 基于 `PhotoKit` 读取 `PHAsset`，不复制照片。
- 资产浏览器：支持 **All / Untagged** 视图切换。
- 预取优化：使用 `PHCachingImageManager` 做批量缓存，提升 10,000+ 资产滚动体验。
- 快速标注：详情页提供 8 个常用标签按钮，点击后立即保存并平滑切换到下一张。
- 手动标注：支持手动输入标签（逗号分隔）。
- 本地离线存储：标签映射保存到 CoreData `AssetEntity(id, tagsRaw, annotatedAt)`。
- 本地搜索：按多标签 AND 逻辑即时过滤。
- 离线导出协议：导出所选资产为 **HEIC + 同名 JSON sidecar** 目录。
- 标签同步：保留标签 JSON 的导入/导出与局域网发送能力。

## 关键权限
在 iOS Target -> Info 中配置：
- `NSPhotoLibraryUsageDescription`：用于读取照片并建立标签索引
- `NSLocalNetworkUsageDescription`：用于发现同一局域网设备并传输标签
- `NSBonjourServices`：添加 `_phototags-sync._tcp`

## 导出目录示例
```text
Export_Batch_20260324/
├── IMG_4567.heic
├── IMG_4567.json
├── IMG_4568.heic
└── IMG_4568.json
```

JSON 示例：
```json
{
  "source_id": "PHAsset_Local_ID",
  "filename": "IMG_4567.heic",
  "tags": ["clay", "texture", "reference"],
  "annotated_at": "2026-03-24T21:00:00Z"
}
```

## 安装与调试
1. 用 Xcode 打开 iOS App 工程（SwiftUI App）。
2. 将本目录 `.swift` 文件加入 target。
3. 将 `../PhotoTagsCore` 作为 Local Package 添加。
4. 在 `Signing & Capabilities` 配置开发者 Team。
5. 真机运行（Linux 环境无法产出签名 IPA）。
