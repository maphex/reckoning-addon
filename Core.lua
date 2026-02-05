---@class AddonPrivate
local Private = select(2, ...)

local const = Private.constants
local addon = Private.Addon

local function GetCurrentGuildKey()
    if type(IsInGuild) ~= "function" or not IsInGuild() then
        return nil
    end
    if type(GetGuildInfo) ~= "function" then
        return nil
    end
    local guildName = GetGuildInfo("player")
    if not guildName or guildName == "" then
        return nil
    end
    local realm = (type(GetRealmName) == "function") and GetRealmName() or ""
    return tostring(guildName) .. "@" .. tostring(realm)
end

local function HasAnyLocalAchievementProgress()
    if not addon.Database then return false end
    local db = addon.Database
    if db.achievementData or db.achievementDataRaw then
        return true
    end
    if type(db.completed) == "table" and next(db.completed) ~= nil then
        return true
    end
    if type(db.progress) == "table" and next(db.progress) ~= nil then
        return true
    end
    return false
end

local function HandleGuildMembershipChanged()
    if not addon.Database then return end

    local currentKey = GetCurrentGuildKey()
    local previousKey = addon.Database.achievementGuildKey

    -- If we haven't stored a guild key yet (new field) and we're currently unguilded,
    -- but we do have achievement data, wipe it so achievements never show while unguilded.
    if previousKey == currentKey and not (currentKey == nil and HasAnyLocalAchievementProgress()) then
        return
    end

    -- Wipe local achievement progress on guild join/leave/switch.
    if Private.DatabaseUtils and Private.DatabaseUtils.WipeLocalAchievementProgress then
        Private.DatabaseUtils:WipeLocalAchievementProgress()
    end
    if Private.AchievementEngine and Private.AchievementEngine.ResetAllProgress then
        Private.AchievementEngine:ResetAllProgress()
        -- Persist the wipe immediately (silent to avoid chat spam on guild events).
        Private.AchievementEngine:SaveProgress(true)
    end

    -- Record the new guild key after wiping (so we don't wipe repeatedly).
    addon.Database.achievementGuildKey = currentKey
end

function addon:OnInitialize(...)
    Private.SettingsUtils:Init()
    Private.CommsUtils:Init()
    Private.CommandUtils:Init()
    Private.EventBridge:Init()
    Private.AchievementEngine:Init()
    Private.GuildSyncUtils:Init()
end

function addon:OnEnable(...)
    Private.DatabaseUtils:LoadDefaultsForMissing()
    Private.UpdateUtils:OnEnable()

    -- Track guild membership changes: achievements only count while in the guild,
    -- and local achievement progress is wiped on join/leave/switch.
    ---@diagnostic disable-next-line: param-type-mismatch
    self:RegisterEvent("PLAYER_GUILD_UPDATE", "RECKONING_GUILD_MEMBERSHIP_CHANGED", function()
        HandleGuildMembershipChanged()
    end)
    ---@diagnostic disable-next-line: param-type-mismatch
    self:RegisterEvent("GUILD_ROSTER_UPDATE", "RECKONING_GUILD_MEMBERSHIP_CHANGED_ROSTER", function()
        HandleGuildMembershipChanged()
    end)
    HandleGuildMembershipChanged()

    -- Load current week from DatabaseUtils
    local dbUtils = Private.DatabaseUtils
    if dbUtils then
        local currentWeek = dbUtils:GetCurrentWeek()
        Private.AchievementUtils:SetCurrentWeek(currentWeek)

        -- Load explored zones into EventBridge
        if Private.EventBridge then
            Private.EventBridge.exploredZones = dbUtils:LoadExploredZones()
        end
    end
end

function addon:OnDisable(...)
    -- Unregister guild tracking events
    ---@diagnostic disable-next-line: param-type-mismatch
    self:UnregisterEvent("PLAYER_GUILD_UPDATE")
    ---@diagnostic disable-next-line: param-type-mismatch
    self:UnregisterEvent("GUILD_ROSTER_UPDATE")
end
