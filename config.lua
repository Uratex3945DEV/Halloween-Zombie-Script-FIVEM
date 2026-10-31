Config = {}

Config.Ped = {
    model = 'u_m_y_zombie_01',
    coords = vector4(241.7611, -891.0092, 30.4921, 42.8752),
    scenario = 'WORLD_HUMAN_CLIPBOARD'
}

Config.Zone = {
    routingBucket = 238, -- instance partagée (utilisée seulement si soloInstance = false)
    soloInstance = true, -- true = chaque joueur est seul dans sa propre instance
    crewBucketBase = 24800, -- instance crew = crewBucketBase + id du crew (même monde pour les membres)
    soloBucketBase = 23800, -- instance solo = soloBucketBase + ID du joueur
    center = vector3(-1282.5094, -3112.8430, 14.2813),
    radius = 75.0,
    returnCoords = vector4(241.7611, -891.0092, 30.4921, 42.8752),
    maxZombies = 12, -- nombre de zombies vivants en même temps
    spawnRadiusMin = 12.0,
    spawnRadiusMax = 45.0
}

Config.Waves = {
    startDelay = 5000,        -- délai avant la 1ère vague (ms)
    betweenWaves = 10000,     -- pause entre deux vagues (ms)
    spawnInterval = 800,      -- délai entre deux apparitions dans une vague (ms)
    baseZombies = 6,          -- zombies en vague 1
    zombiesPerWave = 3,       -- zombies en plus à chaque vague
    maxZombiesPerWave = 40    -- plafond de zombies par vague
}

Config.Terrifier = {
    enabled = true,
    model = 'Terrifier_ATC',  -- doit être streamé par une autre ressource
    weapon = 'weapon_minigun',
    health = 600,
    moveRate = 1.15,
    startWave = 3,            -- 1ère vague où il apparaît
    everyNWaves = 3,          -- puis toutes les N vagues
    count = 1                 -- nombre de Terrifier par apparition
}

Config.Death = {
    reviveEvent = 'esx_ambulancejob:revive', -- évènement client de revive (nil pour désactiver)
    invincibleMs = 3000                      -- invincibilité après le revive
}

Config.WaveAnnounce = {
    enabled = true,
    duration = 4500,                              -- durée d'affichage de la bannière (ms)
    subtitle = 'Les morts se réveillent...',
    terrifierSubtitle = 'Le Terrifier approche...',
    -- Sons natifs GTA (aucun fichier requis)
    sound = { name = 'Event_Start_Text', set = 'GTAO_FM_Events_Soundset' },
    terrifierSound = { name = 'ScreenFlash', set = 'WastedSounds' },
    -- Son perso (optionnel) : dépose un .mp3/.ogg dans html/sounds/ puis mets son nom ici.
    -- Si renseigné, il remplace les sons natifs ci-dessus.
    customSound = "zombie.mp3",                            -- ex: 'halloween.mp3'
    volume = 0.6                                  -- 0.0 à 1.0 (son perso uniquement)
}

Config.Blips = {
    enabled = true,
    zombie = {
        sprite = 1,       -- 1 = rond standard
        color = 1,        -- 1 = rouge
        scale = 0.6,
        label = 'Zombie'
    },
    terrifier = {
        sprite = 303,     -- crâne
        color = 76,       -- rouge sombre
        scale = 0.9,
        label = 'Terrifier'
    }
}

Config.ZombieModels = { 'u_m_y_zombie_01' } -- ajoute d'autres modèles ici si besoin

Config.TicketItem = 'ticket_halloween'
Config.TicketMin = 10
Config.TicketMax = 60
Config.RareWeapon = 'WEAPON_REDL'
Config.RareWeaponLabel = 'AK RedLight' -- nom affiché dans l'UI
Config.RareWeaponChance = 1 -- pourcentage par zombie tué
Config.InteractDistance = 2.0
Config.PedDrawDistance = 25.0
Config.KillRewardCooldown = 0 -- récompense validée par zombie, sans délai global


-- Munitions illimitées dans la zone zombie (plus besoin de balles, pas de rechargement).
Config.InfiniteAmmo = true

-- Stats des zombies classiques
Config.Zombie = {
    health = 250,
    moveRate = 1.20
}

-- /configzombie : qui peut modifier la config en jeu ?
-- Un joueur est autorisé si l'une de ces valeurs (insensible à la casse) correspond à son
-- groupe, au nom de son job, ou au nom/label de son grade. (ESX / SpinFramework)
Config.Admin = {
    command = 'configzombie',
    roles = { 'fondateur' },
    saveFile = 'settings.json'  -- réglages sauvegardés dans la ressource (persistent au restart)
}

-- Crews (créés depuis le menu, validés par les fondateurs dans /configzombie)
Config.Crew = {
    price = 5000000,          -- prix de création (payé à la demande)
    account = 'bank',         -- compte débité : 'bank', 'money' (espèces) ou 'black_money'
    maxMembers = 10,          -- membres max par crew (owner inclus)
    nameMin = 3,
    nameMax = 20,
    inviteTtl = 300,          -- secondes avant expiration d'une invitation
    refundOnReject = true     -- rembourse le prix si une demande en attente est supprimée
}

