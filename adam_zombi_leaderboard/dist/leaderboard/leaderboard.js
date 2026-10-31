console.log("loaded");

// ---------------- Réglages ----------------
const MAX_ROWS = 10; // lignes max par classement (10 tient dans 1080p avec la barre sociale)

// true dans le jeu (DUI/NUI), false dans un navigateur
const IS_GAME = typeof window.invokeNative !== "undefined";

const boardsEl = document.getElementById("boards");
const boards = new Map(); // id -> { card, content, titleEl, statEl, prev: Map(nom -> valeur), rendered }

// "#rrggbb" / "#rgb" -> "r, g, b" (pour --color-rgb)
function hexToRgbTriplet(hex, fallback = "#03a1fc") {
    const ok = (v) => /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(String(v).trim());
    let h = ok(hex) ? String(hex).trim() : fallback;
    if (h.length === 4) h = `#${h[1]}${h[1]}${h[2]}${h[2]}${h[3]}${h[3]}`;
    const n = parseInt(h.slice(1), 16);
    return `${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}`;
}

function el(tag, className, text) {
    const e = document.createElement(tag);
    if (className) e.className = className;
    if (text !== undefined) e.textContent = text;
    return e;
}

function buildAvatar(player) {
    const initial = String(player.name || "?").trim().charAt(0) || "?";
    const fallback = el("div", "avatar-fallback", initial);

    if (!player.avatar) return fallback;

    const img = el("img", "discord-pfp");
    img.src = player.avatar;
    img.alt = "Discord PFP";
    img.onerror = () => img.replaceWith(fallback); // image injoignable -> initiale
    return img;
}

// Crée la carte d'un classement (une seule fois par id)
function getBoard(def) {
    let b = boards.get(def.id);
    if (b) return b;

    const card = el("div", "leaderboard");
    const titleEl = el("div", "leaderboard-header", def.title || def.id);

    const table = el("div", "leaderboard-table");
    const statEl = el("div", "column-header", def.stat || "Kills");
    table.append(el("div", "column-header"), el("div", "column-header", "Rang"), el("div", "column-header", "Nom"), statEl);

    const content = el("div", "column-content");
    table.appendChild(content);

    card.append(titleEl, table);
    boardsEl.appendChild(card);

    b = { card, content, titleEl, statEl, prev: new Map(), rendered: false };
    boards.set(def.id, b);
    return b;
}

function renderBoard(def) {
    const b = getBoard(def);
    b.titleEl.textContent = def.title || def.id;
    b.statEl.textContent = def.stat || "Kills";

    const rows = (Array.isArray(def.rows) ? def.rows : [])
        .map((r) => ({ ...r, value: Number(r.value) || 0 }))
        .sort((x, y) => y.value - x.value)
        .slice(0, MAX_ROWS);

    b.content.innerHTML = "";

    if (rows.length === 0) {
        b.content.appendChild(el("div", "empty-row", "Aucun joueur classé"));
        b.prev = new Map();
        b.rendered = true;
        b.content.classList.add("static");
        return;
    }

    const classMap = { 1: "top-1", 2: "top-2", 3: "top-3" };
    const next = new Map();

    rows.forEach((player, index) => {
        const rank = index + 1;
        next.set(player.name, player.value);

        const row = el("div", "player-row");
        row.style.setProperty("--i", index); // délai d'animation en cascade
        if (classMap[rank]) row.classList.add(classMap[rank]);

        // Mise à jour live : on fait clignoter les lignes nouvelles ou qui ont progressé
        if (b.rendered && (!b.prev.has(player.name) || b.prev.get(player.name) < player.value)) {
            row.classList.add("flash");
        }

        const pfpCell = el("div", "cell pfp-col");
        pfpCell.appendChild(buildAvatar(player));

        const rankCell = el("div", "cell rank-col");
        rankCell.appendChild(el("span", "rank-badge", rank));

        const nameCell = el("div", "cell name-col", player.name);
        if (player.uid) nameCell.appendChild(el("span", "uid", " #" + player.uid));
        const statCell = el("div", "cell stat-col", player.value);

        row.append(pfpCell, rankCell, nameCell, statCell);
        b.content.appendChild(row);
    });

    b.prev = next;
    b.rendered = true;
    b.content.classList.add("static"); // les animations d'entrée ne jouent qu'au premier affichage
}

