# 漫画阅读器（ComicReader）

基于 **Electron + React + TypeScript** 的 Windows 本地漫画阅读软件。完全离线运行，不依赖任何后端服务。

## 功能

- **导入**：本地文件夹 / ZIP / CBZ（多选、拖拽入窗口、批量导入子文件夹），识别 jpg / jpeg / png / webp / gif，自动取第一页生成封面，页码按自然顺序排列（1、2、10）
- **书架**：封面网格（虚拟滚动，数千本不卡）、阅读进度、最近阅读时间、搜索（Ctrl+F）、排序、卡片大小三档；来源丢失自动标记；右键菜单：从头读 / 重新扫描 / 打开位置 / 移除（不删原文件）
- **阅读器**：单页 / 双页 / 连续滚动，适应宽度 / 适应高度 / 原始大小 + 自由缩放，LTR / RTL 阅读方向，工具栏自动隐藏，相邻页预解码、可视区按需挂载，放大后可拖拽平移
- **进度**：每本漫画自动记住页码与阅读偏好（模式 / 缩放 / 方向），重开自动续读
- **设置**：浅色 / 深色 / 跟随系统主题、默认模式与缩放、启动时打开上次漫画
- **健壮性**：数据 schema 版本化 + 自动迁移（迁移前自动备份）、权限 / 占用 / 丢失等 IO 错误友好提示、窗口位置记忆、主进程日志（`logs/main.log`，自动轮转）

### 快捷键（阅读器内）

| 按键 | 功能 |
| --- | --- |
| ← / → | 翻页（尊重阅读方向） |
| 空格 / Shift+空格 | 下一页 / 上一页（滚动模式为滚屏） |
| PgUp / PgDn / Home / End | 翻页 / 跳到首末页 |
| F / F11 | 全屏 |
| Esc | 退出全屏 / 返回书架 |
| + / − / 0 | 放大 / 缩小 / 重置缩放（也可 Ctrl+滚轮） |
| 1 / 2 / 3 | 单页 / 双页 / 连续滚动 |

## 开发

```bash
npm install        # 安装依赖（会下载 Electron，国内网络可先设置镜像，见下）
npm run dev        # 启动开发环境（热更新）
npm run typecheck  # TypeScript 类型检查
npm test           # 单元测试（vitest）
```

国内网络加速 Electron 下载：

```bash
# PowerShell
$env:ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/"
npm install
```

## 打包 Windows 应用

```bash
npm run build:win     # 输出 NSIS 安装包 + 便携版到 release/<版本号>/
npm run build:unpack  # 只输出未打包目录（调试用）
```

产物：

- `ComicReader Setup <版本>.exe` —— NSIS 安装包（可选安装目录，按用户安装）
- `ComicReader <版本>.exe` —— 便携版单文件，免安装直接运行

打包配置说明（package.json 的 `build` 字段）：

- `electronDist` 已指向 `node_modules/electron/dist`，打包直接复用本地已下载的
  Electron，不再从 GitHub 下载（国内网络必备，也保证与开发运行的版本一致）
- NSIS 等打包工具下载慢/失败时，设置镜像后重试：
  `ELECTRON_BUILDER_BINARIES_MIRROR=https://npmmirror.com/mirrors/electron-builder-binaries/`
- 首次打包若报 `Cannot create symbolic link`（winCodeSign 解压失败）：
  是 Windows 创建符号链接需要特权所致，开启系统「开发者模式」后重试即可
  （出错的只是包内 macOS 文件的符号链接，Windows 打包并不使用它们）
- 应用图标由 `node scripts/gen-icon.js` 生成到 `build/icon.png`，
  想换图标直接替换该文件（≥256×256）后重新打包
- 安装包未做代码签名，首次运行会有 SmartScreen 提示（点“仍要运行”）；
  正式发布可购买代码签名证书并配置 `win.certificateFile`

如需自定义图标，放置 `build/icon.ico`（256×256 以上）后重新打包。

## 项目结构

