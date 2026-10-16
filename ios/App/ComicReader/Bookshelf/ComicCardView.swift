import SwiftUI
import ComicReaderCore
import UIKit

// MARK: - 书架卡片（ComicCard.tsx 的移植）
//
// 封面 3:4 + 信息区（标题两行 + 状态行）；角标：页数 / 类型 / 来源丢失 / 进度条 / 选中框。
// 桌面版的 hover 浮层（「继续阅读」）在触屏上无意义，由长按菜单的「从第一页开始」承担。

struct ComicCardView: View {
    let comic: Comic
    let missing: Bool
    let selectionActive: Bool
    let selected: Bool
    let cover: UIImage?
    let onTap: () -> Void

    /// 卡片圆角与信息区高度（信息区高度对齐桌面 CARD_INFO_HEIGHT = 66）
    private let coverRadius: CGFloat = 9

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                coverBox
                titleLabel
                metaRow
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: 封面

    private var coverBox: some View {
        ZStack {
            Color(uiColor: .secondarySystemFill)

            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "book.closed")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        // 进度条在裁剪之前叠加，才会跟着封面圆角一起被裁掉
        .overlay(alignment: .bottom) { progressBar }
        .clipShape(RoundedRectangle(cornerRadius: coverRadius, style: .continuous))
        .overlay(alignment: .topLeading) { topLeadingBadge }
        .overlay(alignment: .bottomLeading) { missingBadge }
        .overlay(alignment: .bottomTrailing) { styleBadge }
        .overlay { selectionOutline }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var topLeadingBadge: some View {
        if selectionActive {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selected ? Color.accentColor : .white)
                .background(Circle().fill(.black.opacity(selected ? 0 : 0.28)).padding(2))
                .padding(7)
        } else {
            chip("\(comic.pageCount) 页")
                .padding(7)
        }
    }

    @ViewBuilder
    private var missingBadge: some View {
        if missing {
            Text("来源丢失")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(red: 0.85, green: 0.35, blue: 0.35)))
                .padding(7)
        }
    }

    @ViewBuilder
    private var styleBadge: some View {
        if let style = comic.style {
            Text(ComicStyleInfo.label(style))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.45)))
                .padding(7)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        let percent = Format.readPercent(comic)
        if comic.lastReadAt != nil, percent > 0 {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.18))
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(percent) / 100)
                }
            }
            .frame(height: 3.5)
        }
    }

    @ViewBuilder
    private var selectionOutline: some View {
        if selected {
            RoundedRectangle(cornerRadius: coverRadius + 2, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(-2)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(0.45)))
    }

    // MARK: 标题与状态

    private var titleLabel: some View {
        Text(comic.title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(2, reservesSpace: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaRow: some View {
        HStack(spacing: 4) {
            statusText
            Text("·")
                .foregroundStyle(.tertiary)
            Text(Format.relativeTime(comic.lastReadAt))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .lineLimit(1)
    }

    private var statusText: Text {
        let percent = Format.readPercent(comic)
        // 注意：Text.foregroundStyle 是 iOS 17 API；Text 上要用 foregroundColor（iOS 13+）
        if comic.lastReadAt == nil {
            return Text("未读").foregroundColor(.secondary)
        }
        if percent >= 100 {
            return Text("已读完").foregroundColor(Color(red: 0.25, green: 0.65, blue: 0.42))
        }
        return Text("已读 \(percent)%").foregroundColor(.secondary)
    }
}
