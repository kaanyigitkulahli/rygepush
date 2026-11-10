// Arka plan: 30 saniyede bir yeni push var mı bakar, bildirim gösterir, sağ tık menüsünü yönetir.
import { getSettings, isConfigured, call, sendPush, pushTitle, pushText, deviceName } from './api.js';

const ALARM = 'senkron';

chrome.runtime.onInstalled.addListener(start);
chrome.runtime.onStartup.addListener(start);
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && (changes.url || changes.key)) start();
});

async function start() {
  await chrome.alarms.create(ALARM, { periodInMinutes: 0.5 });
  await chrome.action.setBadgeBackgroundColor({ color: '#1f6bff' });
  await rebuildMenus();
  check();
}

chrome.alarms.onAlarm.addListener((alarm) => { if (alarm.name === ALARM) check(); });

chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
  if (msg && msg.type === 'check') { check().then(() => reply({ ok: true })); return true; }
  return false;
});

/* ---------- Yeni pushları kontrol et ---------- */

async function check() {
  const s = await getSettings();
  if (!isConfigured(s)) { await rebuildMenus(); return; }
  let r;
  try { r = await call({ action: 'sync', deviceId: s.deviceId }); }
  catch (e) { await chrome.action.setBadgeText({ text: '!' }); return; }

  const old = (await chrome.storage.local.get('cache')).cache;
  await chrome.storage.local.set({ cache: { pushes: r.pushes, devices: r.devices, at: Date.now() } });
  if (!old || JSON.stringify(old.devices) !== JSON.stringify(r.devices)) await rebuildMenus(r.devices, s.deviceId);

  const { lastSeen = 0, unread = 0 } = await chrome.storage.local.get(['lastSeen', 'unread']);
  const newest = Math.max(0, ...r.pushes.map((p) => p.createdAt));
  if (!lastSeen) { // ilk çalışma: eskileri bildirme
    await chrome.storage.local.set({ lastSeen: newest });
    await chrome.action.setBadgeText({ text: '' });
    return;
  }
  const fresh = r.pushes.filter((p) => p.createdAt > lastSeen && p.source !== s.deviceId && (!p.target || p.target === s.deviceId));
  if (!fresh.length) {
    await chrome.action.setBadgeText({ text: unread ? String(unread) : '' });
    return;
  }
  const total = unread + fresh.length;
  await chrome.storage.local.set({ lastSeen: newest, unread: total });
  await chrome.action.setBadgeText({ text: total > 99 ? '99+' : String(total) });
  for (const p of fresh.slice(-5)) {
    chrome.notifications.create('p:' + p.id, {
      type: 'basic',
      iconUrl: 'icons/icon128.png',
      title: `${deviceName(r.devices, p.source, s.deviceId)} · ${pushTitle(p)}`,
      message: (pushText(p) || '').slice(0, 300),
      priority: 1,
    });
  }
}

chrome.notifications.onClicked.addListener(async (id) => {
  chrome.notifications.clear(id);
  if (!id.startsWith('p:')) return;
  const { cache } = await chrome.storage.local.get('cache');
  const p = cache && cache.pushes.find((x) => x.id === id.slice(2));
  if (p && (p.type === 'link' || p.type === 'file') && p.url) {
    chrome.tabs.create({ url: p.url });
  } else {
    try { await chrome.action.openPopup(); }
    catch (e) { chrome.tabs.create({ url: chrome.runtime.getURL('ui.html?tab=1') }); }
  }
});

/* ---------- Sağ tık menüsü: "RygePush'a gönder" ---------- */

async function rebuildMenus(devices, myId) {
  await chrome.contextMenus.removeAll();
  const s = await getSettings();
  if (!isConfigured(s)) return;
  if (!devices) devices = ((await chrome.storage.local.get('cache')).cache || {}).devices || [];
  myId = myId || s.deviceId;
  const contexts = ['page', 'link', 'selection', 'image'];
  chrome.contextMenus.create({ id: 'rp', title: "RygePush'a gönder", contexts });
  chrome.contextMenus.create({ id: 'rp:', parentId: 'rp', title: 'Tüm cihazlarım', contexts });
  const others = devices.filter((d) => d.id !== myId);
  if (others.length) chrome.contextMenus.create({ id: 'rp-sep', parentId: 'rp', type: 'separator', contexts });
  for (const d of others) {
    chrome.contextMenus.create({ id: 'rp:' + d.id, parentId: 'rp', title: d.name, contexts });
  }
}

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (typeof info.menuItemId !== 'string' || !info.menuItemId.startsWith('rp:')) return;
  const target = info.menuItemId.slice(3);
  let payload;
  if (info.selectionText) payload = { type: 'note', body: info.selectionText, title: tab && tab.title ? 'Seçili metin' : '' };
  else if (info.linkUrl) payload = { type: 'link', url: info.linkUrl };
  else if (info.srcUrl && /^https?:/i.test(info.srcUrl)) payload = { type: 'link', url: info.srcUrl, title: 'Resim' };
  else if (tab && /^https?:/i.test(tab.url || '')) payload = { type: 'link', url: tab.url, title: tab.title || '' };
  if (!payload) return notifyResult(false, 'Bu sayfa gönderilemez.');
  await deliver({ ...payload, target });
});

chrome.commands.onCommand.addListener(async (command, tab) => {
  if (command !== 'send-page') return;
  if (!tab || !/^https?:/i.test(tab.url || '')) return notifyResult(false, 'Bu sayfa gönderilemez.');
  await deliver({ type: 'link', url: tab.url, title: tab.title || '', target: '' });
});

async function deliver(payload) {
  try {
    await sendPush(payload);
    notifyResult(true, payload.type === 'note' ? 'Metin gönderildi' : 'Link gönderildi');
    check();
  } catch (e) {
    notifyResult(false, e.message);
  }
}

function notifyResult(ok, message) {
  const id = 'r:' + Date.now();
  chrome.notifications.create(id, {
    type: 'basic', iconUrl: 'icons/icon128.png',
    title: ok ? 'RygePush' : 'RygePush · gönderilemedi', message, priority: 0,
  });
  setTimeout(() => chrome.notifications.clear(id), 4000);
}
