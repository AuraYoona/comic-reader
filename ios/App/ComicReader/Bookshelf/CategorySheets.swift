import SwiftUI
import ComicReaderCore

// MARK: - 分类指派（CategoryAssignModal.tsx 的移植）
//
// 点分类行即时加入 / 移出（按数据库当前归属决定方向）；下方可新建并加入。

struct CategoryAssignSheet: View {
    let comicId: String
    let onOpenManager: () -> Void

    @EnvironmentObject private var shelf: ShelfStore
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""

    private var comic: Comic? {
        shelf.comics.first { $0.id == comicId }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shelf.categories) { category in
                        Button {
                            shelf.toggleCategory(comicId: comicId, categoryId: category.id)
                        } label: {
                            HStack(spacing: 10) {
                                ColorDot(hex: category.color)
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if comic?.categoryIds.contains(category.id) == true {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text(comic?.title ?? "")
                }

                Section {
                    HStack(spacing: 8) {
                        TextField("新分类名称（最多 20 字）", text: $newName)
                            .onSubmit(createAndAdd)
                        Button("创建并加入", action: createAndAdd)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    Button("管理分类…") {
                        onOpenManager()
                    }
                }
            }
            .navigationTitle("设置分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func createAndAdd() {
        guard let category = shelf.createCategory(name: newName) else { return }
        newName = ""
        shelf.toggleCategory(comicId: comicId, categoryId: category.id)
    }
}

// MARK: - 分类管理（CategoryManagerModal.tsx 的移植）

struct CategoryManagerSheet: View {
    @EnvironmentObject private var shelf: ShelfStore
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var editingId: String?
    @State private var editName = ""
    @State private var editColor = ""
    @State private var confirmingDeleteId: String?

    var body: some View {
        NavigationStack {
            List {
                Section("新建分类") {
                    HStack(spacing: 8) {
                        TextField("分类名称（最多 20 字）", text: $newName)
                            .onSubmit(create)
                        Button("新建", action: create)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("已有分类") {
                    if shelf.categories.isEmpty {
                        Text("还没有分类")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shelf.categories) { category in
                        row(for: category)
                    }
                }
            }
            .navigationTitle("管理分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for category: ComicCategory) -> some View {
        if editingId == category.id {
            editRow(for: category)
        } else if confirmingDeleteId == category.id {
            HStack {
                Text("删除该分类？漫画不会受影响")
                    .font(.system(size: 13))
                Spacer()
                Button("删除", role: .destructive) {
                    shelf.deleteCategory(id: category.id)
                    confirmingDeleteId = nil
                }
                Button("取消") { confirmingDeleteId = nil }
            }
        } else {
            HStack(spacing: 10) {
                ColorDot(hex: category.color)
                Text(category.name)
                Spacer()
                Text("\(shelf.categoryCount(category.id)) 本")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button {
                    beginEdit(category)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button {
                    confirmingDeleteId = category.id
                    editingId = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.85, green: 0.32, blue: 0.32))
            }
        }
    }

    private func editRow(for category: ComicCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("名称", text: $editName)
            HStack(spacing: 8) {
                ForEach(Limits.categoryColors, id: \.self) { hex in
                    Button {
                        editColor = hex
                    } label: {
                        Circle()
                            .fill(Color(hexString: hex))
                            .frame(width: 22, height: 22)
                            .overlay {
                                if editColor == hex {
                                    Circle()
                                        .strokeBorder(myAppTextColor, lineWidth: 2)
                                        .padding(-2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("保存") {
                    shelf.updateCategory(id: category.id, patch: CategoryPatch(name: editName, color: editColor))
                    editingId = nil
                }
                .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("取消") { editingId = nil }
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }

    /// 与调色板色对比的描边色（不做主题跳色判断，用主色即可）
    private var myAppTextColor: Color { .primary }

    private func create() {
        guard shelf.createCategory(name: newName) != nil else { return }
        newName = ""
    }

    private func beginEdit(_ category: ComicCategory) {
        editingId = category.id
        editName = category.name
        editColor = category.color
        confirmingDeleteId = nil
    }
}

// MARK: - 共用小件

/// 分类颜色圆点
struct ColorDot: View {
    let hex: String

    var body: some View {
        Circle()
            .fill(Color(hexString: hex))
            .frame(width: 10, height: 10)
    }
}

extension Color {
    /// "#rrggbb" → Color（非法值回退灰色）
    init(hexString: String) {
        var value: UInt64 = 0
        let hex = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard hex.count == 6, Scanner(string: hex).scanHexInt64(&value) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
