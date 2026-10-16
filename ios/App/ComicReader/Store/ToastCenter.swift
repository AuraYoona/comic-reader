import Foundation
import SwiftUI

// MARK: - 轻提示（src/renderer/src/store/ui.ts 的移植：4200ms、最多 4 条、溢出丢最旧）

@MainActor
final class ToastCenter: ObservableObject {
    enum Kind {
        case info
        case success
        case error
    }

    struct Toast: Identifiable, Equatable {
        let id: UUID
        let kind: Kind
        let message: String

        init(kind: Kind, message: String) {
            self.id = UUID()
            self.kind = kind
            self.message = message
        }
    }

    /// 自动消失时间（对齐 ui.ts TOAST_MS = 4200）
    static let toastMs = 4200
    /// 同屏最多条数（对齐 ui.ts MAX_TOASTS = 4，溢出丢最旧）
    static let maxToasts = 4

    @Published private(set) var toasts: [Toast] = []

    func show(_ kind: Kind, _ message: String) {
        let toast = Toast(kind: kind, message: message)
        toasts.append(toast)
        if toasts.count > Self.maxToasts {
            toasts.removeFirst(toasts.count - Self.maxToasts)
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.toastMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}
