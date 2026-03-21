# PhotoTags iOS App (SwiftUI)

这是可安装到 iPhone 的测试版源码（需在 macOS + Xcode 16+ 构建）。

## 功能
- 读取系统相册（PhotoKit）
- 给照片添加自定义标签（标签独立保存，不写回系统相册）
- 按标签 AND 搜索
- 导出/导入同步 JSON（文件）
- 局域网设备发现 + 一键发送标签数据（参考 LocalSend 的同网段直传思路）

## 如何在 iOS 真机安装测试版
1. 在 Mac 上用 Xcode 新建一个 iOS App（名字建议 `PhotoTagsApp`，SwiftUI + Swift）。
2. 将本目录下 `.swift` 文件拷入项目。
3. 将 `../PhotoTagsCore` 作为 Local Package 添加到 Xcode。
4. 在 target 的 `Signing & Capabilities` 里配置你的 Team。
5. 在 `Info` 添加以下权限项：
   - `NSPhotoLibraryUsageDescription`：用于读取照片并建立标签索引
   - `NSLocalNetworkUsageDescription`：用于发现同一局域网设备并传输标签
   - `NSBonjourServices`：添加 `_phototags-sync._tcp`
6. 连接 iPhone，选择真机目标，`Run` 即可安装 Debug 测试版。

## 局域网传输说明
- 双方都打开 app，并进入主页面（会自动开启发现）。
- 在“局域网传输”区域看到对方设备后，点击“发送标签”。
- 接收端会自动合并标签（优先 `sha256`，其次 `original_name`）。

> 说明：本仓库运行环境是 Linux，无法直接产出签名 IPA；但源码已可在 Xcode 中编译并安装测试。
