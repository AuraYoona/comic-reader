/**
 * 极小的 PDF 写入器，给归档层的集成测试造夹具用。
 *
 * 每页是纯色矩形，PDFium 能正常打开并渲成位图即可；
 * 不追求字体 / 图片嵌入，这样测试就不需要额外依赖。
 */

export interface PdfPage {
  width: number
  height: number
  /** 0–1 */
  r: number
  g: number
  b: number
}

function obj(id: number, body: string): string {
  return `${id} 0 obj\n${body}\nendobj\n`
}

export function buildPdf(pages: PdfPage[]): Buffer {
  if (pages.length === 0) throw new Error('PDF 至少要有一页')

  const kids = pages.map((_, i) => `${3 + i * 2} 0 R`).join(' ')
  const parts: string[] = ['%PDF-1.4\n']

  parts.push(obj(1, '<< /Type /Catalog /Pages 2 0 R >>'))
  parts.push(obj(2, `<< /Type /Pages /Kids [${kids}] /Count ${pages.length} >>`))

  for (let i = 0; i < pages.length; i++) {
    const page = pages[i]
    const pageId = 3 + i * 2
    const contentId = pageId + 1
    const stream = `${page.r} ${page.g} ${page.b} rg\n0 0 ${page.width} ${page.height} re f\n`
    parts.push(
      obj(
        pageId,
        `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${page.width} ${page.height}] /Contents ${contentId} 0 R /Resources << >> >>`
      )
    )
    parts.push(obj(contentId, `<< /Length ${stream.length} >>\nstream\n${stream}endstream`))
  }

  let offset = 0
  const offsets: number[] = [0]
  for (let i = 1; i < parts.length; i++) {
    offset += Buffer.byteLength(parts[i - 1], 'latin1')
    offsets.push(offset)
  }
  const body = parts.join('')
  const xrefStart = Buffer.byteLength(body, 'latin1')
  const count = pages.length * 2 + 3 // catalog + pages + each (page + contents)

  let xref = `xref\n0 ${count}\n`
  xref += '0000000000 65535 f \n'
  for (let i = 1; i < count; i++) {
    xref += `${String(offsets[i]).padStart(10, '0')} 00000 n \n`
  }
  const tail = `${xref}trailer\n<< /Size ${count} /Root 1 0 R >>\nstartxref\n${xrefStart}\n%%EOF\n`
  return Buffer.from(body + tail, 'latin1')
}
