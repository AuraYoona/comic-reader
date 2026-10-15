import Foundation

// MARK: - 封面文件名约定（src/shared/covers.ts 的移植）
//
// 扩展名兼任「已压缩」标记：.jpg = 主进程生成的 480px JPEG 缩略图；
// 其它扩展名 = 原图直存（iOS 上 ImageIO 都能解码，导入时一步生成，不再需要二段压缩，
// 但保留这两个判定以便读取桌面版备份）。

public let COVER_THUMB_EXT = ".jpg"

/// 是否是主进程生成的缩略图
public func isGeneratedCover(_ coverFile: String?) -> Bool {
    guard let coverFile else { return false }
    return coverFile.lowercased().hasSuffix(COVER_THUMB_EXT)
}

/// 封面是否需要二次压缩（原图直存时为 true）
public func coverNeedsThumbnail(_ coverFile: String?) -> Bool {
    guard let coverFile else { return false }
    return !isGeneratedCover(coverFile)
}
