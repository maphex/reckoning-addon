---@class AddonPrivate
local Private = select(2, ...)
local const = Private.constants

-- Account-wide SavedVariables (achievements are account-wide)
local defaultDatabase = {
    version = 1,
    settings = {
        guildSync = {
            showLogs = false,
        },
    },
    -- Achievements only count while you are in a guild.
    -- We store the last known guild key to detect join/leave/switch and wipe achievement progress accordingly.
    achievementGuildKey = nil,
    -- Encoded achievement data (with hash verification)
    achievementData = nil,        -- Encoded + compressed achievement progress
    achievementHash = nil,        -- Hash for tamper detection
    achievementVersion = 1,       -- Data format version
    lastSaved = 0,                -- Timestamp of last save
    -- Legacy/fallback fields (used if encoding fails)
    progress = {},                -- Achievement ID -> count progress
    criteriaProgress = {},        -- Achievement ID -> { [criteriaIndex] = true/false }
    completed = {},               -- Achievement ID -> { completedAt = timestamp, week = number }
    completedTimestamps = {},     -- Achievement ID -> timestamp
    lastWeek = 0,                 -- Last processed week number
    -- Explored zones tracking
    exploredZones = {},           -- Zone|SubZone -> true
    -- Guild sync cache
    guildCache = {
        members = {},             -- PlayerName -> GuildMemberData
        events = {},              -- Recent guild events
        tickets = {},             -- TicketId -> AchievementBugTicket
        ticketsSavedAt = 0,       -- Last ticket cache save time
        achievementCorrections = {}, -- CorrectionId -> AchievementCorrection (officer invalidate/revalidate)
        achievementCorrectionsSavedAt = 0,
        savedAt = 0,              -- Last cache save time
    },
}

-- Per-character SavedVariables (currently unused, placeholder for future)
local defaultCharDatabase = {
    char = {
    },
}

---@class Reckoning : RasuAddonBase
local addon = LibStub("RasuAddon"):CreateAddon(
    const.ADDON_NAME,
    "ReckoningDB",
    defaultDatabase,
    nil,
    nil,
    nil,
    "ReckoningCharDB",
    defaultCharDatabase
)

Private.Addon = addon

-- Expose Private for files loaded via XML (which don't receive ...)
Reckoning = Reckoning or {}
Reckoning.Private = Private

local localeObj = LibStub("RasuLocale"):CreateLocale(const.ADDON_NAME)
localeObj:AddFullTranslationTbl(Private.Locales)
localeObj:SetLocale(GetLocale())

Private.L = localeObj:GetTranslationObj()
