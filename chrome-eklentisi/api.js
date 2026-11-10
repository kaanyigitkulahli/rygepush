// RygePush sunucusuyla (Google Apps Script) konuşan ortak kod. Açılır pencere ve arka plan birlikte kullanır.

export const MAX_BYTES = 100 * 1024 * 1024 * 1024;
const CHUNK = 32 * 1024 * 1024; // Drive için 256 KB'nin katı olmalı

export async function getSettings() {
  const s = await chrome.storage.local.get(['url', 'key', 'name', 'deviceId']);
  if (!s.deviceId) {
    s.deviceId = 'c' + crypto.randomUUID().replace(/-/g, '').slice(0, 20);
    await chrome.storage.local.set({ deviceId: s.deviceId });
  }
  return s;
}

export function isConfigured(s) {
  return !!(s && s.url && s.key);
}

export function validURL(url) {
  return /^https:\/\/script\.google\.com\/.+\/exec$/.test(String(url || '').trim());
}

async function post(url, body) {
  let response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain;charset=utf-8' },
      body: JSON.stringify(body),
    });
  } catch (e) {
    throw new Error('Sunucuya ulaşılamadı. İnternet bağlantını kontrol et.');
  }
  let data;
  try { data = await response.json(); } catch (e) {
    throw new Error('Sunucu yanıtı okunamadı. Adresin /exec ile bittiğinden emin ol.');
  }
  if (!data.ok) throw new Error(data.error || 'İstek başarısız oldu.');
  return data;
}

export async function call(body) {
  const s = await getSettings();
  if (!isConfigured(s)) throw new Error('Önce bağlantı ayarlarını gir.');
  return post(s.url, { key: s.key, ...body });
}

/** Bilgileri dener; sunucu kabul ederse kaydeder ve bu cihazı kaydeder. */
export async function connect({ url, key, name }) {
  const s = await getSettings();
  const clean = { url: url.trim(), key: key.trim(), name: (name || 'Chrome').trim() };
  await post(clean.url, { key: clean.key, action: 'sync', deviceId: s.deviceId });
  await chrome.storage.local.set(clean);
  await post(clean.url, { key: clean.key, action: 'register', deviceId: s.deviceId, name: clean.name, kind: 'web', forceName: true });
}

export async function disconnect() {
  const s = await getSettings();
  try { await call({ action: 'removeDevice', deviceId: s.deviceId }); } catch (e) { /* sunucuya ulaşılamasa da yerelden sil */ }
  await chrome.storage.local.remove(['url', 'key', 'cache', 'lastSeen', 'unread']);
  await chrome.action.setBadgeText({ text: '' });
}

export function isLink(text) {
  return /^https?:\/\/\S+$/i.test(String(text || '').trim());
}

/** Bir push gönderir. Dosya varsa önce Drive'a yüklenmiş olmalı (driveId). */
export async function sendPush({ type, title = '', body = '', url = '', target = '', driveId }) {
  const s = await getSettings();
  const req = { action: 'push', source: s.deviceId, target, type, title, body, url };
  if (driveId) req.file = { driveId };
  return call(req);
}

function receivedEnd(response) {
  const h = response.headers.get('Range');
  const m = h && h.match(/bytes=0-(\d+)/);
  return m ? Number(m[1]) + 1 : null;
}

/** Dosyayı Drive'a doğrudan, 32 MB'lık parçalarla yükler. Kopmada kaldığı yerden devam eder. */
export async function uploadFile(file, onProgress) {
  if (file.size > MAX_BYTES) throw new Error('Dosya en fazla 100 GB olabilir.');
  if (!file.size) throw new Error('Dosya boş.');
  const start = await call({ action: 'uploadStart', name: file.name, mime: file.type || 'application/octet-stream', size: file.size });
  let offset = 0;
  let failures = 0;
  while (true) {
    const end = Math.min(offset + CHUNK, file.size);
    try {
      const r = await fetch(start.uploadUrl, {
        method: 'PUT',
        headers: { 'Content-Range': `bytes ${offset}-${end - 1}/${file.size}` },
        body: file.slice(offset, end),
      });
      if (r.status === 200 || r.status === 201) { onProgress?.(1); return (await r.json()).id; }
      if (r.status !== 308) throw new Error('HTTP ' + r.status);
      offset = receivedEnd(r) ?? end;
      failures = 0;
      onProgress?.(offset / file.size);
    } catch (e) {
      if (++failures > 5) throw new Error('Yükleme yarıda kaldı. İnternet bağlantını kontrol edip tekrar dene.');
      await new Promise((resolve) => setTimeout(resolve, 1500 * failures));
      try {
        const q = await fetch(start.uploadUrl, { method: 'PUT', headers: { 'Content-Range': `bytes */${file.size}` } });
        if (q.status === 200 || q.status === 201) { onProgress?.(1); return (await q.json()).id; }
        if (q.status === 308) offset = receivedEnd(q) ?? 0;
      } catch (_) { /* bir sonraki denemede yeniden sorulur */ }
    }
  }
}

export function deviceName(devices, id, myId) {
  if (id === myId) return 'Bu tarayıcı';
  const d = (devices || []).find((x) => x.id === id);
  return d ? d.name : 'Silinmiş cihaz';
}

export function pushTitle(p) {
  if (p.title) return p.title;
  return p.type === 'file' ? 'Dosya' : p.type === 'link' ? 'Link' : 'Not';
}

export function pushText(p) {
  if (p.type === 'file') return p.body || p.fileName;
  if (p.type === 'link') return p.body || p.url;
  return p.body;
}
