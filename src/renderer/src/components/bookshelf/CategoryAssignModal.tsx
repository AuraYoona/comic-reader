import { useRef, useState, type ReactNode } from 'react'
import { CATEGORY_NAME_MAX, type Comic } from '@shared/types'
import Modal from '@/components/common/Modal'
import { Icon } from '@/components/common/Icon'
import { useLibrary } from '@/store/library'

interface CategoryAssignModalProps {
  comic: Comic
  onClose: () => void
  /** 切到管理弹窗：调用方需先关掉本弹窗，两个弹窗不能叠放（Esc 会一次全关） */
  onOpenManager: () => void
}

/** 给单本漫画设置分类，点击行即切换归属，改动即时保存 */
export default function CategoryAssignModal({
  comic,
  onClose,
  onOpenManager
}: CategoryAssignModalProps): ReactNode {
  const categories = useLibrary((s) => s.categories)
  const createCategory = useLibrary((s) => s.createCategory)
  const toggleComicCategory = useLibrary((s) => s.toggleComicCategory)
  const [name, setName] = useState('')
  // Enter 自动重复 / 连点时只放行第一次提交
  const submittingRef = useRef(false)

  const submitCreate = async (): Promise<void> => {
    const trimmed = name.trim()
    if (!trimmed || submittingRef.current) return
    submittingRef.current = true
    try {
      const created = await createCategory(trimmed)
      // 失败（重名等）保留输入，错误已由 store 弹出提示
      if (!created) return
      void toggleComicCategory(comic.id, created.id)
      setName('')
    } finally {
      submittingRef.current = false
    }
  }

  return (
    <Modal title="设置分类" width={440} onClose={onClose}>
      <p className="cat-comic-title" title={comic.title}>
        {comic.title}
      </p>

      {categories.length === 0 ? (
        <p className="cat-empty">还没有分类</p>
      ) : (
        <div className="cat-list">
          {categories.map((cat) => {
            const on = comic.categoryIds.includes(cat.id)
            return (
              <button
                key={cat.id}
                className="cat-row"
                aria-pressed={on}
                onClick={() => void toggleComicCategory(comic.id, cat.id)}
              >
                <span className="cat-dot" style={{ background: cat.color }} />
                <span className="cat-name">{cat.name}</span>
                {on && (
                  <span className="cat-check">
                    <Icon name="check" size={15} />
                  </span>
                )}
              </button>
            )
          })}
        </div>
      )}

      <div className="cat-create">
        <input
          className="cat-input"
          type="text"
          placeholder="新建分类"
          maxLength={CATEGORY_NAME_MAX}
          value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.nativeEvent.isComposing) void submitCreate()
          }}
          spellCheck={false}
        />
        <button className="btn btn-sm" disabled={!name.trim()} onClick={() => void submitCreate()}>
          创建并加入
        </button>
      </div>

      <div className="modal-actions">
        <button className="btn btn-ghost" onClick={onOpenManager}>
          管理分类…
        </button>
        <span className="flex-spacer" />
        <button className="btn btn-primary" onClick={onClose}>
          完成
        </button>
      </div>
    </Modal>
  )
}
