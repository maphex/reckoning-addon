---@class AddonPrivate
local Private = select(2, ...)

---@class CommandUtils
local commandUtils = {
    ---@type table<any, string>
    L = nil,
    ---@type Reckoning
    addon = nil,
}
Private.CommandUtils = commandUtils

local const = Private.constants

function commandUtils:Init()
    self.L = Private.L

    -- Production commands only - safe for all users
    local subCommands = {
        default = self.OnAchievementsCommand,

        [self.L["CommandUtils.CollectionsCommand"]] = self.OnAchievementsCommand,
        [self.L["CommandUtils.CollectionsCommandShort"]] = self.OnAchievementsCommand,

        [self.L["CommandUtils.SettingsCommand"]] = self.OnSettingsCommand,
        [self.L["CommandUtils.SettingsCommandShort"]] = self.OnSettingsCommand,

        -- Help command
        ["help"] = self.OnHelpCommand,
        ["?"] = self.OnHelpCommand,

        -- Info command (safe version)
        ["info"] = self.OnInfoCommand,
        ["version"] = self.OnInfoCommand,

        -- Reset saved variables
        ["reset"] = self.OnResetCommand,
        ["clear"] = self.OnResetCommand,
        ["resetdb"] = self.OnResetCommand,
    }

    -- If DebugCommands module is loaded (dev mode), register debug commands
    local debugCommands = Private.DebugCommands
    if debugCommands and debugCommands.isLoaded then
        local debugCmds = debugCommands:GetCommands()
        for cmd, handler in pairs(debugCmds) do
            subCommands[cmd] = function(self, args)
                handler(debugCommands, args)
            end
        end
        -- Add debug help to the help command
        self.debugEnabled = true
    end

    Private.Addon:RegisterCommand({
        "R",
        "Reckoning",
    }, function(addon, args)
        if args and #args > 0 then
            local cmd = args[1]
            if subCommands[cmd] then
                -- Pass remaining args
                local remainingArgs = {}
                for i = 2, #args do
                    table.insert(remainingArgs, args[i])
                end
                subCommands[cmd](self, remainingArgs)
                return
            end
        elseif args == nil or #args == 0 then
            subCommands["default"](self)
            return
        end
        self:OnUnknownCommand(addon)
    end)
end

-------------------------------------------------------------------------------
-- Production Commands
-------------------------------------------------------------------------------

function commandUtils:OnUnknownCommand(addon)
    addon:Print(self.L["CommandUtils.UnknownCommand"])
    addon:Print("Type |cffffffff/r help|r for available commands.")
end

function commandUtils:OnSettingsCommand()
    Private.SettingsUtils:Open()
end

function commandUtils:OnAchievementsCommand()
    -- Toggle achievement frame
    if ReckoningAchievementFrame then
        if ReckoningAchievementFrame:IsShown() then
            ReckoningAchievementFrame:Hide()
        else
            ReckoningAchievementFrame:Show()
        end
    else
        Private.Addon:Print("Achievement frame not found")
    end
end

function commandUtils:OnHelpCommand(args)
    local addon = Private.Addon
    addon:Print("=== Reckoning Commands ===")
    addon:Print("|cffffffff/r|r or |cffffffff/reckoning|r - Toggle achievements window")
    addon:Print("|cffffffff/r settings|r - Open settings")
    addon:Print("|cffffffff/r info|r - Show addon information")
    addon:Print("|cffffffff/r reset confirm|r - Clear saved data")
    addon:Print("|cffffffff/r help|r - Show this help")

    -- If debug mode is enabled, show additional info
    if self.debugEnabled then
        addon:Print("")
        addon:Print("|cffff6600[DEV MODE] Debug commands available!|r")
        addon:Print("|cffffffff/r debug help|r - Show debug commands")
    end
end

function commandUtils:OnInfoCommand(args)
    local addon = Private.Addon
    local aUtils = Private.AchievementUtils
    local engine = Private.AchievementEngine
    local dbUtils = Private.DatabaseUtils

    addon:Print("=== Reckoning ===")
    -- Use C_AddOns.GetAddOnMetadata for newer WoW versions, fallback to addon.Version
    local version = addon.Version or "Unknown"
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        version = C_AddOns.GetAddOnMetadata("Reckoning", "Version") or version
    end
    addon:Print("Version: " .. version)

    -- Safe info only - no manipulation hints
    local currentWeek = dbUtils and dbUtils:GetCurrentWeek() or 0
    addon:Print("Current Week: " .. currentWeek)

    -- Count achievements
    local totalAchievements = 0
    local completedAchievements = 0

    if aUtils and aUtils.achievements then
        for id, _ in pairs(aUtils.achievements) do
            totalAchievements = totalAchievements + 1
            if engine and engine:IsCompleted(id) then
                completedAchievements = completedAchievements + 1
            end
        end
    end

    addon:Print("Achievements: " .. completedAchievements .. "/" .. totalAchievements .. " completed")

    -- Calculate total points
    local earnedPoints = 0
    local totalPoints = 0
    if aUtils and aUtils.achievements then
        for id, achievement in pairs(aUtils.achievements) do
            local points = achievement.points or 0
            totalPoints = totalPoints + points
            if engine and engine:IsCompleted(id) then
                earnedPoints = earnedPoints + points
            end
        end
    end

    local pointsName = const and const.DISPLAY and const.DISPLAY.POINTS_NAME or "Points"
    addon:Print(pointsName .. ": " .. earnedPoints .. "/" .. totalPoints)
end

function commandUtils:OnResetCommand(args)
    local addon = Private.Addon
    if not addon then return end

    local confirm = args and args[1] == "confirm"
    if not confirm then
        addon:Print("This will clear all Reckoning saved data.")
        addon:Print("Type |cffffffff/r reset confirm|r to proceed.")
        return
    end

    local defaultDB = addon.DefaultDatabase or {}
    local defaultCharDB = addon.DefaultCharDatabase or {}

    addon.Database = addon:CopyTable(defaultDB)
    addon.CharDatabase = addon:CopyTable(defaultCharDB)
    _G["ReckoningDB"] = addon.Database
    _G["ReckoningCharDB"] = addon.CharDatabase

    local engine = Private.AchievementEngine
    if engine then
        engine.progressData = {}
        engine.criteriaProgress = {}
        engine.completedAchievements = {}
        engine.completedTimestamps = {}
        engine.failedState = {}
        engine.lastWeek = 0
        engine.dataLoaded = false
        engine:LoadProgress()
    end

    if Private.EventBridge then
        Private.EventBridge.exploredZones = addon.Database.exploredZones or {}
    end

    local guildSync = Private.GuildSyncUtils
    if guildSync then
        guildSync.memberData = {}
        guildSync.recentEvents = {}
        guildSync.pendingChunks = {}
        guildSync.lastResponseToRequester = {}
        guildSync:SaveCachedData()
    end

    addon:Print("Saved data cleared.")
end

-------------------------------------------------------------------------------
-- Utility Functions
-------------------------------------------------------------------------------

function commandUtils:CountTable(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end
