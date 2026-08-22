import { useEffect, useRef, useState, type ReactNode } from 'react'
import { stripArchiveExt } from '@shared/archives'
import { TITLE_MAX, type Comic } from '@shared/types'
import Modal from '@/components/common/Modal'
import { useLibrary } from '@/store/library'
import { basename } from '@/utils/format'

/** 从来源路径还原出导入时的默认标题 */
function titleFromSource(comic: Comic): string {
  const base = basename(comic.sourcePath)
  return comic.sourceType === 'archive' ? stripArchiveExt(base) : base
}

/**
 * 重命名书架标题。
 * 只改书架里的显示名，磁盘上的文件夹 / 压缩包不会被改名。
 */
export default function RenameModal({
  comic,
  onClose
}: {
  comic: Comic
  onClose: () => void
}): ReactNode {
  const rename = useLibrary((s) => s.rename)
  const [text, setText] = useState(comic.title)
  const [busy, setBusy] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    inputRef.current?.focus()
    inputRef.current?.select()
  }, [])

  const original = titleFromSource(comic)
  const trimmed = text.trim()
  const canSubmit = !busy && trimmed.length > 0 && trimmed !== comic.title

  const submit = async (): Promise<void> => {
    if (!canSubmit) return
    setBusy(true)
    const ok = await rename(comic.id, trimmed)
    setBusy(false)
    if (ok) onClose()
  }

  return (
    <Modal title="重命名" onClose={onClose} width={460}>
      <p className="cat-comic-title" title={comic.sourcePath}>
        {comic.sourcePath}
      </p>
      <div className="rename-field">
        <input
          ref={inputRef}
          className="cat-input"
          value={text}
          maxLength={TITLE_MAX}
          placeholder="漫画标题"
          spellCheck={false}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.nativeEvent.isComposing) void submit()
          }}
        />
      </div>
      <p className="rename-hint">只改书架里的显示名，磁盘上的原文件不会被改名。</p>

      <div className="modal-actions">
        {text !== original && (
          <button className="btn btn-ghost" onClick={() => setText(original)}>
            用文件名
          </button>
        )}
        <span className="flex-spacer" />
        <button className="btn" onClick={onClose}>
          取消
        </button>
        <button className="btn btn-primary" disabled={!canSubmit} onClick={() => void submit()}>
          保存
        </button>
      </div>
    </Modal>
  )
}
