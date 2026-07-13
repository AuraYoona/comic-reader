<div align="center">

# 📖 ComicReader 漫画阅读器

一款 Windows 桌面端本地漫画阅读器 —— 完全离线，简洁流畅，专注阅读体验。

![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20x64-0078d4)
![Electron](https://img.shields.io/badge/Electron-31-47848f)
![React](https://img.shields.io/badge/React-18-61dafb)
![TypeScript](https://img.shields.io/badge/TypeScript-5-3178c6)
![Tests](https://img.shields.io/badge/tests-vitest%20%C3%97%2023-6e9f18)
![License](https://img.shields.io/badge/license-MIT-green)

**[下载最新版本 →](https://github.com/AuraYoona/comic-reader/releases)**

</div>

---

## ✨ 特性一览

### 📥 导入
- 支持**本地文件夹**与 **ZIP / CBZ 压缩包**，可多选、可直接**拖拽进窗口**
- **批量导入**：选择一个根目录，每个子文件夹 / 压缩包自动作为一本漫画
- 识别 `jpg` `jpeg` `png` `webp` `gif`，页码**自然排序**（`1, 2, 10` 而非 `1, 10, 2`）
- 自动提取第一页生成封面缩略图；按路径去重；单项失败不影响其余项

### 📚 书架
- **虚拟滚动网格** —— 数千本漫画依然流畅，DOM 中始终只有可视区的几十张卡片
- 搜索（`Ctrl+F`，输入防抖）、排序（最近阅读 / 名称 / 导入时间）、卡片大小三档
- 卡片显示封面、页数、阅读百分比、最近阅读时间；**来源丢失**自动标记
- 右键菜单：从第一页开始 / 重新扫描（刷新页数与封面）/ 打开所在位置 / 移除
- 移除只删记录，**永远不动原文件**

### 📖 阅读器
- **单页 / 双页 / 连续滚动**三种模式，随时切换（`1` `2` `3`）
- **适应宽度 / 适应高度 / 原始大小** + 自由缩放（25%–400%，`Ctrl+滚轮`）
- **从左到右 / 从右到左**阅读方向（日漫友好，双页自动交换左右）
- 相邻页**提前解码**，翻页零白屏；滚动模式只挂载视口附近页面，长篇不占内存
- 工具栏自动隐藏、点击左右分区翻页、放大后**按住拖拽平移**、滚轮到页面边缘才翻页
- 全屏阅读（`F`），进度滑块快速跳页

### 💾 进度与设置
- 每本漫画独立记住**页码 + 阅读模式 + 缩放 + 方向**，重新打开自动续读
- 全局设置：浅色 / 深色 / 跟随系统主题、默认阅读模式与缩放、启动时打开上次阅读
- 数据结构**版本化 + 自动迁移**，升级应用不丢数据（迁移前自动备份）

## ⌨️ 快捷键

| 按键 | 功能 |
| --- | --- |
| `←` `→` | 上一页 / 下一页（尊重阅读方向） |
| `空格` / `Shift+空格` | 下一页 / 上一页（滚动模式为滚屏） |
| `↑` `↓` `PgUp` `PgDn` | 翻页 / 滚屏 |
| `Home` / `End` | 第一页 / 最后一页 |
| `1` `2` `3` | 单页 / 双页 / 连续滚动 |
| `+` `−` `0` | 放大 / 缩小 / 重置缩放 |
| `F` / `F11` | 全屏切换 |
| `Esc` | 退出全屏 / 返回书架 |
| `Ctrl+F`（书架） | 聚焦搜索框 |

## 📦 安装

到 [Releases](https://github.com/AuraYoona/comic-reader/releases) 页面下载：

| 文件 | 说明 |
| --- | --- |
| `ComicReader-Setup-x.y.z.exe` | 安装版，可选安装目录，含卸载器 |
| `ComicReader-x.y.z.exe` | 便携版，免安装单文件，随处运行 |

> 安装包未做代码签名，首次运行如遇 SmartScreen 提示，点「更多信息 → 仍要运行」。

用户数据保存在 `%APPDATA%/comic-reader/`，卸载重装不丢失：

```
library.json        漫画列表、阅读进度、全局设置（原子写入，损坏自动备份重建）
covers/             封面缩略图
window-state.json   窗口大小与位置
logs/main.log       主进程日志（>2MB 自动轮转）
```

## 🛠️ 开发

```bash
git clone https://github.com/AuraYoona/comic-reader.git
cd comic-reader
npm install          # 国内网络建议先设置 Electron 镜像，见下
npm run dev          # 开发环境（热更新，F12 开调试器）
npm run typecheck    # TypeScript 类型检查（主进程 + 渲染层双配置）
npm test             # vitest 单元测试
```

国内网络加速 Electron 下载：

```powershell
$env:ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/"
npm install
```

### 打包 Windows 应用

```bash
npm run build:win     # NSIS 安装包 + 便携版 → release/<版本号>/
npm run build:unpack  # 仅输出未压缩目录（调试用）
```

- 打包配置在 `package.json` 的 `build` 字段；`electronDist` 指向本地
  `node_modules/electron/dist`，**不再从 GitHub 下载**，且保证与开发版本一致
- NSIS 工具下载慢时设置：
  `ELECTRON_BUILDER_BINARIES_MIRROR=https://npmmirror.com/mirrors/electron-builder-binaries/`
- 首次打包若报 `Cannot create symbolic link`：开启 Windows「开发者模式」后重试
  （出错的只是工具包内 macOS 符号链接，Windows 打包并不使用）
- 应用图标由 `node scripts/gen-icon.js` 生成到 `build/icon.png`，替换该文件即可换图标

### 发布新版本

仓库配置了 GitHub Actions：**CI**（推送 / PR 自动跑类型检查、测试、构建）与
**Release**（推 `v*` 标签自动在 Windows 环境打包并上传 Release 草稿）。

```bash
# 1. 更新 package.json 的 version，提交
git commit -am "release: v0.3.0"

# 2. 打标签推送，触发云端自动打包
git tag v0.3.0
git push origin main v0.3.0

# 3. Actions 完成后检查 Release 草稿并发布
gh release edit v0.3.0 --draft=false
```

## 🏗️ 架构

```
src/
├── shared/                  # 主/渲染进程共享契约（改这里，两端类型同步）
│   ├── types.ts             #   Comic、AppSettings、枚举等数据结构
│   ├── ipc.ts               #   IPC 通道名常量
│   └── api.ts               #   window.api 接口定义
├── main/                    # Electron 主进程
│   ├── index.ts             #   生命周期、窗口、安全策略
│   ├── protocol.ts          #   comic:// 自定义协议（图片按需流式返回）
│   ├── archive.ts           #   文件夹/ZIP 统一抽象：扫描、按页读取、句柄缓存
│   ├── importer.ts          #   导入流程：去重、计页、封面、批量展开
│   ├── thumbnail.ts         #   nativeImage 封面缩略图（无原生依赖）
│   ├── ipc.ts               #   全部 IPC handler（入参校验）
│   ├── store/
│   │   ├── db.ts            #   library.json：防抖 + 原子写 + 损坏自愈
│   │   ├── migrations.ts    #   schema 迁移管线（纯函数，可单测）
│   │   └── windowState.ts   #   窗口位置记忆（多显示器越界校验）
│   ├── lib/logger.ts        #   文件日志（2MB 自动轮转）
│   └── utils/               #   自然排序、图片类型/MIME
├── preload/index.ts         # contextBridge 暴露类型安全的 window.api
└── renderer/src/            # React 界面
    ├── pages/               #   Bookshelf 书架 / Reader 阅读器
    ├── components/          #   bookshelf / reader / common 组件
    ├── store/               #   zustand：settings / library / reader / ui
    ├── hooks/               #   useVirtualGrid / useAutoHide / useClickOutside
    ├── lib/pageCache.ts     #   相邻页预解码 LRU
    └── styles/global.css    #   明暗主题 CSS 变量
tests/unit/                  # vitest：排序 / 迁移 / 格式化 / 文件识别
.github/workflows/           # CI + tag 自动发布
```

### 关键设计

| 问题 | 方案 |
| --- | --- |
| 大图传输卡顿 | 图片**不走 IPC**：主进程注册 `comic://` 协议，`<img>` 按页请求，磁盘/压缩包字节直接流式返回 |
| 翻页白屏 | 相邻页用 `img.decode()` **预解码**进 Chromium 图像缓存（LRU 32 张，淘汰即中断请求） |
| 长篇滚动爆内存 | IntersectionObserver 只挂载视口 ±2 屏，远处卸载并保留占位高度 |
| 书架万卡渲染 | 自研虚拟网格：封面固定 3:4 + 标题固定两行 → 行高精确可算，只渲染可视行 |
| 压缩包反复开销 | ZIP 句柄 LRU 缓存（上限 4 个，空闲 60s 自动关闭），单条目按需解压 |
| 数据安全 | 写临时文件再改名（原子性）+ 退出强制落盘 + 解析失败备份自愈 + 版本化迁移 |
| 进程安全 | sandbox + contextIsolation + CSP + 拒绝一切导航/弹窗/Web 权限 + 封面路径越界防护 |

## 🗺️ Roadmap

- [ ] RAR / CBR、PDF 支持
- [ ] 双页模式封面单独显示（首页对齐）
- [ ] 标签 / 分组、批量管理
- [ ] 书签与阅读历史
- [ ] 缩略图快速跳页条
- [ ] 自动更新（electron-updater，Release 已附带 latest.yml）

## 📄 License

[MIT](LICENSE)
