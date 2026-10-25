import SwiftUI

// MARK: - 近似系统 Liquid Glass 的材质面板
//
// 视觉基准（用户提供的参考 App）：亮白磨砂玻璃、悬浮胶囊、大而柔的漫射
// 投影、内容直接躺在玻璃上。真 .glassEffect 需要 iOS 26 SDK 编译（CI 当前
// Xcode 16.4 无此符号），这里用系统材质复刻；CI 升级 Xcode 26 后把
// GlassSurface 内部换成真 glassEffect 的 #available 分支即可，调用点不动。

/// 玻璃背板：材质 + 按明暗模式自适应的白色提亮 + tint + 顶部镜面高光 +
/// 高光描边。亮色模式提亮到近白（参考风格的奶白磨砂感），暗色模式轻提亮
private struct GlassSurface<S: InsettableShape>: View {
    let shape: S
    var tint: Color = .clear
    var tintOpacity: Double = 0
    /// 提亮倍率：全强度浮板 1.0；页头等大面积可调低避免过白
    var bright: Double = 1.0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let lift = (colorScheme == .light ? 0.50 : 0.10) * bright
        let stroke = colorScheme == .light ? 0.40 : 0.14
        return shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(Color.white).opacity(lift).allowsHitTesting(false)
            }
            .overlay {
                shape.fill(tint).opacity(tintOpacity).allowsHitTesting(false)
            }
            .overlay {
                // 顶部镜面高光：玻璃最显眼的反光特征
                LinearGradient(
                    colors: [.white.opacity(0.35), .white.opacity(0.06), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(stroke), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(
        in shape: S,
        tint: Color = .clear,
        tintOpacity: Double = 0,
        shadowOpacity: Double = 0.16
    ) -> some View {
        self.background {
            GlassSurface(shape: shape, tint: tint, tintOpacity: tintOpacity)
                // 大而柔的漫射投影（参考风格；比小而紧的阴影更像悬浮玻璃）
                .shadow(color: .black.opacity(shadowOpacity), radius: 18, y: 6)
        }
    }

    /// 全宽玻璃页头（书架顶栏等固定头部）：材质 + 提亮 + 底部发丝线，
    /// 无描边与投影——悬浮感留给 liquidGlass 浮板。大面积用 0.7 提亮防爆白
    func glassHeader() -> some View {
        self.background {
            GlassSurface(shape: Rectangle(), bright: 0.7)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }
}
