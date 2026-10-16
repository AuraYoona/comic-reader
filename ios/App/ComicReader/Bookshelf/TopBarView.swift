import SwiftUI
import ComicReaderCore
import UIKit

// MARK: - 书架顶栏（TopBar.tsx 的移植：搜索 / 分类 / 类型 / 排序 / 导入 / 设置）

struct TopBarView: View {
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var settings: SettingsStore

    let isSelecting: Bool
    let onToggleSelecting: () -> Void
    let onImportFolder: () -> Void
    let onImportFiles: () -> Void
    let onImportBatch: () -> Void
    let onOpenSettings: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 9) {
            titleRow
            searchRow
            filterRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(.bar)
    }

    // MARK: 标题行

    private var titleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "book")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("漫画书架")
                .font(.system(size: 18, weight: .semibold))

            Spacer()

            Button {
                onToggleSelecting()
            } label: {
                Text(isSelecting ? "完成" : "选择")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelecting ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                cycleTheme()
            } label: {
                Image(systemName: currentThemeIcon)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func cycleTheme() {
        // 桌面版是「浅色 ↔ 深色」切换按钮
        let effective: ThemeMode
        if settings.settings.theme == .system {
            effective = UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
        } else {
            effective = settings.settings.theme
        }
        settings.update { $0.theme = effective == .dark ? .light : .dark }
    }

    private var currentThemeIcon: String {
        switch settings.settings.theme {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system:
            return UITraitCollection.current.userInterfaceStyle == .dark ? "moon" : "sun.max"
        }
    }

    // MARK: 搜索行

    private var searchRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            TextField("搜索漫画…", text: $shelf.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !shelf.searchText.isEmpty {
                Button {
                    shelf.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }

    // MARK: 筛选行

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if settings.extensions.categories {
                    categoryMenu
                }
                styleMenu
                sortMenu

                Spacer(minLength: 8)

                importMenu
            }
            .padding(.horizontal, 1)
        }
    }

    private var categoryMenu: some View {
        Menu {
            Picker("分类", selection: $shelf.categoryFilter) {
                Text("全部").tag(String?.none)
                Text("未分类").tag(String?.some(ShelfStore.uncategorizedId))
                ForEach(shelf.categories) { category in
                    Text(category.name).tag(String?.some(category.id))
                }
            }
        } label: {
            filterLabel(
                "分类",
                value: selectedCategoryName,
                active: shelf.categoryFilter != nil
            )
        }
    }

    private var selectedCategoryName: String {
        guard let filter = shelf.categoryFilter else { return "全部" }
        if filter == ShelfStore.uncategorizedId { return "未分类" }
        return shelf.categories.first { $0.id == filter }?.name ?? "全部"
    }

    private var styleMenu: some View {
        Menu {
            Picker("类型", selection: $shelf.styleFilter) {
                Text("全部").tag(String?.none)
                Text("未标记").tag(String?.some(ShelfStore.unstyledId))
                ForEach(ComicStyle.allCases, id: \.rawValue) { style in
                    Text(ComicStyleInfo.label(style)).tag(String?.some(style.rawValue))
                }
            }
        } label: {
            filterLabel(
                "类型",
                value: selectedStyleName,
                active: shelf.styleFilter != nil
            )
        }
    }

    private var selectedStyleName: String {
        guard let filter = shelf.styleFilter else { return "全部" }
        if filter == ShelfStore.unstyledId { return "未标记" }
        return ComicStyle(rawValue: filter).map { ComicStyleInfo.label($0) } ?? "全部"
    }

    private var sortMenu: some View {
        Menu {
            Picker("排序", selection: $shelf.sortKey) {
                Text("最近阅读").tag(SortKey.lastReadAt)
                Text("名称").tag(SortKey.title)
                Text("导入时间").tag(SortKey.addedAt)
            }
        } label: {
            filterLabel("排序", value: sortLabel, active: false)
        }
    }

    private var sortLabel: String {
        switch shelf.sortKey {
        case .lastReadAt: return "最近阅读"
        case .title: return "名称"
        case .addedAt: return "导入时间"
        }
    }

    private var importMenu: some View {
        Menu {
            Button {
                onImportFolder()
            } label: {
                Label("导入文件夹…", systemImage: "folder")
            }
            Button {
                onImportFiles()
            } label: {
                Label("导入文件（ZIP / CBZ / RAR / CBR / PDF）…", systemImage: "doc.zipper")
            }
            Button {
                onImportBatch()
            } label: {
                Label("批量导入子文件夹…", systemImage: "square.grid.2x2")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: shelf.importing.active ? "hourglass" : "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("导入")
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(shelf.importing.active ? Color.gray : Color.accentColor)
            )
        }
        .disabled(shelf.importing.active)
    }

    private func filterLabel(_ title: String, value: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : .primary)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color(uiColor: .tertiarySystemFill))
        )
    }
}
