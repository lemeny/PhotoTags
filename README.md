# PhotoTags

一个轻量本地图片标签工具：
- 给 meme 和其他照片添加多个自定义标签（手动输入，逗号分隔）
- 支持 iOS 常见 HEIC/HEIF 照片上传（自动转为 JPEG，方便 Windows 浏览）
- 基于标签筛选展示照片（支持多选，按“同时包含”筛选）
- 面向大量数据做了分页与索引优化（如 1 万张图片场景）
- 标签数据可导出/导入为同步文件，适合 iOS 与 Windows 间通过 USB / iCloud Drive / U 盘等方式离线互通

## 快速开始（Windows / macOS / Linux）

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

浏览器访问：`http://127.0.0.1:5000`

> 默认仅监听本机 `127.0.0.1`，不需要部署网络服务器。

## iOS + Windows 离线同步流程（推荐）

1. 在任意一端（例如 Windows）用 PhotoTags 完成标签操作。
2. 导出标签同步文件：
   ```bash
   python app.py --export-sync sync/phototags_sync.json
   ```
3. 通过你自己的硬件/文件同步方式（USB、iCloud Drive、OneDrive、U 盘）把 `sync/phototags_sync.json` 复制到另一端。
4. 在另一端导入并合并标签：
   ```bash
   python app.py --import-sync sync/phototags_sync.json
   ```

### 互通细节
- 同步文件会携带每张图片的 SHA-256 指纹和标签。
- 导入时优先按图片指纹合并标签，即使图片文件名变化也能尽量匹配。

## Windows 一键启动

双击 `run_windows.bat`：会自动创建虚拟环境、安装依赖并启动应用。

## 技术实现

- Flask + SQLite
- Pillow + pillow-heif（HEIC/HEIF 转换）
- 图片文件存储在 `uploads/`
- 数据存储在 `phototags.db`


## 大量图片性能说明

- 页面默认分页（每页 120 张），避免一次渲染上万条记录。
- 筛选查询建立了 `photo_tags(tag_id, photo_id)`、`photo_tags(photo_id, tag_id)`、`photos(created_at)` 索引。
- 当前页只加载该页图片对应的标签，不再全量扫描所有图片标签。
