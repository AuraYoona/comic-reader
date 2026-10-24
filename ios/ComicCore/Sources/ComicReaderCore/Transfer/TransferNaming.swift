import Foundation

// MARK: - 传输文件名安全与命名
//
// 来自浏览器的文件名是不可信输入：
//   - 拒绝路径分隔符 / 控制字符 / Windows 非法字符，杜绝「../」与隐藏文件；
//   - 只接受阅读器支持的类型（与 Importer / 桌面版 ARCHIVE_EXTS 对齐）；
//   - 落盘时重名追加 " (2)"、" (3)"（与 ImportFlow 的既有行为一致）。
// 下载头用 RFC 5987 编码中文文件名，保证各浏览器都能正确保存。

public enum TransferNaming {
    /// 允许上传的扩展名（与 Importer.isArchivePath 保持一致）
    public static let allowedExtensions: Set<String> = ["zip", "cbz", "rar", "cbr", "pdf"]

    /// 文件名长度上限（字符数）
    public static let maxFileNameLength = 200
    /// 文件名长度上限（UTF-8 字节数；Darwin 单个路径分量上限 255 字节，
    /// 这里留出重名序号 " (9999)" 的余量）
    public static let maxFileNameBytes = 200

    /// Windows / 各平台都不适合做文件名的字符
    private static let forbiddenScalars: Set<Unicode.Scalar> = Set("/\\:<>\"|?*".unicodeScalars)

    /// 净化文件名；非法输入返回 nil（调用方按 400 处理）
    public static func sanitizeFileName(_ raw: String) -> String? {
        let normalized = raw
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard normalized.count <= maxFileNameLength else { return nil }
        guard normalized.utf8.count <= maxFileNameBytes else { return nil }
        // 隐藏文件 / "." / ".." / 以点结尾（Windows 上不可用）
        guard !normalized.hasPrefix("."), !normalized.hasSuffix(".") else { return nil }
        for scalar in normalized.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F { return nil }
            if forbiddenScalars.contains(scalar) { return nil }
        }
        return normalized
    }

    /// 扩展名是否在允许列表内（大小写不敏感；隐藏文件一律拒绝）
    public static func isAllowedComicFile(_ name: String) -> Bool {
        guard !name.hasPrefix(".") else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return allowedExtensions.contains(ext)
    }

    /// 重名时追加序号：a.cbz → a (2).cbz；无扩展名时 a → a (2)
    public static func uniqueFileName(preferred: String, exists: (String) -> Bool) -> String {
        if !exists(preferred) { return preferred }

        let nsName = preferred as NSString
        let base = nsName.deletingPathExtension
        let ext = nsName.pathExtension
        for number in 2...9999 {
            let candidate = ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)"
            if !exists(candidate) { return candidate }
        }
        // 极端情况兜底（一万个同名文件）：用随机后缀保证可继续
        let tag = UUID().uuidString.prefix(8)
        return ext.isEmpty ? "\(base)-\(tag)" : "\(base)-\(tag).\(ext)"
    }

    /// Content-Disposition：ASCII fallback + RFC 5987 的 filename*
    public static func contentDisposition(fileName: String) -> String {
        let fallback = asciiFallback(fileName)
        let encoded = rfc5987Encode(fileName)
        return "attachment; filename=\"\(fallback)\"; filename*=UTF-8''\(encoded)"
    }

    // MARK: 内部

    /// 只保留 ASCII 字母数字与 . _ -；没有任何可读字符时退回 "download"
    private static func asciiFallback(_ fileName: String) -> String {
        let nsName = fileName as NSString
        let ext = String(nsName.pathExtension.lowercased().filter { $0.isASCII })
        let base = nsName.deletingPathExtension

        var out = ""
        for char in base {
            if char.isASCII, char.isLetter || char.isNumber || char == "." || char == "_" || char == "-" {
                out.append(char)
            } else {
                out.append("_")
            }
        }
        if !out.contains(where: { $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            out = "download"
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        if out.isEmpty { out = "download" }
        return ext.isEmpty ? out : "\(out).\(ext)"
    }

    /// RFC 5987 attr-char 之外的 UTF-8 字节一律 %XX
    private static func rfc5987Encode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            if isAttrChar(byte) {
                out.append(Character(Unicode.Scalar(byte)))
            } else {
                let hex = String(byte, radix: 16, uppercase: true)
                out += "%" + (byte < 16 ? "0" : "") + hex
            }
        }
        return out
    }

    private static func isAttrChar(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x41...0x5A, 0x61...0x7A, 0x30...0x39: // ALPHA / DIGIT
            return true
        case 0x21, 0x23, 0x24, 0x26, 0x2B, 0x2D, 0x2E, 0x5E, 0x5F, 0x60, 0x7C, 0x7E:
            return true
        default:
            return false
        }
    }
}
