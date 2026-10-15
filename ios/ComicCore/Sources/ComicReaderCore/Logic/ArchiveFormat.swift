import Foundation

// MARK: - 压缩包格式判定（src/shared/archives.ts + src/main/archive/formats.ts 的移植）

/// 支持的压缩包扩展名（不带点、小写）
public let ARCHIVE_EXTS: Set<String> = ["zip", "cbz", "rar", "cbr", "pdf"]

/// 页面图片扩展名（不带点、小写；src/main/utils/images.ts IMAGE_EXTS）
public let IMAGE_EXTS: Set<String> = [
    "jpg", "jpeg", "jfif", "png", "webp", "gif", "avif", "bmp"
]

public enum ArchiveFormat: String, Sendable {
    case zip
    case rar
    case pdf
}

/// 取路径扩展名（小写，不含点）；路径分隔符同时容忍 \ 和 /。
/// 没有扩展名（或点在开头 = 隐藏文件）时返回 nil。
public func pathExtname(_ path: String) -> String? {
    let segments = path.split(whereSeparator: { $0 == "\\" || $0 == "/" })
    guard let basename = segments.last else { return nil }
    guard let dot = basename.lastIndex(of: ".") else { return nil }
    guard dot != basename.startIndex else { return nil }
    return String(basename[basename.index(after: dot)...]).lowercased()
}

/// 是否是受支持的压缩包路径
public func isArchivePath(_ path: String) -> Bool {
    guard let ext = pathExtname(path) else { return false }
    return ARCHIVE_EXTS.contains(ext)
}

/// 由扩展名得到格式；不支持的类型返回 nil
public func archiveFormat(_ path: String) -> ArchiveFormat? {
    guard let ext = pathExtname(path) else { return nil }
    switch ext {
    case "zip", "cbz": return .zip
    case "rar", "cbr": return .rar
    case "pdf": return .pdf
    default: return nil
    }
}

/// 书架标题：文件名去掉压缩包扩展名（src/shared/archives.ts stripArchiveExt）
public func stripArchiveExt(_ path: String) -> String {
    guard let ext = pathExtname(path), ARCHIVE_EXTS.contains(ext) else { return path }
    let segments = path.split(whereSeparator: { $0 == "\\" || $0 == "/" })
    guard let basename = segments.last else { return path }
    var name = String(basename)
    if let dot = name.lastIndex(of: "."), dot != name.startIndex {
        name = String(name[..<dot])
    }
    return name
}

// MARK: - 条目过滤（src/main/utils/images.ts 的移植）

/// 路径的 basename 是否是页面图片：
/// 扩展名在白名单内，且 basename 不以点开头（`_001.jpg` 这种下划线开头的保留）
public func isImagePath(_ path: String) -> Bool {
    let segments = path.split(whereSeparator: { $0 == "\\" || $0 == "/" })
    guard let basename = segments.last, !basename.hasPrefix(".") else { return false }
    guard let ext = pathExtname(path) else { return false }
    return IMAGE_EXTS.contains(ext)
}

/// 垃圾条目：任一路径段以点开头、等于 __MACOSX、或以 __MACOSX 开头（资源叉/系统目录）
public func isJunkEntry(_ path: String) -> Bool {
    let segments = path.split(whereSeparator: { $0 == "\\" || $0 == "/" })
    for segment in segments {
        if segment.hasPrefix(".") { return true }
        if segment == "__MACOSX" || segment.hasPrefix("__MACOSX") { return true }
    }
    return false
}

/// 扩展名 → MIME（回退 application/octet-stream）
public func mimeFor(_ path: String) -> String {
    switch pathExtname(path) {
    case "jpg", "jpeg", "jfif": return "image/jpeg"
    case "png": return "image/png"
    case "webp": return "image/webp"
    case "gif": return "image/gif"
    case "avif": return "image/avif"
    case "bmp": return "image/bmp"
    default: return "application/octet-stream"
    }
}

/// 导入去重用的路径归一化键（桌面版在 Windows 上 resolve+lowercase；
/// iOS 文件系统默认大小写不敏感，统一按小写比较）
public func normalizeForCompare(_ path: String) -> String {
    path.lowercased()
}
