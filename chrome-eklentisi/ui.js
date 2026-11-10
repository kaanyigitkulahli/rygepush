import {
  getSettings, isConfigured, validURL, call, connect, disconnect, isLink, sendPush,
  uploadFile, MAX_BYTES, deviceName,
} from './api.js';

const $ = (id) => document.getElementById(id);
const isTab = new URLSearchParams(location.search).has('tab');
if (isTab) document.body.classList.add('tab');

let settings = null;
let pushes = [];
let devices = [];
let filter = 'all';
let pending = null;
let uploading = false;
let pendingDelete = null;
let pollTimer = null;

/* ---------- Yardımcılar ---------- */

function toast(msg) {
  const t = $('toast'); t.textContent = msg; t.hidden = false;
  clearTimeout(toast._); toast._ = setTimeout(() => { t.hidden = true; }, 2200);
}
const size = (b) => b < 1024 ? `${b} B` : b < 1048576 ? `${Math.round(b / 1024)} KB` : b < 1073741824 ? `${(b / 1048576).toFixed(1)} MB` : `${(b / 1073741824).toFixed(2)} GB`;
function dayLabel(ms) {
  const d = new Date(ms), n = new Date(), y = new Date(); y.setDate(n.getDate() - 1);
  if (d.toDateString() === n.toDateString()) return 'Bugün';
  if (d.toDateString() === y.toDateString()) return 'Dün';
  return d.toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric' });
}
const hm = (ms) => new Date(ms).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
function show(view) { for (const v of ['setup', 'main', 'settings']) $(v).hidden = v !== view; }

/* ---------- Açılış ---------- */

async function init() {
  settings = await getSettings();
  if (!isConfigured(settings)) { show('setup'); return; }
  show('main');
  const { cache } = await chrome.storage.local.get('cache');
  if (cache) { pushes = cache.pushes || []; devices = cache.devices || []; renderAll(true); }
  await sync(true);
  pollTimer = setInterval(() => { if (!document.hidden) sync(false); }, 4000);
}

async function markSeen() {
  const newest = Math.max(0, ...pushes.map((p) => p.createdAt));
  await chrome.storage.local.set({ lastSeen: newest, unread: 0 });
  await chrome.action.setBadgeText({ text: '' });
}

async function sync(scroll) {
  try {
    const r = await call({ action: 'sync', deviceId: settings.deviceId });
    const changed = JSON.stringify(r.pushes) !== JSON.stringify(pushes) || JSON.stringify(r.devices) !== JSON.stringify(devices);
    pushes = r.pushes; devices = r.devices;
    await chrome.storage.local.set({ cache: { pushes, devices, at: Date.now() } });
    $('dot').className = 'dot live'; $('st').textContent = 'Canlı';
    if (changed || scroll) renderAll(scroll);
    markSeen();
  } catch (e) {
    $('dot').className = 'dot err'; $('st').textContent = 'Bağlantı yok';
  }
}

/* ---------- Kurulum ---------- */

$('setupForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const url = $('sUrl').value.trim(), key = $('sKey').value.trim(), name = $('sName').value.trim();
  const err = $('setupErr');
  if (!validURL(url)) { err.textContent = 'Adres https://script.google.com/ ile başlayıp /exec ile bitmeli.'; err.hidden = false; return; }
  $('setupBtn').disabled = true; $('setupBtn').textContent = 'Bağlanıyor…'; err.hidden = true;
  try {
    await connect({ url, key, name });
    chrome.runtime.sendMessage({ type: 'check' }).catch(() => {});
    init();
  } catch (ex) {
    err.textContent = ex.message; err.hidden = false;
  }
  $('setupBtn').disabled = false; $('setupBtn').textContent = 'Bağlan';
});

/* ---------- Çizim ---------- */

function renderAll(scroll) { renderChips(); renderTargets(); renderFeed(scroll); }

function renderChips() {
  const box = $('chips'); box.textContent = '';
  const mk = (id, label) => {
    const b = el('button', 'chip', label); b.type = 'button'; b.setAttribute('aria-pressed', filter === id);
    b.addEventListener('click', () => { filter = id; renderChips(); renderFeed(true); });
    box.appendChild(b);
  };
  mk('all', 'Tümü');
  for (const d of devices) if (d.id !== settings.deviceId) mk(d.id, d.name);
  mk('pin', '★ Sabit');
}

function renderTargets() {
  const sel = $('to'); const cur = sel.value;
  sel.textContent = '';
  const add = (v, t) => { const o = el('option', null, t); o.value = v; sel.appendChild(o); };
  add('', 'Tüm cihazlarım');
  for (const d of devices) if (d.id !== settings.deviceId) add(d.id, d.name);
  if ([...sel.options].some((o) => o.value === cur)) sel.value = cur;
  else if (filter !== 'all' && filter !== 'pin') sel.value = filter;
}

