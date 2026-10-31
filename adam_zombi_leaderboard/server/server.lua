-- ============================================================
-- adam_zombi_leaderboard : classements de la zone zombie
-- Stockage oxmysql, identité = joueur ESX (repli : licence Rockstar).
-- ============================================================

local TABLE = 'adam_zombie_leaderboard'

local boardDefs = {}
for _, b in ipairs(Config.boards) do boardDefs[b.id] = b end

local externalRows = {} -- classements fournis par un autre script (ex : crews)
local cache = {}
local champion = nil
local ready = false
local dirty = false

-- ---------- Base de données ----------
local function buildChampion()
    local top = MySQL.query.await(
        ('SELECT `license`, `name`, `uid`, `value` FROM `%s` WHERE `stat` = ? AND `value` > 0 ORDER BY `value` DESC LIMIT 1'):format(TABLE),
        { Config.championBoard }
    )
    if not top or not top[1] then return nil end

    local rows = MySQL.query.await(
        ('SELECT `stat`, `value` FROM `%s` WHERE `license` = ?'):format(TABLE),
        { top[1].license }
    ) or {}
    local byStat = {}
    for _, r in ipairs(rows) do byStat[r.stat] = r.value end

    local modes = {}
    for _, b in ipairs(Config.boards) do
        if not b.external then
            modes[#modes + 1] = { id = b.id, title = b.title, kills = byStat[b.id] or 0 }
        end
    end

    return {
        name = top[1].name ~= '' and top[1].name or 'Inconnu',
        uid = top[1].uid or '',
        total = tonumber(top[1].value) or 0,
        label = Config.championLabel or 'points',
        modes = modes
    }
end

local function rebuild()
    local boards = {}
    for _, b in ipairs(Config.boards) do
        local list = {}
        if b.external then
            for i, r in ipairs(externalRows[b.id] or {}) do list[i] = r end
        else
            local rows = MySQL.query.await(
                ('SELECT `name`, `uid`, `value` FROM `%s` WHERE `stat` = ? AND `value` > 0 ORDER BY `value` DESC LIMIT ?'):format(TABLE),
                { b.id, Config.topCount }
            ) or {}
            for i, r in ipairs(rows) do list[i] = { name = r.name, uid = r.uid or '', value = r.value } end
        end
        boards[#boards + 1] = { id = b.id, title = b.title, stat = b.stat, rows = list }
    end
    cache = boards
    champion = buildChampion()
end

local function emptyCache()
    local boards = {}
    for _, b in ipairs(Config.boards) do
        boards[#boards + 1] = { id = b.id, title = b.title, stat = b.stat, rows = {} }
    end
    cache = boards
    champion = nil
end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await(([[
            CREATE TABLE IF NOT EXISTS `%s` (
                `license` VARCHAR(80) NOT NULL,
                `stat`    VARCHAR(32) NOT NULL,
                `name`    VARCHAR(64) NOT NULL DEFAULT '',
                `uid`     VARCHAR(32) NOT NULL DEFAULT '',
                `value`   INT NOT NULL DEFAULT 0,
                PRIMARY KEY (`license`, `stat`),
                KEY `idx_stat_value` (`stat`, `value`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]]):format(TABLE))
        -- Migration : ajoute la colonne de l'ID unique si la table existe déjà sans elle
        local col = MySQL.query.await(('SHOW COLUMNS FROM `%s` LIKE \'uid\''):format(TABLE))
        if not col or not col[1] then
            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `uid` VARCHAR(32) NOT NULL DEFAULT \'\' AFTER `name`'):format(TABLE))
        end
        rebuild()
    end)

    if ok then
        print(('^2[Zombie Leaderboard]^0 Prêt : %d classements chargés'):format(#cache))
    else
        print('^1[Zombie Leaderboard]^0 Erreur base de données : ' .. tostring(err))
        emptyCache()
    end

    ready = true
    TriggerClientEvent('adam_zombi_lb:update', -1, cache, champion)

    while true do
        Wait(Config.refreshDelay * 1000)
        if dirty then
            dirty = false
            local ok2, err2 = pcall(rebuild)
            if not ok2 then print('^1[Zombie Leaderboard]^0 Erreur de mise à jour : ' .. tostring(err2)) end
            TriggerClientEvent('adam_zombi_lb:update', -1, cache, champion)
        end
    end
end)

-- ---------- Identité du joueur ----------
local ESX = nil
local esxWarned = false

local function getESX()
    if ESX then return ESX end
    if not (Config.esx and Config.esx.enabled) then return nil end
    local tries = { { Config.esx.resource, Config.esx.export }, { 'SpinFramework', 'getSharedObject' }, { 'es_extended', 'getSharedObject' } }
    for _, t in ipairs(tries) do
        local ok, obj = pcall(function()
            local res = exports[t[1]]
            return res[t[2]](res)
        end)
        if ok and type(obj) == 'table' and obj.GetPlayerFromId then
            ESX = obj
            return ESX
        end
    end
    if not esxWarned then
        esxWarned = true
        print('^3[Zombie Leaderboard]^0 Objet ESX/Spin introuvable -> repli sur licence + nom FiveM. Ajuste Config.esx.')
    end
    return nil
end

local function getIdentity(src)
    local identifier = GetPlayerIdentifierByType(src, 'license')
    local name = GetPlayerName(src)
    local uid = ''

    -- API Spin (https://spinhub-1.gitbook.io) : identifiant, nom RP et ID unique
    local spin = rawget(_G, 'Spin')
    if type(spin) == 'table' and type(spin.Player) == 'table' then
        pcall(function()
            local i = spin.Player.GetIdentifier(src)
            if type(i) == 'string' and i ~= '' then identifier = i end
        end)
        pcall(function()
            local n = spin.Player.GetName(src)
            if type(n) == 'string' and n ~= '' then name = n end
        end)
        pcall(function()
            local u = spin.Player.GetUniqueId(src)
            if u ~= nil then uid = tostring(u) end
        end)
    end

    local esx = getESX()
    if esx then
        local xPlayer = esx.GetPlayerFromId(src)
        if xPlayer then
            identifier = xPlayer.identifier or identifier
            if xPlayer.getName then
                local ok, n = pcall(xPlayer.getName)
                if ok and type(n) == 'string' and n ~= '' then name = n end
            end
            if uid == '' and xPlayer.idunique ~= nil then uid = tostring(xPlayer.idunique) end
        end
    end
    return identifier, name, uid
end

-- ---------- API (SERVEUR) ----------
-- exports['adam_zombi_leaderboard']:AddStat(src, 'zombies', 1)   -- cumul
-- exports['adam_zombi_leaderboard']:AddStat(src, 'wave', 7)      -- meilleur score (agg = 'max')
local uidLogged = {}
AddEventHandler('playerDropped', function() uidLogged[source] = nil end)

local function AddStat(src, stat, amount)
    src = tonumber(src)
    amount = math.floor(tonumber(amount) or 1)
    local def = boardDefs[stat]
    if not src or amount < 1 or not def or def.external then return false end

    local license, name, uid = getIdentity(src)
    if not uidLogged[src] then
        uidLogged[src] = true
        local spin = rawget(_G, 'Spin')
        print(('^3[Zombie Leaderboard]^0 Joueur %s : ID unique = "%s" | API Spin = %s | nom = %s'):format(
            src, tostring(uid), (type(spin) == 'table' and type(spin.Player) == 'table') and 'oui' or 'NON', tostring(name)))
    end
    if not license then return false end
    name = (name or 'Inconnu'):sub(1, 64)

    local onDup = def.agg == 'max'
        and '`value` = GREATEST(`value`, VALUES(`value`)), `name` = VALUES(`name`), `uid` = VALUES(`uid`)'
        or '`value` = `value` + VALUES(`value`), `name` = VALUES(`name`), `uid` = VALUES(`uid`)'

    MySQL.insert(
        ('INSERT INTO `%s` (`license`, `stat`, `name`, `uid`, `value`) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE %s'):format(TABLE, onDup),
        { license, stat, name, tostring(uid or ''), amount },
        function() dirty = true end
    )
    return true
end

exports('AddStat', AddStat)

-- Classements externes (ex : crews) : exports['adam_zombi_leaderboard']:SetBoardRows('crews', { {name=..., value=...}, ... })
exports('SetBoardRows', function(id, rows)
    local def = boardDefs[id]
    if not def or not def.external or type(rows) ~= 'table' then return false end
    local clean = {}
    for i, r in ipairs(rows) do
        if i > (Config.topCount or 10) then break end
        clean[i] = { name = tostring(r.name or '?'):sub(1, 64), uid = tostring(r.uid or ''), value = math.floor(tonumber(r.value) or 0) }
    end
    externalRows[id] = clean
    dirty = true
    return true
end)

-- Pour le menu de la zone zombie : renvoie les classements et le meilleur chasseur
exports('GetBoards', function() return cache, champion end)

-- ---------- Envoi à un joueur ----------
local lastRequest = {}

RegisterNetEvent('adam_zombi_lb:request', function()
    local src = source
    local now = GetGameTimer()
    if (lastRequest[src] or 0) + 5000 > now then return end
    lastRequest[src] = now
    if ready then
        TriggerClientEvent('adam_zombi_lb:update', src, cache, champion)
    end
end)

AddEventHandler('playerDropped', function() lastRequest[source] = nil end)

-- ---------- /zlbreset <classement|all> ----------
-- Réservé au rôle fondateur (Config.adminRoles) ou à la console serveur
local function lowerStr(v) return v ~= nil and tostring(v):lower() or nil end

local function collectRoles(src)
    local out = {}
    local function add(label, v)
        if type(v) == 'string' or type(v) == 'number' then out[#out + 1] = { label, tostring(v) } end
    end
    local spin = rawget(_G, 'Spin')
    local spinOk = false
    if type(spin) == 'table' and type(spin.Player) == 'table' then
        spinOk = true
        pcall(function() add('Spin.group', spin.Player.GetGroup(src)) end)
        pcall(function()
            local j = spin.Player.GetJob(src)
            if type(j) == 'table' then
                for _, key in ipairs({ 'name', 'label', 'grade_name', 'grade_label' }) do add('Spin.job.' .. key, j[key]) end
            end
        end)
        pcall(function() add('Spin.uniqueId', spin.Player.GetUniqueId(src)) end)
    end
    local ESX = getESX()
    local xPlayer = ESX and ESX.GetPlayerFromId(src)
    if not xPlayer then return out, spinOk end
    local function try(label, fn)
        local ok, v = pcall(fn)
        if ok then add(label, v) end
    end
    for _, key in ipairs({ 'group', 'rank', 'role', 'grade', 'permission_level', 'perm' }) do
        try(key, function() return xPlayer[key] end)
    end
    for _, fn in ipairs({ 'getGroup', 'getRank', 'getRole', 'getGrade', 'getPermissionLevel' }) do
        try(fn .. '()', function() return xPlayer[fn] and xPlayer[fn]() end)
    end
    local okJ, job = pcall(function() return xPlayer.getJob and xPlayer.getJob() or xPlayer.job end)
    if okJ and type(job) == 'table' then
        for _, key in ipairs({ 'name', 'label', 'grade_name', 'grade_label', 'grade' }) do add('job.' .. key, job[key]) end
    end
    return out, true
end

local function isFounder(src)
    if src == 0 then return true end -- console
    local wanted = {}
    for _, r in ipairs(Config.adminRoles or {}) do wanted[lowerStr(r)] = true end
    for _, entry in ipairs((collectRoles(src))) do
        if entry[1] ~= 'Spin.uniqueId' and wanted[lowerStr(entry[2])] then return true end
    end
    return false
end
RegisterCommand('zlbreset', function(src, args)
    local stat = args[1]
    local function reply(msg)
        if src == 0 then print('[Zombie Leaderboard] ' .. msg)
        else TriggerClientEvent('chat:addMessage', src, { args = { 'Leaderboard', msg } }) end
    end
    if not isFounder(src) then
        reply('Tu n\'as pas la permission (rôle fondateur requis).')
        return
    end
    if stat == 'all' then
        MySQL.update(('DELETE FROM `%s`'):format(TABLE), {}, function() dirty = true end)
        reply('Tous les classements zombie ont été remis à zéro.')
    elseif stat and boardDefs[stat] then
        MySQL.update(('DELETE FROM `%s` WHERE `stat` = ?'):format(TABLE), { stat }, function() dirty = true end)
        reply(('Classement "%s" remis à zéro.'):format(stat))
    else
        reply('Usage : /zlbreset <zombies|terrifier|wave|tickets|all>')
    end
end, false)
