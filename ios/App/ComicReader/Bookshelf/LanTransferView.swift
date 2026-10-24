import ComicReaderCore
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// MARK: - 局域网传输面板
//
// 打开即启动服务：二维码 / 地址 / 6 位密码 / 传输记录。
// 关闭面板或 App 进后台会自动停服；服务运行期间禁用自动锁屏。

struct LanTransferView: View {
    @EnvironmentObject private var transfer: LanTransferModel
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var didAutoStart = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    switch transfer.phase {
                    case .running:
                        connectionCard
                        optionsCard
                        activityCard
                    case .starting:
                        startingCard
                    case .failed(let message):
                        failureCard(message)
                    case .stopped:
                        stoppedCard
                    }
                    tipsCard
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("局域网传输")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                guard !didAutoStart else { return }
                didAutoStart = true
                Task { await transfer.start() }
            }
            .onDisappear {
                transfer.stop(notify: false)
            }
        }
    }

    // MARK: 状态

    private var statusCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 15, weight: .semibold))
                Text(statusSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if transfer.phase == .running, transfer.connectionCount > 0 {
                Label("\(transfer.connectionCount)", systemImage: "person.2.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var statusTitle: String {
        switch transfer.phase {
        case .stopped: return "已停止"
        case .starting: return "正在启动…"
        case .running: return "等待连接"
        case .failed: return "启动失败"
        }
    }

    private var statusSubtitle: String {
        switch transfer.phase {
        case .stopped:
            return "打开传输面板后自动开启"
        case .starting:
            return "正在启动本地服务"
        case .running:
            return transfer.connectionCount > 0 ? "有设备正在传输" : "用浏览器打开下面的地址"
        case .failed:
            return "按照下面的提示处理后重试"
        }
    }

    private var statusColor: Color {
        switch transfer.phase {
        case .stopped: return .gray
        case .starting: return .orange
        case .running: return .green
        case .failed: return .red
        }
    }

    // MARK: 连接信息

    private var connectionCard: some View {
        VStack(spacing: 14) {
            if let url = transfer.urlString {
                TransferQRCodeView(text: url)

                Text(url)
                    .font(.system(size: 13, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("连接密码")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(transfer.displayCode)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .kerning(1)
                    }

                    Spacer()

                    Button {
                        UIPasteboard.general.string = url
                        toasts.show(.success, "已复制传输地址")
                    } label: {
                        Label("复制地址", systemImage: "doc.on.doc")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("在同一 Wi-Fi 下，用电脑或平板的浏览器打开上面的地址（或扫码）。无需安装任何软件。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: 选项

    private var optionsCard: some View {
        VStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { transfer.autoImport },
                set: { transfer.autoImport = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("传完自动导入书架")
                        .font(.system(size: 14, weight: .medium))
                    Text(transfer.autoImport ? "上传完成后自动上架" : "只保存到 Comics，稍后扫描上架")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button(role: .destructive) {
                transfer.stop(notify: true)
            } label: {
                Text("停止传输")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: 传输记录

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("传输记录")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !transfer.recent.isEmpty {
                    Text("\(transfer.recent.count) 项")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            if shelf.importing.active {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在导入 \(shelf.importing.current)/\(shelf.importing.total)…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if transfer.recent.isEmpty {
                Text("还没有文件。收到的漫画会显示在这里。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                ForEach(transfer.recent) { item in
                    itemRow(item)
                    if item.id != transfer.recent.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func itemRow(_ item: LanTransferStatusStore.Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(item.size > 0 ? formatBytes(item.size) : "—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if item.state == .receiving {
                if item.size > 0 {
                    ProgressView(value: Double(item.received), total: Double(item.size))
                        .tint(.accentColor)
                } else {
                    ProgressView()
                        .tint(.accentColor)
                }
            }

            HStack(spacing: 6) {
                Text(stateText(item))
                    .font(.system(size: 11.5))
                    .foregroundStyle(stateColor(item))
                Spacer()
                if item.state == .receiving, item.size > 0 {
                    Text("\(Int(Double(item.received) / Double(item.size) * 100))%")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func stateText(_ item: LanTransferStatusStore.Item) -> String {
        switch item.state {
        case .receiving:
            return "接收中…"
        case .importing:
            return "已上传，正在导入…"
        case .imported:
            return "已导入书架"
        case .skipped:
            return "已上传（\(item.reason ?? "已在书架中")）"
        case .saved:
            return "已保存到 Comics（未自动导入）"
        case .failed:
            return "失败：\(item.reason ?? "未知原因")"
        }
    }

    private func stateColor(_ item: LanTransferStatusStore.Item) -> Color {
        switch item.state {
        case .receiving: return .accentColor
        case .importing: return .orange
        case .imported: return .green
        case .skipped, .saved: return .secondary
        case .failed: return .red
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: 启动中 / 失败 / 停止

    private var startingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在启动局域网服务…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(cardBackground)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13.5))
                .multilineTextAlignment(.center)
            Button {
                Task { await transfer.start() }
            } label: {
                Text("重试")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(cardBackground)
    }

    private var stoppedCard: some View {
        VStack(spacing: 12) {
            Text("传输已停止")
                .font(.system(size: 15, weight: .semibold))
            Text("点击开始后会生成新的二维码与密码。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                Task { await transfer.start() }
            } label: {
                Text("开始传输")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: 提示

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("小提示")
                .font(.system(size: 13, weight: .semibold))

            tip("电脑和手机连接同一个 Wi-Fi；电脑连手机热点也可以。")
            tip("传输期间保持这个页面打开；App 进入后台会自动停止。")
            tip("打不开页面时：确认没有连 VPN；首次使用请在「设置 › 隐私与安全性 › 本地网络」中允许 ComicReader。")
            tip("支持 ZIP / CBZ / RAR / CBR / PDF；文件夹请先压缩成 ZIP。")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("•")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

// MARK: - 二维码

/// 独立子视图：图片只在地址变化时重建，进度刷新不会反复渲染二维码
private struct TransferQRCodeView: View {
    let text: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .accessibilityLabel("传输地址二维码")
            }
        }
        .onAppear { image = QRCodeRenderer.image(for: text) }
        .onChange(of: text) { newValue in
            image = QRCodeRenderer.image(for: newValue)
        }
    }
}

private enum QRCodeRenderer {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
