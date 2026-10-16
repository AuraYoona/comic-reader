import Foundation
import UIKit
import ComicReaderCore

// MARK: - 导入入口（把文档选择器选中的内容复制进沙盒再导入）
//
// iOS 沙盒规则：文档选择器返回的 URL 需要安全作用域访问，且退出即失效；
// 「来源丢失」在沙盒里几乎只剩用户从「文件」App 手动删文件这一种情况。
// 因此导入 = 复制进 Documents/Comics/ 后就地导入；之后一切读写都在沙盒内。
//
// 桌面版三种入口的对应关系：
//   - 导入文件夹…        → 选目录 → 整树复制 → 作为 folder 漫画导入
//   - 导入文件…          → 选压缩包/PDF（可多选）→ 复制 → 逐本导入
//   - 批量导入子文件夹…  → 选目录 → 整树复制 → 记为库根 → 每个一级子项各导入一本

@MainActor
final class ImportFlow {
    private let paths: AppPaths
    private let shelf: ShelfStore
    private let toasts: ToastCenter

    init(paths: AppPaths, shelf: ShelfStore, toasts: ToastCenter) {
        self.paths = paths
        self.shelf = shelf
        self.toasts = toasts
    }

    /// 导入文件（压缩包 / PDF，可多选）
    func importFiles(_ urls: [URL]) async {
        var destinations: [String] = []
        for url in urls {
            if let dest = copyIntoLibrary(url) {
                destinations.append(dest)
            }
        }
        guard !destinations.isEmpty else { return }
        await shelf.importPaths(destinations)
    }

    /// 导入一个文件夹作为一本漫画（整树复制）
    func importFolderAsComic(_ url: URL) async {
        guard let dest = copyIntoLibrary(url) else { return }
        await shelf.importPaths([dest])
    }

    /// 批量导入：选中的目录整体复制成库根，每个一级子项（子文件夹 / 压缩包）各导入一本
    func importFolderAsBatchRoot(_ url: URL) async {
        guard let dest = copyIntoLibrary(url) else { return }
        await shelf.importBatchRoot(dest)
    }

    /// 从「文件」App 拖入 / 打开方式进来的文件（onOpenURL）
    func importIncoming(url: URL) async {
        await importFiles([url])
    }

    // MARK: 复制

    /// 把一个外部 URL 复制进 Documents/Comics/，返回沙盒内新路径
    /// （重名时追加 " (2)" 等序号；失败提示并返回 nil）
    private func copyIntoLibrary(_ url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()

        let fm = FileManager.default
        let name = url.lastPathComponent.isEmpty ? "未命名" : url.lastPathComponent
        let destPath = uniqueDestination(for: name)

        do {
            try fm.copyItem(at: url, to: URL(fileURLWithPath: destPath))
            if scoped { url.stopAccessingSecurityScopedResource() }
            return destPath
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            toasts.show(.error, "复制「\(name)」失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 目标重名时追加序号（a.cbz → a (2).cbz）
    private func uniqueDestination(for name: String) -> String {
        let fm = FileManager.default
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = (paths.comicsDir as NSString).appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: candidate) {
            let fileName = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = (paths.comicsDir as NSString).appendingPathComponent(fileName)
            n += 1
        }
        return candidate
    }
}
