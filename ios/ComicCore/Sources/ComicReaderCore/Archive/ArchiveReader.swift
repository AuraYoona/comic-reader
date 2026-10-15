import Foundation

// MARK: - 来源读取契约（src/main/archive/reader.ts + errors.ts 的移植）

/// 与来源相关的可恢复错误；message 直接给 UI 用
public struct SourceError: Error, CustomStringConvertible, @unchecked Sendable {
    public let message: String
    /// 可选的来源路径（日志里会脱敏）
    public let path: String?

    public init(_ message: String, path: String? = nil) {
        self.message = message
        self.path = path
    }

    public var description: String { message }

    /// 日志用：路径脱敏成「盘符 + 目录层数 + 扩展名」
    public var logMessage: String {
        guard let path, !path.isEmpty else { return message }
        return message + "（\(redactPath(path))）"
    }
}

/// 压缩包内的一个条目
public struct ArchiveEntry: Sendable {
    public let name: String
    public let isDirectory: Bool

    public init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }
}

/// 读到的页面字节
public struct PageBytes: Sendable {
    public let data: Data
    public let mime: String

    public init(data: Data, mime: String) {
        self.data = data
        self.mime = mime
    }
}

/// 文件来源读取适配器（压缩包或 PDF）。
/// 每种格式实现同一套接口，上层（SourceScanner）只负责按扩展名分派、
/// 过滤图片条目与自然排序，与具体格式解耦。
public protocol ArchiveReader: AnyObject, Sendable {
    /// 列出全部条目（不过滤）
    func list(_ file: String) throws -> [ArchiveEntry]
    /// 读取单个条目的字节
    func read(_ file: String, entry: String) throws -> Data
    /// 释放该文件的句柄（文件被替换、读取失败重试时用）
    func release(_ file: String)
    func releaseAll()
}