function updateBoards(list) {
    if (!Array.isArray(list)) return;

    // supprime les cartes qui ne sont plus dans la config serveur
    const ids = new Set(list.map((d) => d.id));
    for (const [id, b] of boards) {
        if (!ids.has(id)) { b.card.remove(); boards.delete(id); }
    }

    list.forEach(renderBoard);

    // la grille s'adapte au nombre de classements
    boardsEl.style.gridTemplateColumns = `repeat(${Math.max(list.length, 1)}, minmax(0, 1fr))`;
    boardsEl.classList.toggle("dense", list.length >= 5);
}

// ---------------- Bannière du top 1 global ----------------
const champEl = document.getElementById("champion");
const champName = document.getElementById("champ-name");
const champLabel = document.getElementById("champ-label");
const champTotal = document.getElementById("champ-total");
const champChips = document.getElementById("champ-chips");
let champPrev = null; // { name, total } affichés actuellement

function updateChampion(c) {
    if (!c || !c.name) {
        champEl.classList.add("empty");
        champLabel.textContent = "Meilleur chasseur";
        champName.textContent = "Aucun champion";
        champTotal.textContent = "En attente du premier zombie tué";
        champChips.innerHTML = "";
        champPrev = null;
        return;
    }

    champEl.classList.remove("empty");
    champLabel.textContent = "Meilleur chasseur";
    champName.textContent = c.name + (c.uid ? " #" + c.uid : "");
    champTotal.textContent = `${Number(c.total) || 0} ${c.label || "points"}`;

    champChips.innerHTML = "";
    (Array.isArray(c.modes) ? c.modes : []).forEach((m) => {
        const kills = Number(m.kills) || 0;
        const chip = el("div", kills > 0 ? "chip" : "chip zero");
        chip.append(el("div", "chip-title", m.title || m.id), el("div", "chip-value", kills));
        champChips.appendChild(chip);
    });

    // nouveau champion ou score qui bouge : petit effet
    const total = Number(c.total) || 0;
    if (champPrev && (champPrev.name !== c.name || champPrev.total !== total)) {
        champEl.classList.remove("pop");
        void champEl.offsetWidth; // relance l'animation
        champEl.classList.add("pop");
        setTimeout(() => champEl.classList.remove("pop"), 1000); // rend la main à l'animation de la couronne
    }
    champPrev = { name: c.name, total };
}

window.addEventListener("message", (event) => {
    const data = event.data;
    if (!data || data.type !== "updateLeaderboard") return;

    // couleur d'accent optionnelle envoyée par le Lua
    if (data.color) {
        document.documentElement.style.setProperty("--color-rgb", hexToRgbTriplet(data.color));
    }
    updateBoards(data.boards);
    updateChampion(data.champion);
});

// ---------------- Mode navigateur (test sans le jeu) ----------------
if (!IS_GAME) {
    const names = ["Merciless", "Leban", "Nitro", "Phoenix", "Thunder", "Specter", "DaisyTap", "Abhm", "Azerty", "Ghost", "Yacks", "Almighty", "Latortur", "Viper"];
    const defs = [
        ["zombies", "Zombies tués", "Zombies"], ["terrifier", "Terrifier tués", "Kills"],
        ["wave", "Meilleure vague", "Vague"], ["tickets", "Tickets gagnés", "Tickets"],
    ];
    const demo = defs.map(([id, title, stat]) => ({
        id, title, stat,
        rows: names.slice(0, 8).sort(() => Math.random() - 0.5).map((name) => ({ name, value: 5 + Math.floor(Math.random() * 120) })),
    }));

    const demoChampion = () => {
        const totals = new Map();
        demo.forEach((d) => d.rows.forEach((r) => totals.set(r.name, (totals.get(r.name) || 0) + r.value)));
        const [name, total] = [...totals.entries()].sort((a, b) => b[1] - a[1])[0];
        const modes = demo.map((d) => ({ id: d.id, title: d.title, kills: (d.rows.find((r) => r.name === name) || {}).value || 0 }));
        return { name, total, label: "zombies tués", modes };
    };

    updateBoards(demo);
    updateChampion(demoChampion());

    // simule des kills en direct pour voir l'animation de mise à jour
    setInterval(() => {
        const d = demo[Math.floor(Math.random() * demo.length)];
        d.rows[Math.floor(Math.random() * d.rows.length)].value += 1 + Math.floor(Math.random() * 3);
        updateBoards(demo);
        updateChampion(demoChampion());
    }, 3000);
}
