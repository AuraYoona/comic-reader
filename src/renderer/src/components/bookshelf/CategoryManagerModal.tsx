import { useRef, useState, type ReactNode } from 'react'
import { CATEGORY_COLORS, CATEGORY_NAME_MAX, type Category } from '@shared/types'
import Modal from '@/components/common/Modal'
import { Icon } from '@/components/common/Icon'
import { useLibrary } from '@/store/library'

/** 与 CATEGORY_COLORS 一一对应的中文色名（提示与读屏用） */
const COLOR_NAMES = ['红', '橙', '黄', '绿', '青', '蓝', '紫', '粉']

/** 管理分类：新建 / 重命名 / 换色 / 删除。删除只解除关联，漫画本身不受影响 */
export default function CategoryManagerModal({ onClose }: { onClose: () => void }): ReactNode {
  const comics = useLibrary((s) => s.comics)
  const categories = useLibrary((s) => s.categories)
  const createCategory = useLibrary((s) => s.createCategory)
  const updateCategory = useLibrary((s) => s.updateCategory)
  const deleteCategory = useLibrary((s) => s.deleteCategory)

  const [newName, setNewName] = useState('')
  // 编辑与删除确认都是行内切换，同一时刻只有一行处于该状态，绝不叠出第二层弹窗
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editName, setEditName] = useState('')
  const [editColor, setEditColor] = useState('')
  const [confirmingId, setConfirmingId] = useState<string | null>(null)
  // Enter 自动重复 / 连点时只放行第一次提交
  const submittingRef = useRef(false)

  const submitCreate = async (): Promise<void> => {
    const trimmed = newName.trim()
    if (!trimmed || submittingRef.current) return
    submittingRef.current = true
    try {
      // 失败（重名等）保留输入，错误已由 store 弹出提示
      const created = await createCategory(trimmed)
      if (created) setNewName('')
    } finally {
      submittingRef.current = false
    }
  }

  const startEdit = (cat: Category): void => {
    setConfirmingId(null)
    setEditingId(cat.id)
    setEditName(cat.name)
    setEditColor(cat.color)
  }

  const submitEdit = async (): Promise<void> => {
    const trimmed = editName.trim()
    if (!editingId || !trimmed || submittingRef.current) return
    submittingRef.current = true
    try {
      // 失败（重名等）保留编辑态，修正后可直接重试
      if (await updateCategory(editingId, { name: trimmed, color: editColor })) {
        setEditingId(null)
      }
    } finally {
      submittingRef.current = false
    }
  }

  return (
    <Modal title="管理分类" width={520} onClose={onClose}>
      <div className="cat-create">
        <input
          className="cat-input"
          type="text"
          placeholder="新建分类"
          maxLength={CATEGORY_NAME_MAX}
          value={newName}
          onChange={(e) => setNewName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.nativeEvent.isComposing) void submitCreate()
          }}
          spellCheck={false}
        />
        <button
          className="btn btn-primary btn-sm"
          disabled={!newName.trim()}
          onClick={() => void submitCreate()}
        >
          新建
        </button>
      </div>

      {categories.length === 0 ? (
        <p className="cat-empty">还没有分类，创建一个开始整理书架</p>
      ) : (
        <div className="cat-list">
          {categories.map((cat) => {
            if (editingId === cat.id) {
              return (
                <div key={cat.id} className="cat-row cat-row-edit">
                  <input
                    className="cat-input"
                    type="text"
                    maxLength={CATEGORY_NAME_MAX}
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' && !e.nativeEvent.isComposing) void submitEdit()
                    }}
                    spellCheck={false}
                    autoFocus
                  />
                  <div className="cat-swatches">
                    {CATEGORY_COLORS.map((color, i) => (
                      <button
                        key={color}
                        className={editColor === color ? 'cat-swatch active' : 'cat-swatch'}
                        style={{ background: color }}
                        title={COLOR_NAMES[i] ?? color}
                        aria-label={`使用${COLOR_NAMES[i] ?? color}色`}
                        aria-pressed={editColor === color}
                        onClick={() => setEditColor(color)}
                      />
                    ))}
                  </div>
                  <button
                    className="btn btn-primary btn-sm"
                    disabled={!editName.trim()}
                    onClick={() => void submitEdit()}
                  >
                    保存
                  </button>
                  <button className="btn btn-sm" onClick={() => setEditingId(null)}>
                    取消
                  </button>
                </div>
              )
            }
            if (confirmingId === cat.id) {
              return (
                <div key={cat.id} className="cat-row cat-row-edit">
                  <span className="confirm-text">删除该分类？漫画不会受影响</span>
                  <span className="flex-spacer" />
                  <button
                    className="btn btn-danger btn-sm"
                    onClick={() => {
                      void deleteCategory(cat.id)
                      setConfirmingId(null)
                    }}
                  >
                    删除
                  </button>
                  <button className="btn btn-sm" onClick={() => setConfirmingId(null)}>
                    取消
                  </button>
                </div>
              )
            }
            const count = comics.filter((c) => c.categoryIds.includes(cat.id)).length
            return (
              <div key={cat.id} className="cat-row">
                <span className="cat-dot" style={{ background: cat.color }} />
                <span className="cat-name">{cat.name}</span>
                <span className="cat-count">{count} 本</span>
                <button className="icon-btn icon-btn-sm" title="重命名" onClick={() => startEdit(cat)}>
                  <Icon name="edit" size={14} />
                </button>
                <button
                  className="icon-btn icon-btn-sm"
                  title="删除"
                  onClick={() => {
                    setEditingId(null)
                    setConfirmingId(cat.id)
                  }}
                >
                  <Icon name="trash" size={14} />
                </button>
              </div>
            )
          })}
        </div>
      )}

      <div className="modal-actions">
        <button className="btn btn-primary" onClick={onClose}>
          完成
        </button>
      </div>
    </Modal>
  )
}
