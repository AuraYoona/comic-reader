import SwiftUI
import ComicReaderCore
import UIKit

// MARK: - 单页渲染（PageImage.tsx 的移植）
//
// 尺寸规则：
//   - 适宽：宽 = 视口宽 × scale；适高：高 = 视口高 × scale；原始：自然尺寸 × scale
//   - 开了裁边且量出 insets 时，按「保留区」反推显示尺寸（适宽量的是真正的内容宽度），
//     用容器裁剪 + 负偏移实现，等价于桌面版的 clip-path + 负外边距
// 加载：PageProvider 降采样解码；200ms 未出图显示慢载指示；失败面板可重试。

struct PageImageView: View {
    let comic: Comic
    let index: Int
    let boxSize: CGSize
    let mode: ZoomMode
    let scale: Double
    let autoCrop: Bool
    let onNatural: ((Double, Double) -> Void)?
    let onSettled: (() -> Void)?

    @EnvironmentObject private var pages: PageProvider

    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var showSlowLoad = false
    @State private var cropInsets: CropInsets?? // 双层可选：nil=还没查到，some(nil)=已查到（不需要裁）

    /// 慢载提示延迟（对齐 PagedView.tsx SLOW_LOAD_HINT_MS = 200）
    private static let slowLoadHintNs: UInt64 = 200 * 1_000_000

    /// 解码目标尺寸：显示与预取必须共用同一公式——缓存键含解码尺寸
    /// （PageProvider.pageKey），公式、地板值或倍率任何一处漂移都会让
    /// 预取条目永远 miss，白做一遍还挤占 32 槽 LRU
    static func decodeTargetSize(pointWidth: CGFloat, scale: Double) -> Int {
        min(4096, max(1024, Int(pointWidth * CGFloat(max(scale, 1)) * UIScreen.main.scale * 2)))
    }

    var body: some View {
        content
            .task(id: "\(comic.id)-\(index)-\(attempt)") {
                await load()
            }
            // 单页模式下本视图结构位置固定、仅 index 变化，SwiftUI 会保留视图身份，
            // @State 全部残留——必须显式重置，否则翻页显示旧图、失败面板被旧图掩盖
            .onChange(of: index) { _ in
                resetForNewPage()
            }
    }

    /// 翻页 / 换页时的状态复位（.task(id:) 只重启任务，不重置 @State）
    private func resetForNewPage() {
        image = nil
        failed = false
        showSlowLoad = false
        cropInsets = nil
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            sizedImage(image)
        } else if failed {
            failurePanel
        } else {
            ZStack {
                Color.clear
                if showSlowLoad {
                    ProgressView()
                        .controlSize(.regular)
                }
            }
            .frame(maxWidth: .infinity)
            // 加载中也占住槽位高度：无此约束时 LazyVStack 的无界高度提案会让
            // 槽位塌缩为 0（占位高 → 0 → 真实高 的两级跳变是滚动抖动主源）
            .frame(height: max(boxSize.height, 120), alignment: .top)
        }
    }

    // MARK: 尺寸与裁剪

    @ViewBuilder
    private func sizedImage(_ image: UIImage) -> some View {
        let naturalW = Double(image.size.width)
        let naturalH = Double(image.size.height)
        let ratio = naturalW > 0 && naturalH > 0 ? naturalH / naturalW : 1.4

        if autoCrop, let insets = cropInsets ?? nil, hasCrop(insets) {
            croppedImage(image, naturalW: naturalW, naturalH: naturalH, insets: insets)
        } else {
            plainImage(image, ratio: ratio, naturalW: naturalW)
        }
    }

    /// 无裁剪：按模式定尺寸（不放大原始图在 original 模式之外没有意义——沿用桌面规则）
    private func plainImage(_ image: UIImage, ratio: Double, naturalW: Double) -> some View {
        let boxW = boxSize.width
        let boxH = boxSize.height

        let width: CGFloat
        switch mode {
        case .fitWidth:
            width = max(60, boxW * scale)
        case .fitHeight:
            width = max(60, boxH * scale / max(ratio, 0.01))
        case .original:
            width = max(30, naturalW * scale)
        }

        return Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: width * ratio)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 裁剪：容器 = 保留区尺寸；图片放大到 (尺寸 / 保留比例) 再偏移，裁掉的部分不计入布局
    private func croppedImage(
        _ image: UIImage, naturalW: Double, naturalH: Double, insets: CropInsets
    ) -> some View {
        let boxW = max(60, boxSize.width)
        let boxH = max(60, boxSize.height)
        let keepW = max(0.05, 1 - insets.left - insets.right)
        let keepH = max(0.05, 1 - insets.top - insets.bottom)

        let totalW: CGFloat
        let totalH: CGFloat
        switch mode {
        case .fitWidth:
            totalW = boxW * scale / keepW
            totalH = totalW * (naturalH / max(naturalW, 1))
        case .fitHeight:
            totalH = boxH * scale / keepH
            totalW = totalH * (naturalW / max(naturalH, 1))
        case .original:
            totalW = naturalW * scale
            totalH = naturalH * scale
        }

        return ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: totalW, height: totalH)
                .offset(x: -totalW * insets.left, y: -totalH * insets.top)
        }
        .frame(width: totalW * keepW, height: totalH * keepH, alignment: .topLeading)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 失败面板

    private var failurePanel: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("图片加载失败")
                .font(.system(size: 13, weight: .medium))
            Text("文件可能已损坏或被移动")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("重试") {
                failed = false
                image = nil
                attempt += 1
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(20)
        .frame(minWidth: 220, minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    // MARK: 加载

    private func load() async {
        showSlowLoad = false
        // 同步快路径：命中解码缓存直接上屏，重挂载不闪占位（高度不塌缩）
        if image == nil {
            let cached = Self.decodeTargetSize(pointWidth: boxSize.width, scale: scale)
            image = pages.cachedPage(comic: comic, index: index, maxPixelSize: cached)
        }
        let slowTask = Task { [self] in
            try? await Task.sleep(nanoseconds: Self.slowLoadHintNs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if image == nil, !failed { showSlowLoad = true }
            }
        }
        defer { slowTask.cancel() }

        // 解码尺寸：与预取共用 decodeTargetSize（见其注释）
        let target = Self.decodeTargetSize(pointWidth: boxSize.width, scale: scale)
        let decoded = await pages.page(comic: comic, index: index, maxPixelSize: target)

        // .task(id:) 在换页时会取消旧任务：被取消的任务不得再写状态，
        // 否则旧页晚到的结果会覆盖新页的画面（包括熄灭新页的慢载指示）
        guard !Task.isCancelled else { return }
        showSlowLoad = false
        if let decoded {
            image = decoded
            onNatural?(Double(decoded.size.width), Double(decoded.size.height))
            onSettled?()
            if autoCrop {
                let insets = await pages.cropInsets(comic: comic, index: index)
                guard !Task.isCancelled else { return }
                cropInsets = insets
            }
        } else {
            failed = true
            onSettled?()
        }
    }
}
