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
  document.getElementById('zz-choice').classList.add('hidden');
  switchTab(d.tab === 'crew' ? 'crew' : 'zone');
  if (d.tab === 'crew') waitCrewReply();
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

function doJoin(mode) {
  hide();
  emit('ui:onUnloadApplication', false, APP);
  emit('ui:new:unfocus', false, APP);
  emit('adam_zombie:join', false, mode);
}

// Dans un crew validé : on demande si on entre avec le crew (même monde) ou seul
function join() {
  if (myCrew && myCrew.status === 'approved') {
    document.getElementById('zz-choice-crew').textContent = myCrew.name;
    document.getElementById('zz-choice').classList.remove('hidden');
  } else {
    doJoin('solo');
  }
}


// ---------- Onglets du menu + Crew ----------
const mk = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
};
const fmtMoney = (n) => Number(n || 0).toLocaleString('fr-FR') + ' $';

const tabZoneBtn = document.getElementById('zz-tab-zone-btn');
const tabCrewBtn = document.getElementById('zz-tab-crew-btn');
const tabZone = document.getElementById('zz-tab-zone');
const tabCrew = document.getElementById('zz-tab-crew');
const crewBody = document.getElementById('zz-crew-body');

function switchTab(tab) {
  const crew = tab === 'crew';
  tabZone.classList.toggle('hidden', crew);
  tabCrew.classList.toggle('hidden', !crew);
  tabZoneBtn.classList.toggle('active', !crew);
  tabCrewBtn.classList.toggle('active', crew);
}
tabZoneBtn.addEventListener('click', () => switchTab('zone'));
let myCrew = null;
let crewTimer = null;
function waitCrewReply() {
  clearTimeout(crewTimer);
  crewTimer = setTimeout(() => {
    if (crewBody.textContent.trim() === 'Chargement…') {
      crewBody.textContent = '';
      crewBody.appendChild(mk('div', 'zz__lb-empty', "Pas de réponse du serveur. Regarde la console serveur (erreur du script adam_zombi)."));
    }
  }, 4000);
}
tabCrewBtn.addEventListener('click', () => { switchTab('crew'); emit('adam_zombie:crewRequest', false); waitCrewReply(); });

function crewRow(m, kickable) {
  const row = mk('div', 'zz__crew-row' + (m.owner ? ' owner' : ''));
  const name = mk('span', '', m.name);
  if (m.owner) name.prepend(Object.assign(mk('i', 'fa-solid fa-crown'), {}), ' ');
  const uid = mk('em', '', m.uid ? '#' + m.uid : '');
  row.append(name, uid);
  if (kickable && !m.owner) {
    const b = mk('button', 'zz__mini danger', 'Retirer');
    b.addEventListener('click', () => emit('adam_zombie:crewKick', false, m.uid));
    row.appendChild(b);
  }
  return row;
}

