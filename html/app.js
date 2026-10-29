const APP = 'zombiezone'; // nom de l'application, en minuscules
const isBrowser = !window.invokeNative;

const root = document.getElementById('zombiezone');
let isOpen = false;

const DEBUG = {
  applicationName: APP,
  title: 'Zone Zombie',
  subtitle: 'Événement Halloween',
  description: "Élimine les zombies pour gagner des tickets Halloween et tente d'obtenir un butin rare.",
  rewardMin: 70,
  rewardMax: 350,
  rareLabel: 'Machin Pistol',
  color: '#ff6a2b'
};

// ---------- Utilitaires NUI ----------
async function nuiPost(cb, body = {}) {
  if (isBrowser) return {};
  try {
    const r = await fetch(`https://${GetParentResourceName()}/${cb}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body)
    });
    try { return await r.json(); } catch { return {}; }
  } catch { return {}; }
}

const emit = (name, isServer, ...args) =>
  nuiPost('eventNEWUI', { event: { name, isServer }, args });

const norm = (p) =>
  String((p && (p.applicationName ?? p.name ?? p.app ?? p.application)) ?? '').toLowerCase().trim();

function hexToRgbTriplet(hex, fallback = '#03a1fc') {
  const ok = (v) => /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(v.trim());
  let h = typeof hex === 'string' ? hex.trim() : '';
  if (h && h[0] !== '#') h = '#' + h;
  if (!ok(h)) h = fallback;
  if (h.length === 4) h = `#${h[1]}${h[1]}${h[2]}${h[2]}${h[3]}${h[3]}`;
  const n = parseInt(h.slice(1), 16);
  return `${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}`;
}

// ---------- Écran ----------
function render(d) {
  root.style.setProperty('--color-rgb', hexToRgbTriplet(d.color));
  const title = String(d.title || 'Zone Zombie');
  const parts = title.split(' ');
  const last = parts.pop();
  const titleEl = document.getElementById('zz-title');
  titleEl.textContent = parts.join(' ') + (parts.length ? ' ' : '');
  const span = document.createElement('span');
  span.textContent = last;
  titleEl.appendChild(span);

  document.getElementById('zz-subtitle').textContent = d.subtitle || 'Événement Halloween';
  document.getElementById('zz-desc').textContent = d.description || '';
  document.getElementById('zz-tickets').textContent =
    d.rewardMin != null && d.rewardMax != null ? `${d.rewardMin}–${d.rewardMax}` : '—';
  document.getElementById('zz-rare').textContent = d.rareLabel || '—';
}

function openApp(payload) {
  const d = (payload && (payload.args ?? payload.data ?? payload.payload)) || payload || {};
  render(d);
  root.classList.remove('hidden');
  isOpen = true;
  emit('ui:onLoadApplication', false, APP);
  emit('ui:new:focus', false, APP);
}

function hide() {
  root.classList.add('hidden');
  isOpen = false;
}

function closeApp() {
  hide();
  emit('ui:onUnloadApplication', false, APP);
  emit('ui:new:unfocus', false, APP);
}

function join() {
  hide();
  emit('ui:onUnloadApplication', false, APP);
  emit('ui:new:unfocus', false, APP);
  emit('adam_zombie:join', false);
}


// ---------- HUD (jamais de focus souris) ----------
const HUD_APP = 'zombiehud';
const hudRoot = document.getElementById('zombiehud');

function showHud(p) {
  hudRoot.style.setProperty('--color-rgb', hexToRgbTriplet(p && p.color));
  hudRoot.classList.remove('hidden');
}

function updateHud(p) {
  document.getElementById('zh-wave').textContent = p.wave ?? 0;
  document.getElementById('zh-label').textContent = p.pause ? 'Prochaine vague' : 'Restants';
  document.getElementById('zh-value').textContent = p.pause ? `${p.nextWaveIn}s` : (p.remaining ?? 0);
}

// ---------- Annonce de vague ----------
const waRoot = document.getElementById('waveannounce');
let waTimer = null;
let waAudio = null;

function showAnnounce(p) {
  document.getElementById('wa-wave').textContent = p.wave ?? 1;
  document.getElementById('wa-sub').textContent = p.subtitle || '';
  document.getElementById('wa-count').textContent = p.count ?? 0;
  waRoot.classList.toggle('wa--boss', !!p.terrifier);
  waRoot.classList.remove('hidden', 'wa--out');
  // relance l'animation d'entrée
  void waRoot.offsetWidth;
  waRoot.classList.add('wa--in');

  if (p.sound) {
    try {
      if (waAudio) { waAudio.pause(); waAudio = null; }
      waAudio = new Audio('sounds/' + String(p.sound).replace(/[^\w.\-]/g, ''));
      waAudio.volume = Math.min(1, Math.max(0, Number(p.volume) || 0.6));
      waAudio.play().catch(() => {});
    } catch (_) {}
  }

  clearTimeout(waTimer);
  const dur = Number(p.duration) || 4500;
  waTimer = setTimeout(() => {
    waRoot.classList.add('wa--out');
    setTimeout(() => waRoot.classList.add('hidden'), 600);
  }, dur);
}

function hideAnnounce() {
  clearTimeout(waTimer);
  waRoot.classList.add('hidden');
  waRoot.classList.remove('wa--in', 'wa--out');
  if (waAudio) { waAudio.pause(); waAudio = null; }
}

// ---------- Messages Lua -> UI ----------
window.addEventListener('message', (e) => {
  const { action, data, params } = e.data || {};
  const payload = data !== undefined ? data : params;
  const name = norm(payload);
  if (action === 'loadNEWApplication' && name === APP) openApp(payload);
  else if (action === 'unloadNEWApplication' && name === APP) hide();
  else if (action === 'loadNEWApplication' && name === HUD_APP) showHud(payload);
  else if (action === 'unloadNEWApplication' && name === HUD_APP) { hudRoot.classList.add('hidden'); hideAnnounce(); }
  else if (action === 'emitNEWSUI' && name === HUD_APP && payload.event === 'update') updateHud(payload);
  else if (action === 'emitNEWSUI' && name === HUD_APP && payload.event === 'announce') showAnnounce(payload);
});

document.getElementById('zz-close').addEventListener('click', closeApp);
document.getElementById('zz-join').addEventListener('click', join);
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && isOpen) closeApp();
});

// Mode navigateur : affiche l'écran avec des données factices
if (isBrowser) {
  openApp(DEBUG);
  showHud({ color: DEBUG.color });
  updateHud({ wave: 3, remaining: 12, pause: false, nextWaveIn: 0 });
  showAnnounce({ wave: 3, count: 14, terrifier: true, subtitle: 'Le Terrifier approche...', duration: 600000 });
}
