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

    -- On reload, guild roster may not be ready so currentKey can be nil even when in a guild.
    -- Only wipe when we're sure the guild changed: different non-nil keys, or confirmed left guild.
    local guildSwitch = (currentKey ~= nil and previousKey ~= nil and currentKey ~= previousKey)
    local guildJoin = (currentKey ~= nil and previousKey == nil)
    local leftGuildDeferred = (currentKey == nil and previousKey ~= nil)

    -- When currentKey is nil but we had a guild, defer: might be reload (roster not ready) or actually left.
    if leftGuildDeferred then
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                local keyNow = GetCurrentGuildKey()
                if keyNow == nil and addon.Database and addon.Database.achievementGuildKey == previousKey then
                    -- Still no guild after delay: really left. Wipe and clear key.
                    if Private.DatabaseUtils and Private.DatabaseUtils.WipeLocalAchievementProgress then
                        Private.DatabaseUtils:WipeLocalAchievementProgress()
                    end
                    if Private.AchievementEngine and Private.AchievementEngine.ResetAllProgress then
                        Private.AchievementEngine:ResetAllProgress()
                        Private.AchievementEngine:SaveProgress(true)
                    end
                    local ts = Private.TicketSyncUtils
                    if ts and ts.WipeAllTickets then ts:WipeAllTickets() end
                    if ts and ts.StopHeartbeat then ts:StopHeartbeat() end
                    local gs = Private.GuildSyncUtils
                    if gs and gs.StopHeartbeat then gs:StopHeartbeat() end
                    if gs and gs.WipeGuildSyncState then gs:WipeGuildSyncState() end
                    local cs = Private.CorrectionSyncUtils
                    if cs and cs.WipeAllCorrections then cs:WipeAllCorrections() end
                    addon.Database.achievementGuildKey = nil
                end
            end)
        end
        return
    end

    local guildActuallyChanged = guildSwitch or guildJoin

    -- Wipe local achievement progress only when guild actually changed.
    if guildActuallyChanged then
        if Private.DatabaseUtils and Private.DatabaseUtils.WipeLocalAchievementProgress then
            Private.DatabaseUtils:WipeLocalAchievementProgress()
        end
        if Private.AchievementEngine and Private.AchievementEngine.ResetAllProgress then
            Private.AchievementEngine:ResetAllProgress()
            Private.AchievementEngine:SaveProgress(true)
        end
    end

    -- Wipe tickets/corrections only when guild actually changed (not on reload).
    local ticketSync = Private.TicketSyncUtils
    if guildActuallyChanged and ticketSync and ticketSync.WipeAllTickets then
        ticketSync:WipeAllTickets()
    end
    if ticketSync and ticketSync.StopHeartbeat then
        ticketSync:StopHeartbeat()
    end
    if currentKey ~= nil and ticketSync and ticketSync.OnPlayerLogin then
        ticketSync:OnPlayerLogin()
    end

    -- Guild sync: wipe and stop when leaving/switching; restart when in a guild.
    local guildSync = Private.GuildSyncUtils
    if guildActuallyChanged and guildSync and guildSync.WipeGuildSyncState then
        guildSync:WipeGuildSyncState()
    end
    if guildSync and guildSync.StopHeartbeat then
        guildSync:StopHeartbeat()
    end
    if currentKey ~= nil and guildSync and guildSync.OnPlayerLogin then
        guildSync:OnPlayerLogin()
    end

    if guildActuallyChanged then
        local correctionSync = Private.CorrectionSyncUtils
        if correctionSync and correctionSync.WipeAllCorrections then
            correctionSync:WipeAllCorrections()
        end
    end

    if currentKey ~= nil then
        addon.Database.achievementGuildKey = currentKey
    end
end

function addon:OnInitialize(...)
    Private.SettingsUtils:Init()
    Private.CommsUtils:Init()
    Private.UnitCache:Init()
    Private.CommandUtils:Init()
    Private.EventBridge:Init()
    Private.AchievementEngine:Init()
    Private.GuildSyncUtils:Init()
    if Private.TicketSyncUtils and Private.TicketSyncUtils.Init then
        Private.TicketSyncUtils:Init()
    end
    if Private.CorrectionSyncUtils and Private.CorrectionSyncUtils.Init then
        Private.CorrectionSyncUtils:Init()
    end
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
