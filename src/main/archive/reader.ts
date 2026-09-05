/** 压缩包内的一个条目 */
export interface ArchiveEntry {
  name: string
  isDirectory: boolean
}

/**
 * 文件来源读取适配器（压缩包或 PDF）。
 * 每种格式实现同一套接口，上层（archive/index）只负责按扩展名分派、
 * 过滤图片条目与自然排序，与具体格式解耦。
 */
export interface ArchiveReader {
  /** 列出全部条目（不过滤） */
  list(file: string): Promise<ArchiveEntry[]>
  /** 读取单个条目的字节 */
  read(file: string, entry: string): Promise<Buffer>
  /** 释放该文件的句柄（文件被替换、读取失败重试时用） */
  release(file: string): void
  releaseAll(): void
}