-- Liste des réglages modifiables via /configzombie (path = chemin dans Config)
Config.Editable = {
    { path = 'InfiniteAmmo',            group = 'Général',   label = 'Munitions illimitées', type = 'boolean' },
    { path = 'Zone.maxZombies',         group = 'Général',   label = 'Zombies vivants max',  type = 'number', min = 1,   max = 100 },
    { path = 'Zone.spawnRadiusMin',     group = 'Général',   label = 'Rayon spawn min (m)',  type = 'number', min = 1,   max = 200, step = 0.5 },
    { path = 'Zone.spawnRadiusMax',     group = 'Général',   label = 'Rayon spawn max (m)',  type = 'number', min = 2,   max = 300, step = 0.5 },

    { path = 'Waves.startDelay',        group = 'Vagues',    label = 'Délai 1ère vague (ms)',   type = 'number', min = 0,   max = 120000, step = 500 },
    { path = 'Waves.betweenWaves',      group = 'Vagues',    label = 'Pause entre vagues (ms)', type = 'number', min = 0,   max = 300000, step = 500 },
    { path = 'Waves.spawnInterval',     group = 'Vagues',    label = 'Intervalle spawn (ms)',   type = 'number', min = 100, max = 30000,  step = 100 },
    { path = 'Waves.baseZombies',       group = 'Vagues',    label = 'Zombies vague 1',         type = 'number', min = 1,   max = 200 },
    { path = 'Waves.zombiesPerWave',    group = 'Vagues',    label = 'Zombies en plus / vague', type = 'number', min = 0,   max = 100 },
    { path = 'Waves.maxZombiesPerWave', group = 'Vagues',    label = 'Plafond par vague',       type = 'number', min = 1,   max = 500 },

    { path = 'Zombie.health',           group = 'Zombies',   label = 'Vie zombie',           type = 'number', min = 1,   max = 5000 },
    { path = 'Zombie.moveRate',         group = 'Zombies',   label = 'Vitesse zombie',       type = 'number', min = 0.5, max = 3.0, step = 0.05 },

    { path = 'Terrifier.enabled',       group = 'Terrifier', label = 'Terrifier activé',     type = 'boolean' },
    { path = 'Terrifier.health',        group = 'Terrifier', label = 'Vie Terrifier',        type = 'number', min = 1,   max = 20000 },
    { path = 'Terrifier.moveRate',      group = 'Terrifier', label = 'Vitesse Terrifier',    type = 'number', min = 0.5, max = 3.0, step = 0.05 },
    { path = 'Terrifier.startWave',     group = 'Terrifier', label = '1ère vague',           type = 'number', min = 1,   max = 100 },
    { path = 'Terrifier.everyNWaves',   group = 'Terrifier', label = 'Toutes les N vagues',  type = 'number', min = 1,   max = 100 },
    { path = 'Terrifier.count',         group = 'Terrifier', label = 'Nombre par apparition',type = 'number', min = 1,   max = 10 },

    { path = 'Crew.price',              group = 'Crew',      label = 'Prix création crew ($)', type = 'number', min = 0, max = 1000000000, step = 10000 },
    { path = 'Crew.maxMembers',         group = 'Crew',      label = 'Membres max / crew',   type = 'number', min = 1, max = 100 },

    { path = 'TicketItem',              group = 'Récompenses', label = 'Item ticket',        type = 'string' },
    { path = 'TicketMin',               group = 'Récompenses', label = 'Tickets min',        type = 'number', min = 0,   max = 100000 },
    { path = 'TicketMax',               group = 'Récompenses', label = 'Tickets max',        type = 'number', min = 0,   max = 100000 },
    { path = 'RareWeapon',              group = 'Récompenses', label = 'Arme rare (item)',   type = 'string' },
    { path = 'RareWeaponChance',        group = 'Récompenses', label = 'Chance arme rare (%)', type = 'number', min = 0, max = 100, step = 0.5 },
}

-- ---------- Helpers partagés (client + serveur) ----------
function ZConfigGet(path)
    local node = Config
    for key in path:gmatch('[^%.]+') do
        if type(node) ~= 'table' then return nil end
        node = node[key]
    end
    return node
end

function ZConfigSet(path, value)
    local node = Config
    local keys = {}
    for key in path:gmatch('[^%.]+') do keys[#keys + 1] = key end
    for i = 1, #keys - 1 do
        node = node[keys[i]]
        if type(node) ~= 'table' then return false end
    end
    node[keys[#keys]] = value
    return true
end

-- Copie des valeurs d'origine (pour la réinitialisation)
Config.Defaults = {}
for _, f in ipairs(Config.Editable) do
    Config.Defaults[f.path] = ZConfigGet(f.path)
end

-- Leaderboard : zombies tués, Terrifier tués, meilleure vague et tickets gagnés
-- sont envoyés à la ressource adam_zombi_leaderboard (ignoré si elle n'est pas démarrée)
Config.Leaderboard = {
    enabled  = true,
    resource = 'adam_zombi_leaderboard',
    table    = 'adam_zombie_leaderboard', -- table SQL du leaderboard (pour calculer le top des crews)
    crewBoard = 'crews',                  -- id du classement crews dans adam_zombi_leaderboard
    crewStats = { 'zombies', 'terrifier' } -- kills comptés pour le score d'un crew
}


-- Concours : chrono + gagnant = joueur avec le plus de zombies tués (stat du leaderboard) à la fin.
-- Le gagnant est figé à l'heure de fin et visible dans /configzombie (nom, ID unique, kills).
Config.Contest = {
    enabled   = true,
    endsAt    = '2026-11-06 20:00', -- date et heure de fin (AAAA-MM-JJ HH:MM)
    utcOffset = 1,                  -- décalage du fuseau de endsAt par rapport à UTC (Belgique/France : +1 en hiver, +2 en été)
    stat      = 'zombies'           -- classement utilisé (zombies tués)
}
