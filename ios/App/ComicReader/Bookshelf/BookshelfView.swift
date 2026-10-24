import SwiftUI
import UniformTypeIdentifiers
import ComicReaderCore

// MARK: - 书架（Bookshelf.tsx 的移植）
//
// 触屏适配：长按卡片 = 右键菜单；「选择」模式承担桌面版的 Ctrl/Shift 多选与批量操作；
// 「打开所在位置」改为分享来源文件（iOS 无文件管理器）。

struct BookshelfView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var covers: CoverStore

    @State private var selecting = false
    @State private var sheet: ShelfSheet?
    @State private var deleteTargets: [String] = []
    @State private var pickerMode: ImportPickerMode?
    @State private var managerDismissedAssignFor: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(
                isSelecting: selecting,
                onToggleSelecting: toggleSelecting,
                onImportFolder: { pickerMode = .folderComic },
                onImportFiles: { pickerMode = .files },
                onImportBatch: { pickerMode = .batchRoot },
                onOpenSettings: { sheet = .settings },
                onLanTransfer: { sheet = .lanTransfer }
            )
            Divider().opacity(0.5)
            content
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .bottom) { selectionBar }
        .overlay(alignment: .bottomTrailing) { importProgressCard }
        .fileImporter(
            isPresented: Binding(
                get: { pickerMode != nil },
                set: { if !$0 { pickerMode = nil } }
            ),
            allowedContentTypes: pickerMode?.contentTypes ?? [.item],
            allowsMultipleSelection: pickerMode == .files
        ) { result in
            let mode = pickerMode
            pickerMode = nil
            handlePickerResult(result, mode: mode)
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .alert(deleteAlertTitle, isPresented: Binding(
            get: { !deleteTargets.isEmpty },
            set: { if !$0 { deleteTargets = [] } }
        )) {
            Button("取消", role: .cancel) { deleteTargets = [] }
            Button("移除", role: .destructive) {
                shelf.remove(deleteTargets)
                deleteTargets = []
                if shelf.selectedIds.isEmpty { selecting = false }
            }
        } message: {
            Text(deleteAlertMessage)
        }
    }

    // MARK: 主体

    @ViewBuilder
    private var content: some View {
        if shelf.loading {
            SkeletonGrid()
        } else if shelf.comics.isEmpty {
            EmptyShelfView(
                onImportFolder: { pickerMode = .folderComic },
                onImportFiles: { pickerMode = .files }
            )
        } else {
            gridBody
        }
    }

    private var gridBody: some View {
        ScrollView {
            if shelf.visible.isEmpty {
                NoResultsView()
                    .padding(.top, 80)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: cardMinWidth), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(shelf.visible) { comic in
                        card(for: comic)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .refreshable {
            shelf.load()
        }
    }

    private var cardMinWidth: CGFloat {
        switch settings.cardSize {
        case .small: return 128
        case .medium: return 160
        case .large: return 200
        }
    }

    @ViewBuilder
    private func card(for comic: Comic) -> some View {
        ComicCardView(
            comic: comic,
            missing: shelf.missingIds.contains(comic.id),
            selectionActive: selecting || shelf.isSelectionActive,
            selected: shelf.selectedIds.contains(comic.id),
            cover: covers.image(for: comic)
        ) {
            handleCardTap(comic)
        }
        .contextMenu {
            contextMenu(for: comic)
        }
    }

    private func handleCardTap(_ comic: Comic) {
        if selecting || shelf.isSelectionActive {
            shelf.toggleSelect(comic.id)
            if shelf.selectedIds.isEmpty, !selecting { return }
        } else {
            Task { await reader.open(id: comic.id) }
        }
    }

    private func toggleSelecting() {
        if selecting {
            selecting = false
            shelf.clearSelection()
        } else {
            selecting = true
        }
    }

    // MARK: 长按菜单（ComicCard.tsx 右键菜单的移植）

    @ViewBuilder
    private func contextMenu(for comic: Comic) -> some View {
        Button {
            Task { await reader.open(id: comic.id, fromStart: true) }
        } label: {
            Label("从第一页开始", systemImage: "play")
        }

        Button {
            sheet = .rename(comic.id)
        } label: {
            Label("重命名…", systemImage: "pencil")
        }

        Button {
            Task { await shelf.rescan([comic.id]) }
        } label: {
            Label("重新扫描（刷新页数和封面）", systemImage: "arrow.clockwise")
        }

        ShareLink(item: URL(fileURLWithPath: comic.sourcePath)) {
            Label("分享来源文件", systemImage: "square.and.arrow.up")
        }

        if settings.extensions.categories {
            Button {
                sheet = .assign(comic.id)
            } label: {
                Label("设置分类…", systemImage: "tag")
            }
        }

        Section("类型标签（决定阅读方式）") {
            ForEach(ComicStyle.allCases, id: \.rawValue) { style in
                Button {
                    // 点已激活的标签 = 摘掉标签
                    shelf.setStyle([comic.id], style: comic.style == style ? nil : style)
                } label: {
                    if comic.style == style {
                        Label(ComicStyleInfo.label(style), systemImage: "checkmark")
                    } else {
                        Text(ComicStyleInfo.label(style))
                    }
                }
            }
        }

        Button {
            selecting = true
            if !shelf.selectedIds.contains(comic.id) {
                shelf.toggleSelect(comic.id)
            }
        } label: {
            Label("选择", systemImage: "checkmark.circle")
        }

        Divider()

        Button(role: .destructive) {
            deleteTargets = [comic.id]
        } label: {
            Label("从书架移除…", systemImage: "trash")
        }
    }

    // MARK: 多选操作条

    @ViewBuilder
    private var selectionBar: some View {
        if shelf.isSelectionActive {
            SelectionBarView(
                onRemove: { deleteTargets = Array(shelf.selectedIds) },
                onExit: {
                    selecting = false
                    shelf.clearSelection()
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: 导入进度（ImportingToast 的移植）

    @ViewBuilder
    private var importProgressCard: some View {
        if shelf.importing.active {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("正在导入 \(shelf.importing.current) / \(shelf.importing.total)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(shelf.importing.path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            )
            .padding(16)
        }
    }

    // MARK: 删除确认文案（对齐 Bookshelf.tsx）

    private var deleteAlertTitle: String { "移除漫画" }

    private var deleteAlertMessage: String {
        if deleteTargets.count == 1, let comic = shelf.comics.first(where: { $0.id == deleteTargets[0] }) {
            return "将从书架移除《\(comic.title)》。原始文件不会被删除，之后可以重新导入。"
        }
        return "将移除选中的 \(deleteTargets.count) 本漫画。原始文件不会被删除，之后可以重新导入。"
    }

    // MARK: 文件选择器

    private func handlePickerResult(_ result: Result<[URL], Error>, mode: ImportPickerMode?) {
        guard let mode else { return }
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            Task {
                switch mode {
                case .files:
                    await model.importFlow.importFiles(urls)
                case .folderComic:
                    if let url = urls.first { await model.importFlow.importFolderAsComic(url) }
                case .batchRoot:
                    if let url = urls.first { await model.importFlow.importFolderAsBatchRoot(url) }
                }
            }
        case .failure:
            // 用户取消不提示
            break
        }
    }

    // MARK: Sheet 路由

    @ViewBuilder
    private func sheetContent(_ sheet: ShelfSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView()
        case .lanTransfer:
            LanTransferView()
        case .rename(let id):
            // 记录已不存在时自动关闭（对齐桌面版「live」解析）
            if shelf.comics.contains(where: { $0.id == id }) {
                RenameSheet(comicId: id)
            }
        case .assign(let id):
            if shelf.comics.contains(where: { $0.id == id }) {
                CategoryAssignSheet(comicId: id, onOpenManager: {
                    managerDismissedAssignFor = id
                    self.sheet = .manager
                })
            }
        case .manager:
            CategoryManagerSheet()
        }
    }
}

// MARK: - 路由与选择器模式

enum ShelfSheet: Identifiable {
    case settings
    case lanTransfer
    case rename(String)
    case assign(String)
    case manager

    var id: String {
        switch self {
        case .settings: return "settings"
        case .lanTransfer: return "lan-transfer"
        case .rename(let id): return "rename-\(id)"
        case .assign(let id): return "assign-\(id)"
        case .manager: return "manager"
        }
    }
}

enum ImportPickerMode: Equatable {
    case folderComic
    case files
    case batchRoot

    var contentTypes: [UTType] {
        switch self {
        case .folderComic, .batchRoot:
            return [.folder]
        case .files:
            var types: [UTType] = [.zip, .pdf]
            for ext in ["cbz", "cbr", "rar"] {
                if let type = UTType(filenameExtension: ext) {
                    types.append(type)
                }
            }
            return types
        }
    }
}

// MARK: - 骨架屏与空状态（ShelfStates.tsx 的移植）

struct SkeletonGrid: View {
    @State private var pulsing = false

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                spacing: 16
            ) {
                ForEach(0..<12, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemFill))
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(uiColor: .secondarySystemFill))
                            .frame(height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(uiColor: .secondarySystemFill))
                            .frame(width: 80, height: 11)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .opacity(pulsing ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
        .onAppear { pulsing = true }
    }
}

struct EmptyShelfView: View {
    let onImportFolder: () -> Void
    let onImportFiles: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("书架还是空的")
                .font(.system(size: 16, weight: .semibold))
            Text("把漫画放进 App 的「文件」目录，或直接导入")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    onImportFolder()
                } label: {
                    Label("导入文件夹", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    onImportFiles()
                } label: {
                    Label("导入文件", systemImage: "doc.zipper")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct NoResultsView: View {
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    private var message: String {
        let query = shelf.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return "没有找到「\(query)」"
        }
        if let filter = shelf.styleFilter {
            if filter == ShelfStore.unstyledId { return "每本漫画都已标记类型" }
            let label = ComicStyle(rawValue: filter).map { ComicStyleInfo.label($0) } ?? filter
            return "还没有标为「\(label)」的漫画"
        }
        if let filter = shelf.categoryFilter {
            if filter == ShelfStore.uncategorizedId { return "没有未分类的漫画" }
            let name = shelf.categories.first { $0.id == filter }?.name ?? "该"
            return "「\(name)」分类下还没有漫画"
        }
        return "没有结果"
    }

    private var hint: String {
        if !shelf.query.trimmingCharacters(in: .whitespaces).isEmpty {
            return "试试别的关键词，或清空搜索"
        }
        return "换个筛选条件看看"
    }
}
