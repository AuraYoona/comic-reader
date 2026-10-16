import SwiftUI
import ComicReaderCore

// MARK: - 多选操作条（SelectionBar.tsx 的移植）
//
// 分类 / 类型两个下拉负责批量归类；重扫与移除是即时动作。
// 「重新定位来源」在沙盒模型下没有对应场景（来源只剩用户手动删除），暂不提供。

struct SelectionBarView: View {
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var settings: SettingsStore

    let onRemove: () -> Void
    let onExit: () -> Void

    private var selectedIds: [String] { Array(shelf.selectedIds) }

    var body: some View {
        HStack(spacing: 14) {
            Text("已选 \(shelf.selectedIds.count) 本")
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)

            Button {
                if shelf.allVisibleSelected {
                    shelf.clearSelection()
                } else {
                    shelf.selectAllVisible()
                }
            } label: {
                Text(shelf.allVisibleSelected ? "取消全选" : "全选")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 18)

            if settings.extensions.categories, !shelf.categories.isEmpty {
                categoryMenu
            }
            styleMenu

            Button {
                Task { await shelf.rescan(selectedIds) }
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
                    .font(.system(size: 13))
                    .labelStyle(.titleOnly)
            }
            .buttonStyle(.plain)
            .disabled(shelf.busy)
            .opacity(shelf.busy ? 0.4 : 1)

            Button {
                onRemove()
            } label: {
                Text("移除…")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.85, green: 0.3, blue: 0.3))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 2)

            Button {
                onExit()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出多选")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private var categoryMenu: some View {
        Menu {
            Section("加入分类") {
                ForEach(shelf.categories) { category in
                    Button {
                        shelf.assignCategory(selectedIds, categoryId: category.id, add: true)
                    } label: {
                        Text(category.name)
                    }
                }
            }
            Section("移出分类") {
                ForEach(shelf.categories) { category in
                    Button {
                        shelf.assignCategory(selectedIds, categoryId: category.id, add: false)
                    } label: {
                        Text(category.name)
                    }
                }
            }
        } label: {
            Label("分类", systemImage: "tag")
                .font(.system(size: 13))
                .labelStyle(.titleOnly)
        }
    }

    private var styleMenu: some View {
        Menu {
            Section("标为") {
                ForEach(ComicStyle.allCases, id: \.rawValue) { style in
                    Button {
                        shelf.setStyle(selectedIds, style: style)
                    } label: {
                        Text(ComicStyleInfo.label(style))
                    }
                }
            }
            Section("清除") {
                Button(role: .destructive) {
                    shelf.setStyle(selectedIds, style: nil)
                } label: {
                    Text("摘掉类型标签")
                }
            }
        } label: {
            Label("类型", systemImage: "square.grid.2x2")
                .font(.system(size: 13))
                .labelStyle(.titleOnly)
        }
    }
}
