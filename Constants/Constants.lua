local ADDON_NAME = ...
---@cast ADDON_NAME string

---@class AddonPrivate
local Private = select(2, ...)

local constants = {}

Private.constants = constants

constants.ADDON_NAME = ADDON_NAME
constants.ADDON_VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
constants.ADDON_MEDIA_PATH = [[Interface\AddOns\]] .. constants.ADDON_NAME .. [[\Media]]
constants.INTERFACE_VERSION = select(4, GetBuildInfo())

constants.MEDIA = {
    TEXTURES = {
        LOGO = constants.ADDON_MEDIA_PATH .. [[\Textures\logo.tga]],
    },
    SOUNDS = {
        ACHIEVEMENT_EARNED = constants.ADDON_MEDIA_PATH .. [[\Sounds\achievmentsound1.ogg]],
    }
}

constants.COLORS = {
    WHITE = CreateColor(1, 1, 1, 1),
    YELLOW = CreateColor(1, 0.82, 0, 1),
    GREY = CreateColor(0.33, 0.27, 0.20, 1),
    LIGHT_GREY = CreateColor(0.5, 0.5, 0.5, 1),
}

constants.ADDON_COMMS = {
    PREFIX = "ReckoningComms",
    PROTOCOL_VERSION = 1,
}

constants.SETTINGS = {
    TYPES = {
        BOOLEAN = "boolean",
        NUMBER = "number",
        STRING = "string",
    }
}

constants.GUILD_FRAME_NAME = "GuildFrame"

-------------------------------------------------------------------------------
-- Customizable Display Settings
-- These can be overridden by users in config.lua
-------------------------------------------------------------------------------

constants.DISPLAY = {
    -- The name shown for achievement points throughout the UI
    -- Change this to customize what points are called (e.g., "Glory", "Honor", "Score")
    POINTS_NAME = "Points",
    POINTS_NAME_SINGULAR = "Point",
}

-------------------------------------------------------------------------------
-- Achievement Announcement Settings
-------------------------------------------------------------------------------

constants.ANNOUNCEMENTS = {
    -- Whether to show achievement chat links when you earn an achievement
    SHOW_PERSONAL_MESSAGE = true,
    -- Whether to broadcast achievement completions to guild members
    BROADCAST_TO_GUILD = true,
    -- Whether to show messages when guild members earn achievements
    SHOW_GUILD_MESSAGES = true,
    -- Whether to send a guild chat message when you earn an achievement
    SEND_GUILD_CHAT = true,
}

-------------------------------------------------------------------------------
-- Fall Detection
-------------------------------------------------------------------------------

constants.FALLING = {
    -- TODO: Tune this threshold to match ~65 yards of fall distance.
    MIN_SECONDS = 3.0,
}

-------------------------------------------------------------------------------
-- Enums
-------------------------------------------------------------------------------

---@class Enums
local Enums = {}
Private.Enums = Enums

-- Cadence: How often achievement progress resets
---@enum Enums.Cadence
Enums.Cadence = {
    AllTime = 1,  -- Never resets
    Weekly = 2,   -- Resets on Tuesday
    OneTime = 3,  -- Time-limited, never repeatable
}

-- Difficulty: Dungeon/Raid difficulty
---@enum Enums.Difficulty
Enums.Difficulty = {
    Normal = 1,
    Heroic = 2,
}

-- Class: Player classes
---@enum Enums.Class
Enums.Class = {
    Warrior = 1,
    Paladin = 2,
    Hunter = 3,
    Rogue = 4,
    Priest = 5,
    Shaman = 7,
    Mage = 8,
    Warlock = 9,
    Druid = 11,
}

-- BattlegroundResult: Outcome of a battleground match
---@enum Enums.BattlegroundResult
Enums.BattlegroundResult = {
    Victory = 1,
    Defeat = 2,
}

-- ArenaBracket: Arena team sizes
---@enum Enums.ArenaBracket
Enums.ArenaBracket = {
    TwoVTwo = 2,
    ThreeVThree = 3,
    FiveVFive = 5,
}

-- ObjectiveType: PvP objective types
---@enum Enums.ObjectiveType
Enums.ObjectiveType = {
    Flag = 1,
    Base = 2,
    Tower = 3,
}

-- GatherType: Gathering profession types
---@enum Enums.GatherType
Enums.GatherType = {
    Mining = 1,
    Herbalism = 2,
    Skinning = 3,
}

-- Profession: All professions
---@enum Enums.Profession
Enums.Profession = {
    Alchemy = 171,
    Blacksmithing = 164,
    Enchanting = 333,
    Engineering = 202,
    Herbalism = 182,
    Jewelcrafting = 755,
    Leatherworking = 165,
    Mining = 186,
    Skinning = 393,
    Tailoring = 197,
    Cooking = 185,
    FirstAid = 129,
    Fishing = 356,
}

-- FishPoolType: Fishing pool types
---@enum Enums.FishPoolType
Enums.FishPoolType = {
    OpenWater = 1,
    School = 2,
}

-- Standing: Reputation standings
---@enum Enums.Standing
Enums.Standing = {
    Hated = 1,
    Hostile = 2,
    Unfriendly = 3,
    Neutral = 4,
    Friendly = 5,
    Honored = 6,
    Revered = 7,
    Exalted = 8,
}

-- BadgeSource: Where badges come from
---@enum Enums.BadgeSource
Enums.BadgeSource = {
    Boss = 1,
    Quest = 2,
}

-- KeyType: Key types
---@enum Enums.KeyType
Enums.KeyType = {
    Heroic = 1,
    Attunement = 2,
}

-- EquipSlot: Equipment slots
---@enum Enums.EquipSlot
Enums.EquipSlot = {
    Head = 1,
    Neck = 2,
    Shoulder = 3,
    Back = 15,
    Chest = 5,
    Wrist = 9,
    Hands = 10,
    Waist = 6,
    Legs = 7,
    Feet = 8,
    Finger1 = 11,
    Finger2 = 12,
    Trinket1 = 13,
    Trinket2 = 14,
    MainHand = 16,
    OffHand = 17,
    Ranged = 18,
}

-- ItemQuality: Item quality tiers
---@enum Enums.ItemQuality
Enums.ItemQuality = {
    Poor = 0,
    Common = 1,
    Uncommon = 2,
    Rare = 3,
    Epic = 4,
    Legendary = 5,
}

-- RollType: Loot roll types
---@enum Enums.RollType
Enums.RollType = {
    Need = 1,
    Greed = 2,
    Disenchant = 3,
}

-- CreatureType: Creature classification types
---@enum Enums.CreatureType
Enums.CreatureType = {
    Beast = 1,
    Humanoid = 7,
    Demon = 3,
    Undead = 6,
    Elemental = 4,
    Giant = 5,
    Mechanical = 9,
    Dragonkin = 2,
    Aberration = 10,
    Critter = 8,
}