function renderCrew(view) {
  view = view || {};
  clearTimeout(crewTimer);
  myCrew = view.crew || null;
  crewBody.textContent = '';
  if (view.error) {
    crewBody.appendChild(mk('div', 'zz__lb-empty', view.error));
    return;
  }
  const c = view.crew;

  if (c) {
    const head = mk('div', 'zz__crew-head');
    head.append(mk('strong', '', c.name));
    head.append(mk('span', 'zz__badge ' + (c.status === 'approved' ? 'ok' : 'wait'), c.status === 'approved' ? 'Validé' : 'En attente'));
    crewBody.appendChild(head);

    if (c.status !== 'approved') {
      crewBody.appendChild(mk('p', 'zz__desc', 'Ta demande a été envoyée. Un fondateur doit la valider avant que tu puisses inviter des joueurs.'));
    }
    crewBody.appendChild(mk('div', 'zz__crew-sub', `Owner : ${c.ownerName}${c.ownerUid ? ' #' + c.ownerUid : ''}  ·  ${c.members.length}/${view.maxMembers || '?'} membres`));

    const list = mk('div', 'zz__crew-list');
    c.members.forEach((m) => list.appendChild(crewRow(m, c.isOwner && c.status === 'approved')));
    crewBody.appendChild(list);

    if (c.isOwner && c.status === 'approved') {
      const form = mk('div', 'zz__crew-form');
      const input = mk('input'); input.type = 'text'; input.placeholder = 'ID unique du joueur'; input.maxLength = 12; input.inputMode = 'numeric';
      const btn = mk('button', 'btn btn--go', 'Inviter');
      btn.prepend(mk('i', 'fa-solid fa-user-plus'));
      const send = () => { const v = input.value.trim(); if (v) { emit('adam_zombie:crewInvite', false, v); input.value = ''; } };
      btn.addEventListener('click', send);
      input.addEventListener('keydown', (e) => { if (e.key === 'Enter') send(); });
      form.append(input, btn);
      crewBody.appendChild(form);
    } else if (!c.isOwner) {
      const btn = mk('button', 'btn', 'Quitter le crew');
      btn.prepend(mk('i', 'fa-solid fa-right-from-bracket'));
      btn.addEventListener('click', () => emit('adam_zombie:crewLeave', false));
      crewBody.appendChild(btn);
    }
    return;
  }

  // Pas de crew : création + invitations reçues
  const box = mk('div', 'zz__crew-create');
  box.append(mk('strong', '', 'Créer un crew'));
  box.append(mk('p', 'zz__desc', `La création coûte ${fmtMoney(view.price)}. Un fondateur doit ensuite valider ta demande.`));
  const form = mk('div', 'zz__crew-form');
  const input = mk('input'); input.type = 'text'; input.placeholder = 'Nom du crew'; input.maxLength = 20;
  const btn = mk('button', 'btn btn--go', `Créer (${fmtMoney(view.price)})`);
  btn.prepend(mk('i', 'fa-solid fa-flag'));
  const send = () => { const v = input.value.trim(); if (v) emit('adam_zombie:crewCreate', false, v); };
  btn.addEventListener('click', send);
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') send(); });
  form.append(input, btn);
  box.appendChild(form);
  crewBody.appendChild(box);

  if (Array.isArray(view.invites) && view.invites.length) {
    crewBody.appendChild(mk('div', 'zz__crew-sub', 'Invitations reçues'));
    view.invites.forEach((inv) => {
      const row = mk('div', 'zz__crew-row');
      row.append(mk('span', '', `${inv.name} — de ${inv.fromName}`));
      const ok = mk('button', 'zz__mini ok', 'Accepter');
      ok.addEventListener('click', () => emit('adam_zombie:crewRespond', false, inv.crewId, true));
      const no = mk('button', 'zz__mini danger', 'Refuser');
      no.addEventListener('click', () => emit('adam_zombie:crewRespond', false, inv.crewId, false));
      row.append(ok, no);
      crewBody.appendChild(row);
    });
  }
}

// ---------- Classement dans le menu ----------
const lbTabs = document.getElementById('zz-lb-tabs');
const lbList = document.getElementById('zz-lb-list');
const lbChamp = document.getElementById('zz-lb-champ');
let lbBoards = [];
let lbActive = 0;

// Podium (top 3) inséré juste avant la liste
const lbPodium = document.createElement('div');
lbPodium.className = 'zz__podium';
lbPodium.style.display = 'none';
lbList.parentNode.insertBefore(lbPodium, lbList);

function buildPodiumSlot(r, rank) {
  const slot = document.createElement('div');
  slot.className = 'zz__pod p' + rank + (r ? '' : ' empty');

  const crown = document.createElement('i');
  crown.className = 'fa-solid fa-crown zz__pod-crown';

  const avatar = document.createElement('div');
  avatar.className = 'zz__pod-avatar';
  const initial = r ? (String(r.name || '?').trim().charAt(0).toUpperCase() || '?') : '?';
  avatar.textContent = initial;
  if (r && r.avatar) {
    // photo de profil Discord ; si elle ne charge pas, on garde la première lettre
    const img = document.createElement('img');
    img.className = 'zz__pod-img';
    img.alt = '';
    img.onload = () => { avatar.textContent = ''; avatar.appendChild(img); };
    img.onerror = () => { avatar.textContent = initial; };
    img.src = r.avatar;
  }

  const name = document.createElement('div');
  name.className = 'zz__pod-name';
  name.textContent = r ? r.name : '—';

  const uid = document.createElement('div');
  uid.className = 'zz__pod-uid';
  uid.textContent = (r && r.uid) ? '#' + r.uid : '';

  const val = document.createElement('div');
  val.className = 'zz__pod-val';
  val.textContent = r ? r.value : '';

  const block = document.createElement('div');
  block.className = 'zz__pod-block';
  const num = document.createElement('span');
  num.textContent = rank;
  block.appendChild(num);

  slot.append(crown, avatar, name, uid, val, block);
  return slot;
}

