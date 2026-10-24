import Foundation
import SwiftUI
import ComicReaderCore

// MARK: - 应用根对象（组合根 + 启动流程，对齐 App.tsx 的 boot 顺序）
//
// 启动：加载数据库 → 加载设置 → 加载书架 → （可选）打开上次阅读 → 延迟 1200ms 扫描库目录
// 生命周期：进入后台/退出前落盘 + 释放压缩包句柄（对齐 before-quit 的 flushSync + closeAllSources）

/// 默认封面工厂：走 Core 的 ImagePipeline（480px JPEG q0.82）
struct DefaultCoverFactory: CoverMaking {
    func makeCover(fromPageData data: Data) -> Data? {
        ImagePipeline.makeCover(from: data)
    }
}

@MainActor
final class AppModel: ObservableObject {
    let paths: AppPaths
    let db: LibraryDatabase
    let settings: SettingsStore
    let covers: CoverStore
    let pages: PageProvider
    let importer: Importer
    let shelf: ShelfStore
    let reader: ReaderStore
    let toasts: ToastCenter
    let importFlow: ImportFlow
    let transfer: LanTransferModel

    @Published private(set) var booted = false

    init() {
        let paths = AppPaths.live()
        paths.ensureDirectories()

        let db = LibraryDatabase(paths: paths)
        let toasts = ToastCenter()
        let settings = SettingsStore(db: db)
        let covers = CoverStore(coversDir: paths.coversDir)
        let pages = PageProvider()
        let importer = Importer(db: db, coversDir: paths.coversDir, coverFactory: DefaultCoverFactory())
        let shelf = ShelfStore(db: db, settings: settings, importer: importer, covers: covers, toasts: toasts)
        let reader = ReaderStore(db: db, settings: settings, pages: pages)
        let importFlow = ImportFlow(paths: paths, shelf: shelf, toasts: toasts)
        let transfer = LanTransferModel(
            paths: paths,
            db: db,
            shelf: shelf,
            toasts: toasts
        )

        self.paths = paths
        self.db = db
        self.settings = settings
        self.covers = covers
        self.pages = pages
        self.importer = importer
        self.shelf = shelf
        self.reader = reader
        self.toasts = toasts
        self.importFlow = importFlow
        self.transfer = transfer
    }

    /// 启动流程（幂等；ContentView 的 .task 调用）
    func boot() async {
        guard !booted else { return }
        db.load()
        settings.load()
        shelf.load()
        booted = true

        // 启动时打开上次阅读的漫画（对齐 App.tsx 的 openLastOnStartup）
        if settings.settings.openLastOnStartup,
           let lastId = settings.settings.lastOpenedComicId,
           db.getComic(id: lastId) != nil {
            await reader.open(id: lastId)
        }

        // 延迟 1.2s 自动扫描库目录（对齐 App.tsx 40 行；阅读中不打扰）
        if settings.settings.autoScanRoots, !settings.settings.libraryRoots.isEmpty {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !reader.active {
                await shelf.scanRoots(silent: true)
            }
        }
    }

    /// 场景生命周期（对齐桌面版 before-quit：flushSync + closeAllSources）
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            reader.flushPersist()
            db.flushSync()
            closeAllSources()
            pages.clearAll()
            // iOS 会挂起进程，局域网监听留着也收不到包
            transfer.handleBackground()
        case .inactive:
            reader.flushPersist()
            db.flushSync()
        default:
            break
        }
    }
}
