import SwiftUI

// MARK: - 根视图（对齐桌面版 App.tsx：书架常驻，阅读器覆盖其上）

struct RootView: View {
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var shelf: ShelfStore

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
        .onChange(of: reader.active) { visible in
            // 书架常驻在阅读器下面：关闭时刷新快照，进度/未读徽章才跟上
            if !visible { shelf.refreshAfterReading() }
        }
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
                    .liquidGlass(
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                        tint: background(for: toast.kind),
                        tintOpacity: 0.80,
                        shadowOpacity: 0.25
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
        // 不透明色：透明度统一由 liquidGlass 的 tintOpacity 提供
        // （此前颜色自带 alpha 再乘 tint 会双重打折，浅色模式下白字对比度不足）
        switch kind {
        case .info: return Color.black
        case .success: return Color(red: 0.18, green: 0.62, blue: 0.42)
        case .error: return Color(red: 0.85, green: 0.32, blue: 0.32)
        }
    }
}