function renderLbList() {
  lbList.textContent = '';
  lbPodium.textContent = '';
  const b = lbBoards[lbActive];
  const rows = b && Array.isArray(b.rows) ? b.rows.slice(0, 10) : [];
  if (!rows.length) {
    lbPodium.style.display = 'none';
    const e = document.createElement('div');
    e.className = 'zz__lb-empty';
    e.textContent = 'Aucun joueur classé';
    lbList.appendChild(e);
    return;
  }

  // Podium : 2e | 1er | 3e
  lbPodium.style.display = '';
  [1, 0, 2].forEach(i => lbPodium.appendChild(buildPodiumSlot(rows[i], i + 1)));

  // Reste du classement (4 à 10)
  rows.slice(3).forEach((r, k) => {
    const row = document.createElement('div');
    row.className = 'zz__lb-row';
    const rank = document.createElement('b'); rank.textContent = '#' + (k + 4);
    const name = document.createElement('span'); name.textContent = r.name + (r.uid ? '  #' + r.uid : '');
    const val = document.createElement('em'); val.textContent = r.value;
    row.append(rank, name, val);
    lbList.appendChild(row);
  });
}

function renderLeaderboard(p) {
  lbBoards = Array.isArray(p.boards) ? p.boards : Object.values(p.boards || {});
  if (lbActive >= lbBoards.length) lbActive = 0;
  lbTabs.textContent = '';
  lbBoards.forEach((b, i) => {
    const t = document.createElement('div');
    t.className = 'zz__lb-tab' + (i === lbActive ? ' active' : '');
    t.textContent = b.title;
    t.addEventListener('click', () => { lbActive = i; renderLeaderboard({ boards: lbBoards, champion: p.champion }); });
    lbTabs.appendChild(t);
  });
  renderLbList();
  lbChamp.textContent = '';
  if (p.champion && p.champion.name) {
    lbChamp.append('Meilleur chasseur : ');
    const s = document.createElement('strong');
    s.textContent = p.champion.name + (p.champion.uid ? ' #' + p.champion.uid : '');
    lbChamp.append(s, ` — ${p.champion.total} ${p.champion.label || ''}`);
  }
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

// ---------- Config en jeu (/configzombie) ----------
const CFG_APP = 'zombieconfig';
const cfgRoot = document.getElementById('zombieconfig');
const cfgList = document.getElementById('zc-list');
let cfgOpen = false;
let cfgFields = [];

function renderConfig(d) {
  cfgRoot.style.setProperty('--color-rgb', hexToRgbTriplet(d.color));
  cfgFields = Array.isArray(d.fields) ? d.fields : Object.values(d.fields || {});
  const values = d.values || {};
  cfgList.textContent = '';
  let lastGroup = null;
  for (const f of cfgFields) {
    if (f.group !== lastGroup) {
      lastGroup = f.group;
      const h = document.createElement('div');
      h.className = 'zc__group';
      h.textContent = f.group;
      cfgList.appendChild(h);
    }
    const row = document.createElement('label');
    row.className = 'zc__row';
    const span = document.createElement('span');
    span.textContent = f.label;
    const input = document.createElement('input');
    input.dataset.path = f.path;
    input.dataset.type = f.type;
    const v = values[f.path];
    if (f.type === 'boolean') {
      input.type = 'checkbox';
      input.checked = !!v;
    } else if (f.type === 'number') {
      input.type = 'number';
      if (f.min != null) input.min = f.min;
      if (f.max != null) input.max = f.max;
      input.step = f.step != null ? f.step : 1;
      input.value = v ?? '';
    } else {
      input.type = 'text';
      input.maxLength = 64;
      input.value = v ?? '';
    }
    row.append(span, input);
    cfgList.appendChild(row);
  }
}

function openConfig(payload) {
  const d = (payload && (payload.args ?? payload.data ?? payload.payload)) || payload || {};
  renderConfig(d);
  if (!cfgOpen && typeof cfgTab === 'function') cfgTab('settings');
  cfgRoot.classList.remove('hidden');
  cfgOpen = true;
}

function hideConfig() {
  cfgRoot.classList.add('hidden');
  cfgOpen = false;
}

function closeConfig() {
  hideConfig();
  emit('ui:config:close', false);
}

function collectConfig() {
  const out = {};
  cfgList.querySelectorAll('input').forEach((i) => {
    const t = i.dataset.type;
    if (t === 'boolean') out[i.dataset.path] = i.checked;
    else if (t === 'number') { if (i.value !== '') out[i.dataset.path] = Number(i.value); }
    else out[i.dataset.path] = i.value;
  });
  return out;
}

// ----- Concours : chrono + gagnant -----
const contest = { enabled: false, ended: false, deadline: 0 };

function fmtContest() {
  if (contest.ended) return 'Terminé';
  const s = Math.max(0, Math.floor((contest.deadline - Date.now()) / 1000));
  if (s === 0) return 'Terminé';
  const d = Math.floor(s / 86400);
  const hh = String(Math.floor((s % 86400) / 3600)).padStart(2, '0');
  const mm = String(Math.floor((s % 3600) / 60)).padStart(2, '0');
  const ss = String(s % 60).padStart(2, '0');
  return (d > 0 ? `${d}j ` : '') + `${hh}:${mm}:${ss}`;
}

function tickContest() {
  const ids = ['zh-contest', 'zh-contest-sep', 'zz-contest', 'zc-contest'];
  ids.forEach((id) => { const e = document.getElementById(id); if (e) e.classList.toggle('hidden', !contest.enabled); });
  if (!contest.enabled) return;
  const txt = fmtContest();
  ['zh-timer', 'zz-timer', 'zc-timer'].forEach((id) => { const e = document.getElementById(id); if (e) e.textContent = txt; });
}
setInterval(tickContest, 1000);

function renderWinner(w, isFinal) {
  const el = document.getElementById('zc-winner');
  if (!el) return;
  el.textContent = '';
  if (!w) return;
  if (w.none) {
    el.appendChild(mk('div', 'zc__winner-tag', isFinal ? 'Gagnant' : 'Classement'));
    el.appendChild(mk('div', 'zc__winner-line', 'Aucun zombie tué pour le moment.'));
    return;
  }
  el.appendChild(mk('div', 'zc__winner-tag', isFinal ? 'Gagnant du concours' : 'Actuellement en tête'));
  el.appendChild(mk('div', 'zc__winner-name', w.name || 'Inconnu'));
  const line = (label, value) => {
    const d = mk('div', 'zc__winner-line');
    d.append(`${label} : `);
    d.appendChild(mk('b', '', String(value)));
    el.appendChild(d);
  };
  line('ID unique', w.uid || '—');
  line('Zombies tués', w.kills ?? 0);
  line('Identifiant', w.identifier || '—');
  const tie = Array.isArray(w.tie) ? w.tie : Object.values(w.tie || {});
  if (tie.length) el.appendChild(mk('div', 'zc__winner-tie', `Égalité avec : ${tie.join(', ')}`));
}

function handleContest(name, p) {
  contest.enabled = p.enabled === true;
  contest.ended = p.ended === true;
  contest.deadline = Date.now() + (Number(p.secondsLeft) || 0) * 1000;
  tickContest();
  if (name === CFG_APP) renderWinner(contest.enabled ? p.winner : null, p.final === true);
}

// ----- Joueurs en zone + parties en cours (admin) -----
function renderOnline(p) {
  const el = document.getElementById('zc-online-text');
  const gamesEl = document.getElementById('zc-games');
  if (!el) return;
  const n = Number(p.count) || 0;
  const games = Array.isArray(p.games) ? p.games : Object.values(p.games || {});
  el.textContent = '';
  el.append('En zone zombie : ');
  const b = document.createElement('b');
  b.textContent = String(n);
  el.append(b, n > 1 ? ' joueurs' : ' joueur', games.length > 0 ? ` · ${games.length} partie${games.length > 1 ? 's' : ''} en cours` : '');
  if (!gamesEl) return;
  gamesEl.textContent = '';
  for (const g of games) {
    const row = mk('div', 'zc__game');
    const info = mk('div', 'zc__game-info');
    info.appendChild(mk('div', 'zc__game-title', g.label || 'Partie'));
    const players = Array.isArray(g.players) ? g.players : Object.values(g.players || {});
    info.appendChild(mk('div', 'zc__game-sub', `Vague ${Number(g.wave) || 0} · ${players.join(', ')}`));
    row.appendChild(info);
    if (g.joined) {
      row.appendChild(mk('span', 'zc__chip', 'Tu y es'));
    } else {
      const btn = mk('button', 'btn btn--go');
      btn.appendChild(mk('i', 'fa-solid fa-right-to-bracket'));
      btn.append('Rejoindre');
      btn.addEventListener('click', () => emit('adam_zombie:adminJoin', false, g.bucket));
      row.appendChild(btn);
    }
    gamesEl.appendChild(row);
  }
}

// ----- Onglet Crews (admin) -----
const cfgCrewsEl = document.getElementById('zc-crews');
const cfgTabSettings = document.getElementById('zc-tab-settings-btn');
const cfgTabCrews = document.getElementById('zc-tab-crews-btn');
const cfgBadge = document.getElementById('zc-crew-badge');
const cfgSave = document.getElementById('zc-save');
const cfgReset = document.getElementById('zc-reset');

function cfgTab(tab) {
  const crews = tab === 'crews';
  cfgList.classList.toggle('hidden', crews);
  cfgCrewsEl.classList.toggle('hidden', !crews);
  cfgTabSettings.classList.toggle('active', !crews);
  cfgTabCrews.classList.toggle('active', crews);
  cfgSave.classList.toggle('hidden', crews);
  cfgReset.classList.toggle('hidden', crews);
}
cfgTabSettings.addEventListener('click', () => cfgTab('settings'));
cfgTabCrews.addEventListener('click', () => { cfgTab('crews'); emit('adam_zombie:crewAdminList', false); });

function renderAdminCrews(list) {
  list = Array.isArray(list) ? list : Object.values(list || {});
  cfgCrewsEl.textContent = '';
  const pending = list.filter((c) => c.status === 'pending').length;
  cfgBadge.textContent = pending;
  cfgBadge.classList.toggle('hidden', pending === 0);

  if (!list.length) {
    cfgCrewsEl.appendChild(mk('div', 'zz__lb-empty', 'Aucun crew pour le moment'));
    return;
  }

  list.forEach((c) => {
    const card = mk('div', 'zc__crew');
    const head = mk('div', 'zz__crew-head');
    head.append(mk('strong', '', c.name));
    head.append(mk('span', 'zz__badge ' + (c.status === 'approved' ? 'ok' : 'wait'), c.status === 'approved' ? 'Validé' : 'En attente'));
    card.appendChild(head);
    card.appendChild(mk('div', 'zz__crew-sub', `Owner : ${c.ownerName}${c.ownerUid ? ' #' + c.ownerUid : ''}  ·  ${c.members.length} membre(s)`));

    const chips = mk('div', 'zc__chips');
    c.members.forEach((m) => chips.appendChild(mk('span', 'zc__chip' + (m.owner ? ' owner' : ''), `${m.name}${m.uid ? ' #' + m.uid : ''}`)));
    card.appendChild(chips);

    const field = (placeholder, label, action, maxLen, numeric) => {
      const row = mk('div', 'zz__crew-form');
      const input = mk('input'); input.type = 'text'; input.placeholder = placeholder; input.maxLength = maxLen;
      if (numeric) input.inputMode = 'numeric';
      const b = mk('button', 'zz__mini', label);
      b.addEventListener('click', () => { const v = input.value.trim(); if (v) { emit('adam_zombie:crewAdmin', false, action, c.id, v); input.value = ''; } });
      row.append(input, b);
      return row;
    };
    card.appendChild(field('Nouveau nom', 'Renommer', 'rename', 20, false));
    card.appendChild(field('ID unique du nouvel owner', 'Définir owner', 'owner', 12, true));

    const actions = mk('div', 'zz__crew-form');
    if (c.status === 'pending') {
      const ok = mk('button', 'btn btn--go', 'Confirmer');
      ok.prepend(mk('i', 'fa-solid fa-check'));
      ok.addEventListener('click', () => emit('adam_zombie:crewAdmin', false, 'approve', c.id));
      actions.appendChild(ok);
    }
    const del = mk('button', 'btn', 'Supprimer');
    del.prepend(mk('i', 'fa-solid fa-trash'));
    let armed = false;
    del.addEventListener('click', () => {
      if (!armed) { armed = true; del.textContent = 'Cliquer pour confirmer'; setTimeout(() => { armed = false; del.textContent = 'Supprimer'; del.prepend(mk('i', 'fa-solid fa-trash')); }, 3000); return; }
      emit('adam_zombie:crewAdmin', false, 'delete', c.id);
    });
    actions.appendChild(del);
    card.appendChild(actions);
    cfgCrewsEl.appendChild(card);
  });
}

document.getElementById('zc-close').addEventListener('click', closeConfig);
document.getElementById('zc-save').addEventListener('click', () => emit('adam_zombie:saveConfig', false, collectConfig()));
document.getElementById('zc-reset').addEventListener('click', () => emit('adam_zombie:resetConfig', false));

// ---------- Confirmation pour quitter (touche K) ----------
const LEAVE_APP = 'zombieleave';
const leaveRoot = document.getElementById('zombieleave');
let leaveOpenUi = false;

function openLeave(payload) {
  const d = (payload && (payload.args ?? payload.data ?? payload.payload)) || payload || {};
  leaveRoot.style.setProperty('--color-rgb', hexToRgbTriplet(d.color));
  leaveRoot.classList.remove('hidden');
  leaveOpenUi = true;
}
function hideLeave() {
  leaveRoot.classList.add('hidden');
  leaveOpenUi = false;
}
function leaveConfirm() { hideLeave(); emit('adam_zombie:leaveConfirm', false); }
function leaveCancel() { hideLeave(); emit('adam_zombie:leaveCancel', false); }
document.getElementById('zl-confirm').addEventListener('click', leaveConfirm);
document.getElementById('zl-cancel').addEventListener('click', leaveCancel);

// ---------- Messages Lua -> UI ----------
window.addEventListener('message', (e) => {
  const { action, data, params } = e.data || {};
  const payload = data !== undefined ? data : params;
  const name = norm(payload);
  if (action === 'loadNEWApplication' && name === LEAVE_APP) openLeave(payload);
  else if (action === 'unloadNEWApplication' && name === LEAVE_APP) hideLeave();
  else if (action === 'emitNEWSUI' && name === APP && payload.event === 'crew') renderCrew(payload.view);
  else if (action === 'emitNEWSUI' && name === CFG_APP && payload.event === 'crews') renderAdminCrews(payload.crews);
  else if (action === 'emitNEWSUI' && name === CFG_APP && payload.event === 'online') renderOnline(payload);
  else if (action === 'emitNEWSUI' && payload.event === 'contest') handleContest(name, payload);
  else if (action === 'loadNEWApplication' && name === CFG_APP) openConfig(payload);
  else if (action === 'unloadNEWApplication' && name === CFG_APP) hideConfig();
  else if (action === 'loadNEWApplication' && name === APP) openApp(payload);
  else if (action === 'unloadNEWApplication' && name === APP) hide();
  else if (action === 'loadNEWApplication' && name === HUD_APP) showHud(payload);
  else if (action === 'unloadNEWApplication' && name === HUD_APP) { hudRoot.classList.add('hidden'); hideAnnounce(); }
  else if (action === 'emitNEWSUI' && name === APP && payload.event === 'leaderboard') renderLeaderboard(payload);
  else if (action === 'emitNEWSUI' && name === HUD_APP && payload.event === 'update') updateHud(payload);
  else if (action === 'emitNEWSUI' && name === HUD_APP && payload.event === 'announce') showAnnounce(payload);
});

document.getElementById('zz-close').addEventListener('click', closeApp);
document.getElementById('zz-join').addEventListener('click', join);
document.getElementById('zz-join-crew').addEventListener('click', () => doJoin('crew'));
document.getElementById('zz-join-solo').addEventListener('click', () => doJoin('solo'));
document.getElementById('zz-choice-cancel').addEventListener('click', () => document.getElementById('zz-choice').classList.add('hidden'));
document.addEventListener('keydown', (e) => {
  if (leaveOpenUi) {
    if (e.key === 'Escape' || e.key === 'k' || e.key === 'K') leaveCancel();
    else if (e.key === 'Enter') leaveConfirm();
    return;
  }
  if (e.key === 'Escape' && cfgOpen) closeConfig();
  else if (e.key === 'Escape' && isOpen) closeApp();
});

// Mode navigateur : affiche l'écran avec des données factices
if (isBrowser) {
  openApp(DEBUG);
  renderLeaderboard({ champion: { name: 'Merciless', total: 128, label: 'zombies tués' }, boards: [
    { title: 'Zombies tués', rows: [{ name: 'Merciless', value: 128 }, { name: 'Leban', value: 96 }, { name: 'Nitro', value: 40 }] },
    { title: 'Terrifier tués', rows: [{ name: 'Leban', value: 5 }] },
    { title: 'Meilleure vague', rows: [] }, { title: 'Tickets gagnés', rows: [] } ] });
  showHud({ color: DEBUG.color });
  updateHud({ wave: 3, remaining: 12, pause: false, nextWaveIn: 0 });
  showAnnounce({ wave: 3, count: 14, terrifier: true, subtitle: 'Le Terrifier approche...', duration: 600000 });
}
