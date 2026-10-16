import SwiftUI

// MARK: - 根视图（对齐桌面版 App.tsx：书架常驻，阅读器覆盖其上）

struct RootView: View {
    @EnvironmentObject private var reader: ReaderStore

    var body: some View {
        ZStack {
            BookshelfView()

            if reader.active {
                ReaderView()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            ToastOverlay()
        }
        .animation(.easeOut(duration: 0.18), value: reader.active)
    }
}

// MARK: - 轻提示浮层（对齐 Feedback.tsx 的 Toasts）

struct ToastOverlay: View {
    @EnvironmentObject private var toasts: ToastCenter

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toasts.toasts) { toast in
                Text(toast.message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(background(for: toast.kind))
                            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    )
                    .onTapGesture { toasts.dismiss(toast.id) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 84)
        .allowsHitTesting(!toasts.toasts.isEmpty)
        .animation(.easeOut(duration: 0.18), value: toasts.toasts)
    }

    private func background(for kind: ToastCenter.Kind) -> Color {
        switch kind {
        case .info: return Color.black.opacity(0.78)
        case .success: return Color(red: 0.18, green: 0.62, blue: 0.42).opacity(0.95)
        case .error: return Color(red: 0.85, green: 0.32, blue: 0.32).opacity(0.95)
        }
    }
}
