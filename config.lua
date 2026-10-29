Config = {}

Config.Ped = {
    model = 'u_m_y_zombie_01',
    coords = vector4(-71.8805, -811.2636, 285.0001, 157.0258),
    scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
}

Config.Zone = {
    routingBucket = 238, -- instance partagée (utilisée seulement si soloInstance = false)
    soloInstance = true, -- true = chaque joueur est seul dans sa propre instance
    soloBucketBase = 23800, -- instance solo = soloBucketBase + ID du joueur
    center = vector3(1680.0, 2510.0, 45.0),
    radius = 75.0,
    returnCoords = vector4(-71.8805, -811.2636, 285.0001, 157.0258),
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
    weapon = 'weapon_knife',
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
Config.TicketMax = 50
Config.RareWeapon = 'WEAPON_HKUMP'
Config.RareWeaponLabel = 'HKUMP' -- nom affiché dans l'UI
Config.RareWeaponChance = 0,5 -- pourcentage par zombie tué
Config.InteractDistance = 2.0
Config.PedDrawDistance = 25.0
Config.KillRewardCooldown = 0 -- récompense validée par zombie, sans délai global
