---@class AddonPrivate
local Private = select(2, ...)

local const = Private.constants
local addon = Private.Addon

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

end
