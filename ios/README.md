# ComicReader iOS 版

桌面版（Electron）的 iOS 原生移植：**SwiftUI 重写界面，Core 层从 TypeScript 逐行移植**，
数据和备份格式与桌面版完全互通（`library.json` schema v5）。

## 结构

```
ios/
  ComicCore/                # SwiftPM 包 ComicReaderCore —— 纯逻辑 + 服务层（可在 macOS 上跑测试）
    Sources/ComicReaderCore/
      Logic/                # 双页配对 / 裁白边数学 / 自然排序 / 格式判定（shared/*.ts 的移植）
      Models/               # Comic / AppSettings / Category / LibraryFile（字段名与 library.json 一致）
      Store/                # schema v5 迁移、净化、两档防抖落盘、原子写
      Archive/              # 四操作读取契约 + LRU 句柄缓存 + ZIP / RAR / PDF 适配器
      Import/               # 导入器（判类型 / 查重 / 扫页 / 封面）
      Backup/               # 备份导出 / 合并恢复 / 覆盖恢复 + zip 交付
      Platform/             # ImagePipeline：封面 480px q0.82、缩略图 180px q0.70、降采样、裁边采样
    Tests/ComicReaderCoreTests/   # 移植自桌面版 tests/unit 的 XCTest
  Vendor/UnrarKitLocal/     # vendored 官方 UnRAR 6.12（RAR4 + RAR5）+ URKArchive 包装
  App/                      # SwiftUI App（工程文件由 XcodeGen 生成，不入库）
    project.yml
    ComicReader/
```

## 没有 Mac 怎么开发

- **写代码**：全部在 Windows 上完成（本仓库的日常开发环境）。
- **本机类型门禁**（Swift for Windows + MSVC）：

  ```
  npm run swift:check
  ```

  对 `ios/ComicCore` 做整包 `-typecheck`（源码 + XCTest），能在推送前抓出全部编译错误。
  Windows 上跑不了 XCTest（无模拟器），测试运行交给 CI。

- **构建**：推送到 `main`（改动 `ios/**`）或手动触发 GitHub Actions 的 **iOS** workflow：
  1. `core-tests`：macOS runner 上 `swift test`（移植逻辑的完整验证）
  2. `build-ipa`：XcodeGen 生成工程 → 未签名 archive → 组装 `ComicReader-unsigned.ipa`
  3. 打 `v*` 标签时 IPA 会自动附到与桌面版同一个 GitHub Release（草稿）

## 侧载安装（免费 Apple ID）

1. 到 Actions 的 `build-ipa` 任务里下载 **ComicReader-unsigned-ipa** 工件（或用 `v*` 标签的 Release 附件）。
2. 在 Windows 上用 [Sideloadly](https://sideloadly.io) 或 [AltStore](https://altstore.io)
   （AltServer for Windows + 官网版 iTunes/iCloud 组件）以 Apple ID 重签安装。
3. 免费账号签名的 App **7 天过期**：到期后重新拖 IPA 签一次即可；
   想免电脑续签可以用 [SideStore](https://sidestore.io)（一次性配对后可在设备上重签）。
   免费账号同时最多 3 个自签 App、每 7 天最多 10 个 App ID。

## 把漫画放进来（三种方式）

- 书架顶栏「导入」：
  - **导入文件夹…** 选一个文件夹 = 一本漫画（整树复制进沙盒）
  - **导入文件…** 选 ZIP / CBZ / RAR / CBR / PDF（可多选）
  - **批量导入子文件夹…** 选一个目录 = 库根，每个一级子项各一本；之后把这个目录里
    新加的漫画放进「文件」App，启动时会自动扫描上架（设置里可关）
- 电脑连接：在「文件」App（或 Finder / iTunes 文件共享）里把漫画拖进
  `ComicReader/Comics/`，然后在书架里下拉刷新或去设置里点「立即扫描」。
- 分享打开：在「文件」App 里长按压缩包 → 共享 → 用 ComicReader 打开，自动导入。

## 与桌面版的行为差异（有意为之）

| 桌面 | iOS |
| --- | --- |
| 全局文件系统 | 沙盒：导入即复制进 `Documents/Comics/`（「来源丢失」只剩手动删文件一种情况） |
| 右键菜单 / Ctrl、Shift 多选 | 长按菜单 + 顶栏「选择」模式 |
| 鼠标侧键 / 滚轮边缘翻页 / Ctrl±滚轮 | 三分区点按、捏合缩放、（iPad 键盘可后续补） |
| 桌面全屏 / 窗口状态 / 自动更新 | 不存在；升级 = 重签新版 IPA |
| 封面两段式（原图直存 + canvas 重压） | ImageIO 单阶段直接生成 480px JPEG |

其余阅读行为（双页配对与跨页大图、裁白边、跨页图独立成屏、条漫平滑滚动 10–400 px/s、
自动翻页 2–60s、末页两次触发返回书架、进度防抖与落盘、备份合并/覆盖语义）均与桌面版对齐，
常量逐一对齐（见各文件注释与 Core 测试）。