function renderFeed(scroll) {
  const feed = $('feed');
  const nearBottom = feed.scrollHeight - feed.scrollTop - feed.clientHeight < 60;
  const list = pushes.filter((p) => filter === 'all' || (filter === 'pin' && p.pinned) || p.source === filter || p.target === filter);
  feed.textContent = '';
  if (!list.length) {
    const e = el('div', 'empty');
    e.append(el('b', null, pushes.length ? 'Burada push yok' : 'İlk pushunu gönder'),
      document.createTextNode(pushes.length ? 'Başka bir cihaz seç.' : 'Aşağıya bir not ya da link yaz, istersen dosya ekle. Telefonuna anında gider.'));
    feed.appendChild(e);
    return;
  }
  let last = '';
  for (const p of list) {
    const dl = dayLabel(p.createdAt);
    if (dl !== last) { feed.appendChild(el('div', 'day', dl)); last = dl; }
    const mine = p.source === settings.deviceId;
    const m = el('div', 'msg ' + (mine ? 'mine' : 'other'));
    const b = el('div', 'bubble');
    if (p.title) b.appendChild(el('span', 't', p.title));
    if (p.type === 'file') {
      const c = el('div', 'card');
      c.appendChild(el('span', 'ext', (p.fileName.split('.').pop() || 'dosya').slice(0, 4)));
      const info = el('span'); info.append(el('b', null, p.fileName), document.createElement('br'), el('span', 'fs', size(p.fileSize)));
      c.appendChild(info); b.appendChild(c);
      if (p.body) b.appendChild(el('div', null, p.body));
    } else if (p.type === 'link') {
      if (p.body) b.appendChild(el('div', null, p.body));
      const a = el('a', null, p.url); a.href = p.url; a.target = '_blank'; a.rel = 'noopener'; b.appendChild(a);
    } else {
      b.appendChild(document.createTextNode(p.body));
    }
    const meta = el('div', 'meta');
    meta.appendChild(el('span', 'from', `${deviceName(devices, p.source, settings.deviceId)} → ${p.target ? deviceName(devices, p.target, settings.deviceId) : 'tümü'}`));
    meta.appendChild(el('span', null, hm(p.createdAt)));
    if (p.pinned) meta.appendChild(el('span', 'pinned', '★'));
    const act = (label, fn, cls) => { const x = el('button', 'act' + (cls ? ' ' + cls : ''), label); x.type = 'button'; x.addEventListener('click', fn); meta.appendChild(x); };
    if (p.type !== 'note') act(p.type === 'file' ? 'Aç' : 'Aç', () => chrome.tabs.create({ url: p.url }));
    act('Kopyala', () => copy(p.type === 'note' ? [p.title, p.body].filter(Boolean).join('\n') : p.url));
    act(p.pinned ? 'Sabitlemeyi kaldır' : 'Sabitle', () => pin(p));
    act(pendingDelete === p.id ? 'Emin misin? Sil' : 'Sil', () => del(p), pendingDelete === p.id ? 'warn' : '');
    m.append(b, meta); feed.appendChild(m);
  }
  if (scroll || nearBottom) feed.scrollTop = feed.scrollHeight;
}

/* ---------- Eylemler ---------- */

async function copy(text) {
  try { await navigator.clipboard.writeText(text); toast('Kopyalandı'); }
  catch (e) { toast('Kopyalanamadı'); }
}
async function pin(p) {
  p.pinned = !p.pinned; renderFeed(false);
  try { await call({ action: 'pin', id: p.id, pinned: p.pinned }); } catch (e) { toast('Kaydedilemedi: ' + e.message); sync(false); }
}
async function del(p) {
  if (pendingDelete !== p.id) {
    pendingDelete = p.id; renderFeed(false);
    clearTimeout(del._); del._ = setTimeout(() => { pendingDelete = null; renderFeed(false); }, 4000);
    return;
  }
  pendingDelete = null; pushes = pushes.filter((x) => x.id !== p.id); renderFeed(false);
  try { await call({ action: 'delete', id: p.id }); toast('Silindi'); } catch (e) { toast('Silinemedi: ' + e.message); sync(false); }
}

$('openTab').addEventListener('click', () => { chrome.tabs.create({ url: chrome.runtime.getURL('ui.html?tab=1') }); window.close(); });
if (isTab) $('openTab').hidden = true;

$('sendPage').addEventListener('click', async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (isTab || !tab || !/^https?:/i.test(tab.url || '')) { toast('Bu sayfa gönderilemez'); return; }
  try {
    await sendPush({ type: 'link', url: tab.url, title: tab.title || '', target: $('to').value });
    toast('Sayfa gönderildi'); sync(true);
  } catch (e) { toast('Gönderilemedi: ' + e.message); }
});
if (isTab) $('sendPage').hidden = true;

/* ---------- Dosya ---------- */