```
src/
├── shared/              # 主/渲染进程共享的类型与 IPC 契约
│   ├── types.ts         # Comic、AppSettings 等数据结构
│   ├── ipc.ts           # IPC 通道名
│   └── api.ts           # window.api 的类型定义
├── main/                # Electron 主进程
│   ├── index.ts         # 生命周期、窗口、安全策略（拒绝导航/弹窗/权限）
│   ├── protocol.ts      # comic:// 协议：按需把图片流给 <img>（含路径越界防护）
│   ├── archive.ts       # 文件夹/ZIP 扫描与按页读取（句柄缓存、errno 友好化）
│   ├── importer.ts      # 导入流程（去重、页数统计、封面、批量展开）
│   ├── thumbnail.ts     # nativeImage 封面缩略图
│   ├── ipc.ts           # 所有 IPC handler（入参校验）
│   ├── store/           # 持久化
│   │   ├── db.ts        # library.json（原子写、防抖落盘、损坏自愈）
│   │   ├── migrations.ts# schema 版本迁移管线（纯函数，可单测）
│   │   └── windowState.ts # 窗口大小/位置记忆（含多显示器校验）
│   ├── lib/logger.ts    # 文件日志（自动轮转）
│   └── utils/           # 自然排序、图片扩展名/MIME
├── preload/             # contextBridge 暴露类型安全的 window.api
└── renderer/src/        # React 界面
    ├── store/           # zustand：settings / library / reader / ui
    ├── pages/           # Bookshelf 书架、Reader 阅读器
    ├── components/      # bookshelf / reader / common（含 ErrorBoundary）
    ├── hooks/           # useVirtualGrid / useAutoHide / useClickOutside
    ├── lib/pageCache.ts # 相邻页预解码 LRU 缓存
    └── styles/          # 全局样式与明暗主题变量
tests/unit/              # vitest 单元测试（排序/迁移/格式化/文件识别）
```

## 数据存储与迁移

数据保存在 `%APPDATA%/comic-reader/`：

- `library.json` —— 漫画列表、阅读进度、全局设置（写临时文件后改名，保证原子性）
- `covers/` —— 封面缩略图
- `window-state.json` —— 窗口大小与位置
- `logs/main.log` —— 主进程日志（>2MB 自动轮转）

数据结构带 `version` 字段。升级应用后首次启动会按 `src/main/store/migrations.ts`
中的管线逐级迁移，迁移前自动把原文件备份为 `library.json.v<N>.bak`；
解析失败的损坏文件会备份为 `library.json.corrupt-<时间戳>` 并以空库启动。
新增字段时：`CURRENT_SCHEMA_VERSION` +1，添加一步迁移函数，补一条单测即可。

## 发布新版本（GitHub）

仓库已配置 GitHub Actions（`.github/workflows/`）：

- **CI**：推送 / PR 自动跑类型检查、单元测试、构建
- **Release**：推送 `v*` 标签自动在 Windows 环境打包，并把安装包/便携版上传到 GitHub Release

发布流程：

```bash
# 1. 更新 package.json 的 version（如 0.3.0），提交
git commit -am "release: v0.3.0"

# 2. 打标签并推送 —— 这一步触发自动打包发布
git tag v0.3.0
git push origin main v0.3.0
```

Actions 跑完后，到仓库 Releases 页把自动生成的 **draft** 检查、编写更新说明后点击 Publish。
（electron-builder 默认建草稿 Release，避免半成品直接公开。）

## 性能设计

- **图片不走 IPC**：主进程注册 `comic://` 协议，`<img>` 直接按页请求，
  主进程从磁盘或压缩包按需流式返回（ZIP 句柄 LRU 缓存，空闲自动关闭）
- **阅读器**：翻页模式用 `img.decode()` 提前解码相邻页（解码不阻塞主线程）；
  滚动模式用 IntersectionObserver 只挂载视口附近约 4 屏、远处卸载并保留占位高度
- **书架**：自研虚拟滚动网格（固定 3:4 封面比例 → 行高可精确计算），
  上千本漫画时 DOM 始终只有几十个卡片；搜索输入防抖、卡片 memo 化
- **来源校验**：分批 stat（并发 24），窗口聚焦时节流复查
