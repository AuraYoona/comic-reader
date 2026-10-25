import SwiftUI

// MARK: - 近似系统 Liquid Glass 的悬浮材质面板
//
// 真正的 .glassEffect / GlassEffectContainer 需要 iOS 26 SDK 才能编译
// （CI 当前 Xcode 16.4 / iOS 18.5 SDK 上没有这些符号），这里用系统材质
// 复刻其视觉特征：超薄材质底 + 内容色低透叠加 + 顶部镜面高光 +
// 0.5pt 高光描边 + 悬浮投影。明暗模式由材质自适应。
// CI 升级 Xcode 26 后，可把本修饰器内部换成真 glassEffect 的
// #available(iOS 26.0, *) 分支，调用点不用动。

extension View {
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(
        in shape: S,
        tint: Color = .clear,
        tintOpacity: Double = 0,
        shadowOpacity: Double = 0.20
    ) -> some View {
        self.background {
            shape
                .fill(.ultraThinMaterial)
                .overlay {
                    shape
                        .fill(tint)
                        .opacity(tintOpacity)
                        .allowsHitTesting(false)
                }
                .overlay {
                    // 顶部镜面高光：玻璃最显眼的反光特征
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(shape)
                    .allowsHitTesting(false)
                }
                .overlay {
                    shape
                        .strokeBorder(.white.opacity(0.26), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(shadowOpacity), radius: 12, y: 4)
        }
    }

    /// 全宽玻璃页头（书架顶栏等固定头部）：材质 + 镜面高光 + 底部发丝线，
    /// 无描边与投影——悬浮感留给 liquidGlass 浮板
    func glassHeader() -> some View {
        self.background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.04), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }
}