function setFile(f) {
  if (!f) return;
  if (f.size > MAX_BYTES) { toast('Dosya en fazla 100 GB olabilir'); return; }
  if (!f.size) { toast('Dosya boş'); return; }
  pending = f;
  const a = $('attached'); a.hidden = false; a.textContent = '';
  a.appendChild(el('span', 'name', `${f.name} · ${size(f.size)}`));
  if (!isTab && f.size > 50 * 1024 * 1024) {
    const n = el('span', 'note', 'Pencere kapanırsa yükleme durur. ');
    const link = el('a', null, 'Sekmede aç'); link.href = '#';
    link.addEventListener('click', (e) => { e.preventDefault(); chrome.tabs.create({ url: chrome.runtime.getURL('ui.html?tab=1') }); });
    n.appendChild(link); a.appendChild(n);
  }
  const x = el('button', 'act', 'Kaldır'); x.type = 'button';
  x.addEventListener('click', () => { if (!uploading) { pending = null; a.hidden = true; } });
  a.appendChild(x);
}
$('attachBtn').addEventListener('click', () => $('fileIn').click());
$('fileIn').addEventListener('change', (e) => { setFile(e.target.files[0]); e.target.value = ''; });
document.addEventListener('dragover', (e) => e.preventDefault());
document.addEventListener('drop', (e) => { e.preventDefault(); const f = e.dataTransfer?.files?.[0]; if (f) setFile(f); });
$('txt').addEventListener('paste', (e) => { const f = [...(e.clipboardData?.files || [])][0]; if (f) { e.preventDefault(); setFile(f); } });
$('txt').addEventListener('input', (e) => { e.target.style.height = 'auto'; e.target.style.height = Math.min(e.target.scrollHeight, 120) + 'px'; });
$('txt').addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('compose').requestSubmit(); } });
window.addEventListener('beforeunload', (e) => { if (uploading) { e.preventDefault(); e.returnValue = ''; } });

$('compose').addEventListener('submit', async (e) => {
  e.preventDefault();
  const text = $('txt').value.trim(); const target = $('to').value;
  if (!text && !pending) return;
  const btn = $('sendBtn'); btn.disabled = true; btn.textContent = pending ? 'Yükleniyor…' : 'Gönderiliyor…';
  try {
    if (pending) {
      uploading = true;
      const driveId = await uploadFile(pending, (p) => { btn.textContent = '%' + Math.floor(p * 100);
        $('attached').querySelector('.name').textContent = `${pending.name} · ${size(Math.round(p * pending.size))} / ${size(pending.size)}`; });
      btn.textContent = 'Gönderiliyor…';
      await sendPush({ type: 'file', body: text, target, driveId });
    } else if (isLink(text)) {
      await sendPush({ type: 'link', url: text, target });
    } else {
      await sendPush({ type: 'note', body: text, target });
    }
    $('txt').value = ''; $('txt').style.height = 'auto'; pending = null; $('attached').hidden = true;
    await sync(true);
  } catch (err) {
    toast('Gönderilemedi: ' + err.message);
  }
  uploading = false; btn.disabled = false; btn.textContent = 'Gönder';
});

/* ---------- Ayarlar ---------- */

$('openSettings').addEventListener('click', () => {
  show('settings');
  $('myName').value = settings.name || '';
  $('serverInfo').textContent = settings.url;
  const list = $('devList'); list.textContent = '';
  for (const d of devices) {
    const li = el('li');
    const left = el('span'); left.append(el('b', null, d.id === settings.deviceId ? `${d.name} (bu tarayıcı)` : d.name), document.createElement('br'), el('span', 'sub', d.kind === 'ios' ? 'iPhone' : 'Tarayıcı'));
    const mins = d.lastSeen ? Math.round((Date.now() - d.lastSeen) / 60000) : null;
    li.append(left, el('span', 'sub', mins === null ? '' : mins < 2 ? 'şimdi çevrimiçi' : mins < 60 ? `${mins} dk önce` : `${Math.round(mins / 60)} sa önce`));
    list.appendChild(li);
  }
});
$('closeSettings').addEventListener('click', () => show('main'));
$('renameForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const name = $('myName').value.trim(); if (!name) return;
  try {
    await call({ action: 'rename', deviceId: settings.deviceId, name });
    await chrome.storage.local.set({ name }); settings.name = name; toast('Ad kaydedildi'); sync(false);
  } catch (ex) { toast('Kaydedilemedi: ' + ex.message); }
});
let confirmDisconnect = false;
$('disconnect').addEventListener('click', async () => {
  const b = $('disconnect');
  if (!confirmDisconnect) { confirmDisconnect = true; b.textContent = 'Emin misin? Bağlantıyı kes'; setTimeout(() => { confirmDisconnect = false; b.textContent = 'Bu tarayıcının bağlantısını kes'; }, 4000); return; }
  clearInterval(pollTimer);
  await disconnect();
  pushes = []; devices = [];
  init();
});

init();
