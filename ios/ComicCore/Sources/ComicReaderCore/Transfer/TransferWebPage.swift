import Foundation

// MARK: - 局域网传输的网页（服务端内置，无任何外部资源）
//
// 单页面：上传（拖拽 / 多选、进度、重试）与书架下载。
// 页面以 / 结尾提供，所有接口都用相对路径。
// 模板用占位符替换，设备名经过 HTML 转义（设备名是用户可改的自由文本，防 XSS）。

public enum TransferWebPage {
    /// 主页面：设备名与书架数量由服务端填入
    public static func app(deviceName: String, libraryCount: Int) -> String {
        appTemplate
            .replacingOccurrences(of: "{{DEVICE_NAME}}", with: htmlEscape(deviceName))
            .replacingOccurrences(of: "{{LIBRARY_COUNT}}", with: String(libraryCount))
    }

    /// HTML 文本转义
    public static func htmlEscape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for char in value {
            switch char {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(char)
            }
        }
        return out
    }

    // MARK: - 主页面

    private static let appTemplate = #"""
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<title>局域网传输 · 漫画阅读器</title>
<style>
  :root {
    --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; --muted: #6e6e73;
    --line: rgba(0,0,0,.10); --accent: #3b82f6; --accent-soft: rgba(59,130,246,.14);
    --ok: #16a34a; --bad: #dc2626; --warn: #d97706; --bar: rgba(59,130,246,.16);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0b0b0c; --card: #161618; --text: #f5f5f7; --muted: #a1a1a6;
      --line: rgba(255,255,255,.12); --accent-soft: rgba(59,130,246,.22);
      --ok: #4ade80; --bad: #f87171; --warn: #fbbf24; --bar: rgba(59,130,246,.24);
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--text);
    font: 15px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
  }
  header {
    max-width: 1000px; margin: 0 auto; padding: 22px 18px 6px;
    display: flex; align-items: baseline; justify-content: space-between; gap: 12px; flex-wrap: wrap;
  }
  .brand { font-size: 17px; font-weight: 700; letter-spacing: -.2px; }
  .brand span { color: var(--accent); }
  .device { color: var(--muted); font-size: 12.5px; }
  main {
    max-width: 1000px; margin: 0 auto; padding: 12px 18px 32px;
    display: grid; grid-template-columns: 1fr 1fr; gap: 16px; align-items: start;
  }
  @media (max-width: 780px) { main { grid-template-columns: 1fr; } }
  .card {
    background: var(--card); border: 1px solid var(--line); border-radius: 18px;
    padding: 18px 18px 16px; box-shadow: 0 10px 30px rgba(0,0,0,.05);
  }
  h2 { margin: 0 0 4px; font-size: 16px; letter-spacing: -.1px; }
  .hint { margin: 0 0 14px; color: var(--muted); font-size: 12.5px; }
  .drop {
    position: relative; border: 1.5px dashed var(--line); border-radius: 14px;
    padding: 30px 16px; text-align: center; cursor: pointer; outline: none;
    transition: border-color .15s ease, background .15s ease;
  }
  .drop:hover, .drop:focus-visible { border-color: var(--accent); background: var(--accent-soft); }
  .drop.over { border-color: var(--accent); background: var(--accent-soft); }
  .dropIcon { font-size: 26px; line-height: 1; }
  .dropTitle { margin-top: 8px; font-weight: 600; font-size: 14px; }
  .dropSub { color: var(--muted); font-size: 12.5px; margin-top: 2px; }
  .fileInput { position: absolute; width: 1px; height: 1px; opacity: 0; overflow: hidden; pointer-events: none; }
  .queue { margin-top: 8px; }
  .row { padding: 11px 0 10px; border-bottom: 1px solid var(--line); }
  .row:last-child { border-bottom: 0; }
  .rowTop { display: flex; align-items: baseline; gap: 10px; }
  .name { flex: 1; min-width: 0; font-size: 13.5px; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .size { color: var(--muted); font-size: 11.5px; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .bar { height: 5px; border-radius: 999px; background: var(--bar); margin-top: 8px; overflow: hidden; }
  .fill { height: 100%; width: 0%; border-radius: 999px; background: var(--accent); transition: width .12s linear; }
  .fill.indeterminate { width: 100% !important; animation: pulse 1.1s ease-in-out infinite; }
  @keyframes pulse { 0%,100% { opacity: .35; } 50% { opacity: 1; } }
  .rowBottom { display: flex; align-items: center; gap: 8px; margin-top: 5px; }
  .state { flex: 1; color: var(--muted); font-size: 11.5px; }
  .pct { color: var(--muted); font-size: 11.5px; font-variant-numeric: tabular-nums; }
  .row.ok .state { color: var(--ok); }
  .row.warn .state { color: var(--warn); }
  .row.bad .state { color: var(--bad); }
  .row.ok .fill { background: var(--ok); }
  .row.bad .fill { background: var(--bad); }
  .retry {
    border: 1px solid var(--line); background: transparent; color: var(--accent);
    border-radius: 8px; font-size: 11.5px; padding: 3px 9px; cursor: pointer;
  }
  .summary { margin-top: 12px; color: var(--muted); font-size: 12.5px; }
  .libHead { display: flex; align-items: center; gap: 8px; margin-bottom: 12px; }
  .libHead h2 { flex: 1; margin: 0; }
  .search {
    width: 150px; padding: 7px 10px; border-radius: 9px; border: 1px solid var(--line);
    background: transparent; color: var(--text); font-size: 12.5px; outline: none;
  }
  .search:focus { border-color: var(--accent); }
  .ghost {
    border: 1px solid var(--line); background: transparent; color: var(--text);
    border-radius: 9px; padding: 6px 10px; font-size: 12px; cursor: pointer;
  }
  .ghost:hover { border-color: var(--accent); color: var(--accent); }
  .libList { max-height: 520px; overflow: auto; -webkit-overflow-scrolling: touch; }
  .libRow { display: flex; align-items: center; gap: 11px; padding: 9px 0; border-bottom: 1px solid var(--line); }
  .libRow:last-child { border-bottom: 0; }
  .cover {
    width: 42px; height: 58px; border-radius: 7px; background: var(--accent-soft);
    flex: 0 0 auto; display: flex; align-items: center; justify-content: center;
    font-size: 18px; overflow: hidden; color: var(--muted);
  }
  .cover img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .meta { flex: 1; min-width: 0; }
  .title { font-size: 13.5px; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sub { color: var(--muted); font-size: 11.5px; margin-top: 2px; }
  .dl {
    flex: 0 0 auto; color: var(--accent); text-decoration: none; font-size: 12.5px;
    border: 1px solid var(--line); border-radius: 8px; padding: 5px 10px;
    background: none; cursor: pointer; font-family: inherit;
  }
  .dl:hover { border-color: var(--accent); background: var(--accent-soft); }
  .dl.danger { color: var(--bad); }
  .dl.danger:hover { border-color: var(--bad); background: rgba(220,38,38,.10); }
  .empty { color: var(--muted); font-size: 13px; text-align: center; padding: 26px 8px; }
  .empty.bad { color: var(--bad); }
  footer { max-width: 1000px; margin: 0 auto; padding: 0 18px 40px; color: var(--muted); font-size: 11.5px; line-height: 1.7; }
  .hidden { display: none !important; }
</style>
</head>
<body>
<header>
  <div class="brand"><span>📖</span> 漫画阅读器 · 局域网传输</div>
  <div class="device">{{DEVICE_NAME}} · 书架 {{LIBRARY_COUNT}} 本</div>
</header>
<main>
  <section class="card">
    <h2>传入漫画</h2>
    <p class="hint">支持 ZIP / CBZ / RAR / CBR / PDF，可多选或拖拽。上传完成后会自动导入手机书架。</p>
    <div id="drop" class="drop" tabindex="0" role="button" aria-label="选择或拖入漫画文件">
      <div class="dropIcon">⬆️</div>
      <div class="dropTitle">把文件拖到这里</div>
      <div class="dropSub">或点击选择文件（可多选）</div>
      <input id="picker" class="fileInput" type="file" multiple
             accept=".zip,.cbz,.rar,.cbr,.pdf,application/zip,application/pdf,application/x-rar-compressed">
    </div>
    <div id="queue" class="queue" aria-live="polite"></div>
    <div id="summary" class="summary hidden" aria-live="polite"></div>
  </section>

  <section class="card">
    <div class="libHead">
      <h2>书架</h2>
      <input id="search" class="search" type="search" placeholder="筛选标题…" autocomplete="off">
      <button id="reloadLib" class="ghost" type="button">刷新</button>
    </div>
    <div id="libList" class="libList"><div class="empty">正在读取书架…</div></div>
  </section>
</main>
<footer>
  传输期间请保持手机上的「局域网传输」页面打开；App 进入后台会自动停止。<br>
  书架里的文件夹漫画会在下载时自动打包成 ZIP。改名 / 删除会直接作用于手机书架（删除会连同来源文件，原件仍在电脑上）。
</footer>
<script>
(function () {
  'use strict';

  var MAX_PARALLEL = 2;
  var POLL_MS = 1200;
  var BASE = './';
  var ALLOWED = { zip: 1, cbz: 1, rar: 1, cbr: 1, pdf: 1 };

  var items = [];
  var active = 0;
  var pollTimer = null;
  var pollFailures = 0;
  var needLibraryRefresh = false;

  var drop = document.getElementById('drop');
  var picker = document.getElementById('picker');
  var queueEl = document.getElementById('queue');
  var summaryEl = document.getElementById('summary');
  var libList = document.getElementById('libList');
  var searchEl = document.getElementById('search');
  var reloadEl = document.getElementById('reloadLib');

  var libraryCache = [];
  var searchTimer = null;

  // ---------- 工具 ----------

  function formatSize(bytes) {
    if (!isFinite(bytes) || bytes < 0) return '—';
    if (bytes < 1024) return bytes + ' B';
    var units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var index = 0;
    while (value >= 1024 && index < units.length - 1) { value /= 1024; index++; }
    var digits = value >= 100 ? 0 : value >= 10 ? 1 : 2;
    return value.toFixed(digits) + ' ' + units[index];
  }

  function formatSpeed(bytesPerSecond) {
    if (!isFinite(bytesPerSecond) || bytesPerSecond <= 0) return '';
    return formatSize(bytesPerSecond) + '/s';
  }

  function extOf(name) {
    var index = name.lastIndexOf('.');
    return index >= 0 ? name.slice(index + 1).toLowerCase() : '';
  }

  function stateText(state, reason) {
    switch (state) {
      case 'pending': return '等待上传';
      case 'receiving': return '上传中…';
      case 'importing': return '已上传，正在导入…';
      case 'imported': return '已导入书架';
      case 'skipped': return '已上传（' + (reason || '已在书架中') + '）';
      case 'saved': return '已保存到 Comics（未自动导入）';
      case 'failed': return '失败：' + (reason || '未知原因');
      case 'uploadfailed': return '未上传：' + (reason || '未知原因');
      default: return reason || state || '';
    }
  }

  // ---------- 上传队列 ----------

  function Item(file) {
    this.file = file;
    this.size = file.size || 0;
    this.loaded = 0;
    this.state = 'pending';
    this.reason = '';
    this.id = null;
    this.xhr = null;
    this.startedAt = 0;
    this.retryButton = null;
    this.ui = createRow(file);
  }

  function createRow(file) {
    var row = document.createElement('div');
    row.className = 'row';

    var top = document.createElement('div');
    top.className = 'rowTop';
    var name = document.createElement('span');
    name.className = 'name';
    name.textContent = file.name;
    name.title = file.name;
    var size = document.createElement('span');
    size.className = 'size';
    size.textContent = formatSize(file.size || 0);
    top.appendChild(name);
    top.appendChild(size);

    var bar = document.createElement('div');
    bar.className = 'bar';
    var fill = document.createElement('div');
    fill.className = 'fill';
    bar.appendChild(fill);

    var bottom = document.createElement('div');
    bottom.className = 'rowBottom';
    var state = document.createElement('span');
    state.className = 'state';
    state.textContent = '等待上传';
    var pct = document.createElement('span');
    pct.className = 'pct';
    bottom.appendChild(state);
    bottom.appendChild(pct);

    row.appendChild(top);
    row.appendChild(bar);
    row.appendChild(bottom);
    queueEl.appendChild(row);
    return { row: row, fill: fill, state: state, pct: pct, size: size, bottom: bottom };
  }

  function updateItem(item) {
    var ui = item.ui;
    var receiving = item.state === 'receiving';
    var pct = item.size > 0 ? Math.min(100, item.loaded / item.size * 100) : (receiving ? -1 : 0);
    if (pct < 0) {
      ui.fill.classList.add('indeterminate');
      ui.pct.textContent = '';
    } else {
      ui.fill.classList.remove('indeterminate');
      ui.fill.style.width = pct.toFixed(1) + '%';
      ui.pct.textContent = pct.toFixed(0) + '%';
    }
    if (!receiving) {
      ui.size.textContent = formatSize(item.size);
    }
    ui.state.textContent = stateText(item.state, item.reason);
    ui.row.classList.toggle('ok', item.state === 'imported');
    ui.row.classList.toggle('warn', item.state === 'skipped' || item.state === 'saved');
    ui.row.classList.toggle('bad', item.state === 'failed' || item.state === 'uploadfailed');
  }

  function addRejected(name, reason) {
    var item = new Item({ name: name, size: 0 });
    item.state = 'uploadfailed';
    item.reason = reason;
    updateItem(item);
    items.push(item);
    updateSummary();
    return item;
  }

  function addFiles(fileList) {
    var accepted = 0;
    for (var i = 0; i < fileList.length; i++) {
      var file = fileList[i];
      if (!ALLOWED[extOf(file.name)]) {
        addRejected(file.name, '只支持 ZIP / CBZ / RAR / CBR / PDF');
        continue;
      }
      if (!file.size) {
        addRejected(file.name, '文件为空');
        continue;
      }
      items.push(new Item(file));
      accepted++;
    }
    if (accepted > 0) pump();
    updateSummary();
  }

  function pump() {
    while (active < MAX_PARALLEL) {
      var next = null;
      for (var i = 0; i < items.length; i++) {
        if (items[i].state === 'pending') { next = items[i]; break; }
      }
      if (!next) return;
      startUpload(next);
    }
  }

  function startUpload(item) {
    active++;
    item.state = 'receiving';
    item.loaded = 0;
    item.reason = '';
    item.startedAt = performance.now();
    updateItem(item);

    var xhr = new XMLHttpRequest();
    item.xhr = xhr;
    xhr.open('PUT', BASE + 'upload?name=' + encodeURIComponent(item.file.name), true);
    xhr.responseType = 'text';
    try {
      xhr.setRequestHeader('Content-Type', item.file.type || 'application/octet-stream');
    } catch (ignore) {}

    xhr.upload.onprogress = function (event) {
      if (!event.lengthComputable) return;
      item.loaded = event.loaded;
      var elapsed = (performance.now() - item.startedAt) / 1000;
      var speed = elapsed > 0.25 ? event.loaded / elapsed : 0;
      var pct = item.size > 0 ? Math.min(100, event.loaded / item.size * 100) : 0;
      item.ui.fill.classList.remove('indeterminate');
      item.ui.fill.style.width = pct.toFixed(1) + '%';
      item.ui.pct.textContent = pct.toFixed(0) + '%';
      item.ui.size.textContent = formatSize(event.loaded) + ' / ' + formatSize(item.size) +
        (speed > 0 ? ' · ' + formatSpeed(speed) : '');
    };

    xhr.onload = function () {
      active--;
      item.xhr = null;
      var data = null;
      try { data = JSON.parse(xhr.responseText || '{}'); } catch (ignore) {}
      if (xhr.status >= 200 && xhr.status < 300 && data && data.id) {
        item.id = data.id;
        item.state = 'importing';
        item.loaded = item.size;
        updateItem(item);
        needLibraryRefresh = true;
        schedulePoll();
      } else {
        failUpload(item, (data && data.error) || ('上传失败（HTTP ' + xhr.status + '）'));
      }
      pump();
      updateSummary();
    };
    xhr.onerror = function () {
      active--;
      item.xhr = null;
      failUpload(item, '网络中断，请重试');
      pump();
      updateSummary();
    };
    xhr.onabort = function () {
      active--;
      item.xhr = null;
      failUpload(item, '上传已取消');
      pump();
      updateSummary();
    };
    xhr.ontimeout = function () {
      active--;
      item.xhr = null;
      failUpload(item, '上传超时');
      pump();
      updateSummary();
    };

    xhr.send(item.file);
    updateSummary();
  }

  function failUpload(item, reason) {
    item.state = 'uploadfailed';
    item.reason = reason;
    updateItem(item);
    if (!item.retryButton && item.file && item.file.size) {
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'retry';
      button.textContent = '重试';
      button.addEventListener('click', function () {
        button.remove();
        item.retryButton = null;
        item.state = 'pending';
        item.loaded = 0;
        item.reason = '';
        updateItem(item);
        pump();
        updateSummary();
      });
      item.retryButton = button;
      item.ui.bottom.appendChild(button);
    }
  }

  function updateSummary() {
    if (items.length === 0) {
      summaryEl.classList.add('hidden');
      summaryEl.textContent = '';
      return;
    }
    var total = 0;
    var loaded = 0;
    var done = 0;
    var failed = 0;
    var running = 0;
    for (var i = 0; i < items.length; i++) {
      var item = items[i];
      total += item.size || 0;
      loaded += Math.min(item.loaded || 0, item.size || 0);
      if (item.state === 'imported' || item.state === 'skipped' || item.state === 'saved') done++;
      else if (item.state === 'failed' || item.state === 'uploadfailed') failed++;
      else running++;
    }
    var parts = ['共 ' + items.length + ' 个文件'];
    if (done) parts.push('已完成 ' + done);
    if (failed) parts.push('失败 ' + failed);
    if (running) parts.push('进行中 ' + running);
    if (total > 0) parts.push(formatSize(loaded) + ' / ' + formatSize(total));
    summaryEl.textContent = parts.join(' · ');
    summaryEl.classList.remove('hidden');
  }

  // ---------- 状态轮询 ----------

  function schedulePoll() {
    if (pollTimer) return;
    pollTimer = setTimeout(pollState, POLL_MS);
  }

  function pollState() {
    pollTimer = null;
    fetch(BASE + 'state', { cache: 'no-store' })
      .then(function (response) { return response.json(); })
      .then(function (data) {
        pollFailures = 0;
        var uploads = (data && data.uploads) || [];
        var byId = {};
        for (var i = 0; i < uploads.length; i++) byId[uploads[i].id] = uploads[i];

        var waiting = false;
        for (var j = 0; j < items.length; j++) {
          var item = items[j];
          if (!item.id) continue;
          var record = byId[item.id];
          if (!record) continue;
          if (record.size > 0) item.size = record.size;
          if (record.received > 0) item.loaded = record.received;
          item.state = record.state;
          item.reason = record.reason || '';
          updateItem(item);
          if (record.state === 'receiving' || record.state === 'importing') waiting = true;
          if (record.state === 'imported' || record.state === 'skipped' || record.state === 'saved') {
            needLibraryRefresh = true;
          }
        }

        updateSummary();
        if (waiting) {
          schedulePoll();
        } else if (needLibraryRefresh) {
          needLibraryRefresh = false;
          loadLibrary();
        }
      })
      .catch(function () {
        // 服务端可能已停止或网络切换；仍有导入中的条目就再试几次
        pollFailures++;
        var pending = items.some(function (item) { return item.state === 'importing'; });
        if (pending && pollFailures < 5) schedulePoll();
      });
  }

  // ---------- 书架 ----------

  function loadLibrary() {
    libList.textContent = '';
    var loading = document.createElement('div');
    loading.className = 'empty';
    loading.textContent = '正在读取书架…';
    libList.appendChild(loading);

    fetch(BASE + 'library', { cache: 'no-store' })
      .then(function (response) { return response.json(); })
      .then(function (data) {
        libraryCache = (data && data.comics) || [];
        renderLibrary();
      })
      .catch(function () {
        libList.textContent = '';
        var error = document.createElement('div');
        error.className = 'empty bad';
        error.textContent = '读取书架失败，请点「刷新」重试';
        libList.appendChild(error);
      });
  }

  function renderLibrary() {
    var query = (searchEl.value || '').trim().toLowerCase();
    var list = [];
    for (var i = 0; i < libraryCache.length; i++) {
      var comic = libraryCache[i];
      var title = (comic.title || '').toLowerCase();
      if (!query || title.indexOf(query) >= 0) list.push(comic);
    }

    libList.textContent = '';
    if (list.length === 0) {
      var empty = document.createElement('div');
      empty.className = 'empty';
      empty.textContent = libraryCache.length === 0 ? '书架还是空的' : '没有匹配的漫画';
      libList.appendChild(empty);
      return;
    }

    for (var j = 0; j < list.length; j++) {
      var entry = list[j];
      var row = document.createElement('div');
      row.className = 'libRow';

      var cover = document.createElement('div');
      cover.className = 'cover';
      if (entry.hasCover) {
        var image = document.createElement('img');
        image.alt = '';
        image.loading = 'lazy';
        image.src = BASE + 'cover/' + encodeURIComponent(entry.id);
        image.addEventListener('error', function () {
          // 用 cover.textContent 替换整棵子树（此时 image 已经可能被移除）
          cover.textContent = '📖';
        });
        cover.appendChild(image);
      } else {
        cover.textContent = '📖';
      }

      var meta = document.createElement('div');
      meta.className = 'meta';
      var titleEl = document.createElement('div');
      titleEl.className = 'title';
      titleEl.textContent = entry.title || '未命名';
      titleEl.title = entry.title || '';
      var sub = document.createElement('div');
      sub.className = 'sub';
      sub.textContent = (entry.pages || 0) + ' 页' +
        (entry.size ? ' · ' + formatSize(entry.size) : (entry.kind === 'folder' ? ' · 文件夹' : ''));
      meta.appendChild(titleEl);
      meta.appendChild(sub);

      var download = document.createElement('a');
      download.className = 'dl';
      download.textContent = '下载';
      download.href = BASE + 'download/' + encodeURIComponent(entry.id);
      download.setAttribute('download', '');

      var renameBtn = document.createElement('button');
      renameBtn.type = 'button';
      renameBtn.className = 'dl';
      renameBtn.textContent = '改名';
      renameBtn.addEventListener('click', makeRenameHandler(entry));

      var deleteBtn = document.createElement('button');
      deleteBtn.type = 'button';
      deleteBtn.className = 'dl danger';
      deleteBtn.textContent = '删除';
      deleteBtn.addEventListener('click', makeDeleteHandler(entry));

      row.appendChild(cover);
      row.appendChild(meta);
      row.appendChild(download);
      row.appendChild(renameBtn);
      row.appendChild(deleteBtn);
      libList.appendChild(row);
    }
  }

  function makeRenameHandler(entry) {
    return function () {
      var next = window.prompt('把《' + (entry.title || '未命名') + '》改名为：', entry.title || '');
      if (next === null) return;
      var trimmed = next.trim();
      if (!trimmed || trimmed === entry.title) return;
      fetch(BASE + 'rename/' + encodeURIComponent(entry.id) + '?title=' + encodeURIComponent(trimmed), { method: 'POST' })
        .then(function (res) { if (!res.ok) throw new Error('rename'); })
        .then(function () { loadLibrary(); })
        .catch(function () { window.alert('改名失败，请重试'); });
    };
  }

  function makeDeleteHandler(entry) {
    return function () {
      if (!window.confirm('删除《' + (entry.title || '未命名') + '》？\n手机上的来源文件会一并删除（原件仍在你的电脑上）。')) return;
      fetch(BASE + 'remove/' + encodeURIComponent(entry.id), { method: 'POST' })
        .then(function (res) { if (!res.ok) throw new Error('remove'); })
        .then(function () { loadLibrary(); })
        .catch(function () { window.alert('删除失败，请重试'); });
    };
  }

  // ---------- 事件 ----------

  ['dragenter', 'dragover'].forEach(function (name) {
    drop.addEventListener(name, function (event) {
      event.preventDefault();
      event.stopPropagation();
      drop.classList.add('over');
    });
  });
  ['dragleave', 'drop'].forEach(function (name) {
    drop.addEventListener(name, function (event) {
      event.preventDefault();
      event.stopPropagation();
      drop.classList.remove('over');
    });
  });
  drop.addEventListener('drop', function (event) {
    var transfer = event.dataTransfer;
    if (!transfer) return;
    if (transfer.items && transfer.items.length) {
      for (var i = 0; i < transfer.items.length; i++) {
        var entry = transfer.items[i].webkitGetAsEntry && transfer.items[i].webkitGetAsEntry();
        if (entry && entry.isDirectory) {
          addRejected(entry.name || '文件夹', '暂不支持直接传文件夹，请先压缩成 ZIP');
        }
      }
    }
    if (transfer.files && transfer.files.length) addFiles(transfer.files);
  });
  drop.addEventListener('click', function () { picker.click(); });
  drop.addEventListener('keydown', function (event) {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      picker.click();
    }
  });
  picker.addEventListener('change', function () {
    if (picker.files && picker.files.length) addFiles(picker.files);
    picker.value = '';
  });

  window.addEventListener('dragover', function (event) { event.preventDefault(); });
  window.addEventListener('drop', function (event) { event.preventDefault(); });

  searchEl.addEventListener('input', function () {
    if (searchTimer) clearTimeout(searchTimer);
    searchTimer = setTimeout(renderLibrary, 150);
  });
  reloadEl.addEventListener('click', loadLibrary);

  loadLibrary();
})();
</script>
</body>
</html>
"""#
}
