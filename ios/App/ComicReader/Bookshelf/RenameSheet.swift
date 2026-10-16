import SwiftUI
import ComicReaderCore

// MARK: - 重命名（RenameModal.tsx 的移植）
//
// 只改书架里的显示名，磁盘上的原文件不动；「用文件名」从来源路径恢复标题。

struct RenameSheet: View {
    let comicId: String

    @EnvironmentObject private var shelf: ShelfStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var comic: Comic? {
        shelf.comics.first { $0.id == comicId }
    }

    private var sourceName: String {
        guard let comic else { return "" }
        let base = Format.basename(comic.sourcePath)
        return comic.sourceType == .archive ? stripArchiveExt(base) : base
    }

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespaces)
    }

    private var canSubmit: Bool {
        guard let comic else { return false }
        return !trimmed.isEmpty && trimmed != comic.title
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $draft)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                }

                Section {
                    if let comic {
                        Text(comic.sourcePath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                } footer: {
                    Text("只改书架里的显示名，磁盘上的原文件不会被改名。")
                }

                if trimmed != sourceName, !sourceName.isEmpty {
                    Section {
                        Button("用文件名（\(sourceName)）") {
                            draft = String(sourceName.prefix(Limits.titleMax))
                        }
                    }
                }
            }
            .navigationTitle("重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(!canSubmit)
                }
            }
        }
        .onAppear {
            draft = comic?.title ?? ""
            focused = true
        }
    }

    private func save() {
        guard canSubmit else { return }
        shelf.rename(id: comicId, title: trimmed)
        dismiss()
    }
}
