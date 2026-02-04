---@class AddonPrivate
local Private = select(2, ...)

local Enums = Private.Enums

-------------------------------------------------------------------------------
-- Achievement Engine
-- Handles trigger evaluation, condition matching, progress tracking,
-- fail conditions, and achievement completion.
-- Uses account-wide SavedVariables with encoding for persistence.
-------------------------------------------------------------------------------

---@class AchievementEngine
local engine = {
    ---@type table<number, number> -- Achievement ID -> current progress
    progressData = {},
    ---@type table<number, table> -- Achievement ID -> criteria progress
    criteriaProgress = {},
    ---@type table<number, boolean> -- Achievement ID -> completed state
    completedAchievements = {},
    ---@type table<number, number> -- Achievement ID -> completion timestamp
    completedTimestamps = {},
    ---@type table<number, boolean> -- Achievement ID -> failed state (for fail conditions)
    failedState = {},
    ---@type number -- Last saved week number
    lastWeek = 0,
    ---@type boolean -- Whether data has been loaded
    dataLoaded = false,
}
Private.AchievementEngine = engine

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function engine:Init()
    -- Load saved progress from database
    self:LoadProgress()

    -- Check for weekly reset
    self:CheckWeeklyReset()

    -- Initialize achievement links and guild broadcast listener
    self:InitAchievementLinks()

    -- Register for encounter start to reset fail states
    Private.EventBridge:RegisterEvent("DUNGEON_ENCOUNTER_START", function(payload)
        self:OnEncounterStart(payload)
    end)

    -- Register for logout to save data
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGOUT" then
            self:SaveProgress()
        end
    end)
end

-------------------------------------------------------------------------------
-- Data Persistence (Account-Wide)
-------------------------------------------------------------------------------

---Load progress from SavedVariables
function engine:LoadProgress()
    local dbUtils = Private.DatabaseUtils
    if not dbUtils then
        print("|cffff0000[Reckoning] LoadProgress: DatabaseUtils not found|r")
        return
    end

    local addon = Private.Addon
    if not addon then
        print("|cffff0000[Reckoning] LoadProgress: Addon not found|r")
        return
    end

    if not addon.Database then
        print("|cffff0000[Reckoning] LoadProgress: addon.Database not available yet|r")
        return
    end

    -- Try to load encoded data first (new format)
    local data, valid = dbUtils:LoadAchievementProgress()

    if data then
        self.progressData = data.progress or {}
        self.criteriaProgress = data.criteria or {}
        self.completedAchievements = data.completed or {}
        self.completedTimestamps = data.timestamps or {}
        self.lastWeek = data.lastWeek or 0

        if not valid then
            addon:Print("|cffff0000Warning: Achievement data verification failed. Progress may have been tampered with.|r")
        end

        local debugUtils = Private.DebugUtils
        if debugUtils and debugUtils.enabled then
            local completedCount = 0
            for _ in pairs(self.completedAchievements) do
                completedCount = completedCount + 1
            end
            debugUtils:Log("DATABASE", "Loaded %d completed achievements, lastWeek=%d", completedCount, self.lastWeek)
        end
    else
        -- No data or failed to load - initialize empty
        self.progressData = {}
        self.criteriaProgress = {}
        self.completedAchievements = {}
        self.completedTimestamps = {}
        self.lastWeek = 0
    end

    -- Sync with UI
    self:SyncUIFromLoadedData()

    self.dataLoaded = true
end

---Save progress to SavedVariables (called on logout)
function engine:SaveProgress()
    local dbUtils = Private.DatabaseUtils
    if not dbUtils then
        print("|cffff0000[Reckoning] SaveProgress: DatabaseUtils not found|r")
        return
    end

    local addon = Private.Addon
    if not addon then
        print("|cffff0000[Reckoning] SaveProgress: Addon not found|r")
        return
    end

    if not addon.Database then
        print("|cffff0000[Reckoning] SaveProgress: addon.Database not available|r")
        return
    end

    -- Prepare data for encoding
    local data = {
        progress = self.progressData,
        criteria = self.criteriaProgress,
        completed = self.completedAchievements,
        timestamps = self.completedTimestamps,
        lastWeek = dbUtils:GetCurrentWeek(),
        savedAt = time(),
    }

    -- Count what we're saving
    local completedCount = 0
    for _ in pairs(self.completedAchievements or {}) do
        completedCount = completedCount + 1
    end

    local debugUtils = Private.DebugUtils
    if debugUtils and debugUtils.enabled then
        debugUtils:Log("DATABASE", "Saving %d completed achievements", completedCount)
    end

    -- Encode and save
    local success = dbUtils:SaveAchievementProgress(data)

    if success then
        print("|cff00ff00[Reckoning] Achievement progress saved successfully!|r")
    end

    -- Also save explored zones from EventBridge
    if Private.EventBridge and Private.EventBridge.exploredZones then
        dbUtils:SaveExploredZones(Private.EventBridge.exploredZones)
    end
end

---Sync UI with loaded data
function engine:SyncUIFromLoadedData()
    local Data = Reckoning and Reckoning.Achievements
    if not Data then return end

    local aUtils = Private.AchievementUtils
    if not aUtils then return end

    -- Update all achievements in UI
    for id, achievement in pairs(aUtils.achievements) do
        local completed = self.completedAchievements[id]
        local progress = achievement.progress
        local total = progress and progress.required or 1
        local current
        if progress and progress.type == "criteria" then
            current = self:CountCompletedCriteria(self:GetCriteriaProgress(id))
        elseif progress and progress.type == "meta" and progress.subCategory then
            local ids = aUtils:GetAchievementIdsInSubCategory(progress.subCategory)
            current = 0
            for _, aid in ipairs(ids) do
                if aid ~= id and self.completedAchievements[aid] then
                    current = current + 1
                end
            end
        else
            current = self.progressData[id] or 0
        end

        if completed then
            Data:SetAchievementProgress(id, total, total, true)
        elseif current > 0 then
            Data:SetAchievementProgress(id, current, total, false)
        end
    end
end

-------------------------------------------------------------------------------
-- Weekly Reset
-------------------------------------------------------------------------------

---Check if a weekly reset has occurred
function engine:CheckWeeklyReset()
    local dbUtils = Private.DatabaseUtils
    if not dbUtils then return end

    local currentWeek = dbUtils:GetCurrentWeek()

    if self.lastWeek > 0 and currentWeek > self.lastWeek then
        -- Weekly reset occurred!
        self:OnWeeklyReset()
    end

    self.lastWeek = currentWeek
end

---Called on weekly reset to clear weekly achievement progress
function engine:OnWeeklyReset()
    local aUtils = Private.AchievementUtils
    if not aUtils then return end

    local addon = Private.Addon
    if addon then
        addon:Print("|cff00ff00Weekly reset detected! Resetting weekly achievements.|r")
    end

    for id, achievement in pairs(aUtils.achievements) do
        if achievement.cadence == Enums.Cadence.Weekly then
            -- Reset progress
            self.progressData[id] = 0
            self.criteriaProgress[id] = {}

            -- Unmark as completed
            self.completedAchievements[id] = nil
            self.completedTimestamps[id] = nil

            -- Update UI
            local total = achievement.progress and achievement.progress.required or 1
            self:UpdateUIProgress(id, 0, total)
        end
    end

    -- Fire the weekly reset bridge event
    Private.EventBridge:Fire("WEEKLY_RESET", {
        timestamp = time(),
        week = Private.DatabaseUtils:GetCurrentWeek(),
    })
end

-------------------------------------------------------------------------------
-- Event Handling
-------------------------------------------------------------------------------

---Called when a bridge event fires
---@param event string
---@param payload table
function engine:OnBridgeEvent(event, payload)
    if event == "BATTLEGROUND_MATCH_START" then
        self:ResetMatchProgress()
    end

    local aUtils = Private.AchievementUtils
    local debugUtils = Private.DebugUtils
    if not aUtils then return end

    -- Check fail conditions first
    local failAchievements = aUtils:GetAchievementsForFailEvent(event)
    for _, achievement in ipairs(failAchievements) do
        -- Skip if not available yet (startWeek)
        if not aUtils:IsAchievementAvailable(achievement) then
            -- Skip unavailable achievements
        elseif self:CheckConditions(achievement.failCondition.conditions, payload) then
            self:MarkFailed(achievement.id)
            if debugUtils then
                debugUtils:Log("TRIGGERS", "Achievement [%d] %s marked as FAILED", achievement.id, achievement.name)
            end
        end
    end

    -- Check trigger conditions
    local achievements = aUtils:GetAchievementsForEvent(event)
    for _, achievement in ipairs(achievements) do
        -- Skip if not available yet (startWeek)
        if not aUtils:IsAchievementAvailable(achievement) then
            if debugUtils then
                debugUtils:LogSkipped(achievement.id, "not available yet (startWeek)")
            end
        elseif self:IsCompleted(achievement.id) then
            if debugUtils then
                debugUtils:LogSkipped(achievement.id, "already completed")
            end
        elseif self:IsFailed(achievement.id) then
            if debugUtils then
                debugUtils:LogSkipped(achievement.id, "failed this attempt")
            end
        else
            if debugUtils then
                debugUtils:LogTriggerEval(achievement, event)
            end
            self:EvaluateAchievement(achievement, payload, event)
        end
    end
end

---Reset progress for achievements that require a single match
function engine:ResetMatchProgress()
    local aUtils = Private.AchievementUtils
    if not aUtils then return end

    for id, achievement in pairs(aUtils.achievements) do
        local progress = achievement.progress
        if progress and progress.reset == "match" then
            if not self.completedAchievements[id] then
                self.progressData[id] = 0
                self.criteriaProgress[id] = {}
                self.failedState[id] = nil

                local total = progress.required or 1
                self:UpdateUIProgress(id, 0, total)
            end
        end
    end
end

---Called when an encounter starts
---@param payload table
function engine:OnEncounterStart(payload)
    -- Reset fail states for all achievements that track encounter-based mechanics
    local aUtils = Private.AchievementUtils
    if not aUtils then return end

    for id, achievement in pairs(aUtils.achievements) do
        if achievement.failCondition then
            self.failedState[id] = false
        end
    end
end

-------------------------------------------------------------------------------
-- Achievement Evaluation
-------------------------------------------------------------------------------

---Evaluate if an achievement should progress or complete
---@param achievement Achievement
---@param payload table
---@param event string Bridge event name (for criteria key resolution)
function engine:EvaluateAchievement(achievement, payload, event)
    local trigger = achievement.trigger

    -- Check if we have a criteriaSet (multiple conditions to fulfill)
    if trigger.criteriaSet then
        self:EvaluateCriteriaSet(achievement, payload)
        return
    end

    -- Single condition check
    if trigger.conditions then
        if not self:CheckConditions(trigger.conditions, payload) then
            return -- Conditions not met
        end
    end

    -- Meta achievements: progress = count of completed in subCategory
    local progress = achievement.progress
    if progress and progress.type == "meta" then
        self:UpdateMetaProgress(achievement)
        return
    end

    -- Conditions met! Update progress
    self:UpdateProgress(achievement, payload, event or trigger.event)
end

---Evaluate a criteriaSet (multiple independent conditions)
---@param achievement Achievement
---@param payload table
function engine:EvaluateCriteriaSet(achievement, payload)
    local criteriaSet = achievement.trigger.criteriaSet
    local criteriaProgress = self:GetCriteriaProgress(achievement.id)

    for i, criteria in ipairs(criteriaSet) do
        if not criteriaProgress[i] then
            -- Check if this criteria matches
            if self:CheckConditions(criteria, payload) then
                criteriaProgress[i] = true
                self:SaveCriteriaProgress(achievement.id, criteriaProgress)
            end
        end
    end

    -- Check if all criteria met
    local allMet = true
    for i = 1, #criteriaSet do
        if not criteriaProgress[i] then
            allMet = false
            break
        end
    end

    if allMet then
        self:CompleteAchievement(achievement)
    else
        -- Update UI with partial progress
        self:UpdateUIProgress(achievement.id, self:CountCompletedCriteria(criteriaProgress), #criteriaSet)
    end
end

---Normalize condition expected value when config uses string (e.g. "Exalted") and payload uses enum number
---Returns enum value for known keys, or nil to fall back to direct comparison
---@param key string
---@param expected string|number
---@return number|nil
function engine:NormalizeExpectedForCondition(key, expected)
    if type(expected) ~= "string" then return nil end

    local Enums = Private.Enums
    if not Enums then return nil end

    if key == "standing" then
        local map = {
            Hated = Enums.Standing.Hated,
            Hostile = Enums.Standing.Hostile,
            Unfriendly = Enums.Standing.Unfriendly,
            Neutral = Enums.Standing.Neutral,
            Friendly = Enums.Standing.Friendly,
            Honored = Enums.Standing.Honored,
            Revered = Enums.Standing.Revered,
            Exalted = Enums.Standing.Exalted,
        }
        return map[expected]
    end

    if key == "rollType" then
        local map = { need = Enums.RollType.Need, greed = Enums.RollType.Greed, disenchant = Enums.RollType.Disenchant }
        return map[expected and expected:lower()]
    end

    if key == "objectiveType" then
        local map = {
            flag = Enums.ObjectiveType.Flag,
            base = Enums.ObjectiveType.Base,
            tower = Enums.ObjectiveType.Tower,
            flag_return = Enums.ObjectiveType.Flag,
            tower_defense = Enums.ObjectiveType.Tower,
        }
        return map[expected and expected:lower()]
    end

    -- targetType and other string keys: no enum mapping, use direct comparison
    return nil
end

---Check if all conditions match the payload
---Accepts both string and enum in config for standing, rollType, objectiveType (normalized in engine)
---@param conditions table
---@param payload table
---@return boolean
function engine:CheckConditions(conditions, payload)
    if not conditions then return true end

    local debugUtils = Private.DebugUtils

    for key, expected in pairs(conditions) do
        local actual = payload[key]

        if type(expected) == "function" then
            -- Function condition: call with actual value
            if not expected(actual) then
                if debugUtils then
                    debugUtils:LogCondition(key, "<function>", tostring(actual), false)
                end
                return false
            end
            if debugUtils then
                debugUtils:LogCondition(key, "<function>", tostring(actual), true)
            end
        elseif type(expected) == "table" then
            -- Table condition: check if actual is in the table
            local found = false
            for _, v in ipairs(expected) do
                if v == actual then
                    found = true
                    break
                end
            end
            if not found then
                if debugUtils then
                    debugUtils:LogCondition(key, "{list}", tostring(actual), false)
                end
                return false
            end
            if debugUtils then
                debugUtils:LogCondition(key, "{list}", tostring(actual), true)
            end
        else
            -- Direct comparison; normalize string expected to enum for known keys
            local compareExpected = self:NormalizeExpectedForCondition(key, expected)
            if compareExpected == nil then
                compareExpected = expected
            end
            if actual ~= compareExpected then
                if debugUtils then
                    debugUtils:LogCondition(key, tostring(expected), tostring(actual), false)
                end
                return false
            end
            if debugUtils then
                debugUtils:LogCondition(key, tostring(expected), tostring(actual), true)
            end
        end
    end

    return true
end

-------------------------------------------------------------------------------
-- Progress Tracking
-------------------------------------------------------------------------------

---Resolve the criteria key for progress.type == "criteria" (unique-count achievements)
---Uses progress.criteriaKey if set, otherwise event-based default.
---@param achievement Achievement
---@param payload table
---@param event string
---@return string|nil key Unique key for this criteria slot, or nil if not determinable
function engine:GetCriteriaKey(achievement, payload, event)
    local progress = achievement.progress
    if not progress or progress.type ~= "criteria" then return nil end

    local keyName = progress.criteriaKey
    if keyName and payload[keyName] ~= nil then
        return tostring(payload[keyName])
    end

    -- Event-based default payload field for unique criteria
    local defaultKeyByEvent = {
        DUNGEON_CLEARED = "instance",
        DUNGEON_BOSS_KILLED = "bossName",
        ZONE_EXPLORED = "zone",
        PVP_OBJECTIVE_CAPTURED = "objectiveName",
        PVP_KILLING_BLOW = "victimClass",
        BATTLEGROUND_MATCH_END = "battleground",
        QUEST_COMPLETED = "questId",
    }
    keyName = defaultKeyByEvent[event]
    if keyName and payload[keyName] ~= nil then
        return tostring(payload[keyName])
    end

    return nil
end

---Update progress for an achievement
---@param achievement Achievement
---@param payload table
---@param event string Bridge event name (for criteria key resolution)
function engine:UpdateProgress(achievement, payload, event)
    local progress = achievement.progress
    local debugUtils = Private.DebugUtils

    if not progress then
        -- No progress tracking, complete immediately
        if debugUtils then
            debugUtils:Log("PROGRESS", "[%d] %s: No progress needed, completing", achievement.id, achievement.name)
        end
        self:CompleteAchievement(achievement)
        return
    end

    if progress.type == "count" then
        local current = self:GetProgress(achievement.id)
        current = current + 1
        self:SetAchievementProgress(achievement.id, current)

        if debugUtils then
            debugUtils:LogProgress(achievement.id, achievement.name, current, progress.required)
        end

        if current >= progress.required then
            self:CompleteAchievement(achievement)
        else
            self:UpdateUIProgress(achievement.id, current, progress.required)
        end
        return
    end

    if progress.type == "criteria" then
        local key = self:GetCriteriaKey(achievement, payload, event or achievement.trigger.event)
        if not key or key == "" then
            if debugUtils then
                debugUtils:Log("PROGRESS", "[%d] %s: criteria key missing from payload", achievement.id, achievement.name)
            end
            return
        end

        local crit = self:GetCriteriaProgress(achievement.id)
        if crit[key] then
            if debugUtils then
                debugUtils:Log("PROGRESS", "[%d] %s: criteria already counted for key %s", achievement.id, achievement.name, key)
            end
            return
        end

        crit[key] = true
        self:SaveCriteriaProgress(achievement.id, crit)
        local n = self:CountCompletedCriteria(crit)
        local required = progress.required or 1

        if debugUtils then
            debugUtils:LogProgress(achievement.id, achievement.name, n, required)
        end

        if n >= required then
            self:CompleteAchievement(achievement)
        else
            self:UpdateUIProgress(achievement.id, n, required)
        end
    end
end

---Update progress for meta achievements (count of completed achievements in subCategory)
---@param achievement Achievement with progress.type == "meta"
function engine:UpdateMetaProgress(achievement)
    local progress = achievement.progress
    if not progress or progress.type ~= "meta" or not progress.subCategory then return end
    if self.completedAchievements[achievement.id] then return end

    local aUtils = Private.AchievementUtils
    if not aUtils then return end
    local ids = aUtils:GetAchievementIdsInSubCategory(progress.subCategory)
    local count = 0
    for _, id in ipairs(ids) do
        if id ~= achievement.id and self.completedAchievements[id] then
            count = count + 1
        end
    end

    local required = progress.required or 1
    self:SetAchievementProgress(achievement.id, count)

    local debugUtils = Private.DebugUtils
    if debugUtils then
        debugUtils:LogProgress(achievement.id, achievement.name, count, required)
    end

    if count >= required then
        self:CompleteAchievement(achievement)
    else
        self:UpdateUIProgress(achievement.id, count, required)
    end
end

---Get current progress for an achievement
---@param achievementId number
---@return number
function engine:GetProgress(achievementId)
    local progress = self.progressData[achievementId]
    if type(progress) == "number" then
        return progress
    end
    return 0
end

---Save progress for a single achievement (in memory)
---@param achievementId number
---@param progress number
function engine:SetAchievementProgress(achievementId, progress)
    self.progressData[achievementId] = progress
end

---Get criteria progress for an achievement
---@param achievementId number
---@return table
function engine:GetCriteriaProgress(achievementId)
    return self.criteriaProgress[achievementId] or {}
end

---Save criteria progress for an achievement
---@param achievementId number
---@param progress table
function engine:SaveCriteriaProgress(achievementId, progress)
    self.criteriaProgress[achievementId] = progress
end

---Count completed criteria
---@param criteriaProgress table
---@return number
function engine:CountCompletedCriteria(criteriaProgress)
    local count = 0
    for _, completed in pairs(criteriaProgress) do
        if completed then count = count + 1 end
    end
    return count
end

-------------------------------------------------------------------------------
-- Fail Condition Handling
-------------------------------------------------------------------------------

---Mark an achievement as failed for this attempt
---@param achievementId number
function engine:MarkFailed(achievementId)
    self.failedState[achievementId] = true
end

---Check if an achievement is failed for this attempt
---@param achievementId number
---@return boolean
function engine:IsFailed(achievementId)
    return self.failedState[achievementId] or false
end

-------------------------------------------------------------------------------
-- Completion Handling
-------------------------------------------------------------------------------

---Check if an achievement is already completed
---@param achievementId number
---@return boolean
function engine:IsCompleted(achievementId)
    return self.completedAchievements[achievementId] == true
end

---Get the completion timestamp for an achievement
---@param achievementId number
---@return number|nil timestamp Unix timestamp of completion, or nil if not completed
function engine:GetCompletionTimestamp(achievementId)
    return self.completedTimestamps[achievementId]
end

---Get completion info for an achievement (completed status + timestamp)
---@param achievementId number
---@return boolean completed, number|nil timestamp
function engine:GetCompletionInfo(achievementId)
    local completed = self.completedAchievements[achievementId] == true
    local timestamp = self.completedTimestamps[achievementId]
    return completed, timestamp
end

---Get all completed achievements with their timestamps
---@return table<number, number> achievementId -> timestamp
function engine:GetAllCompletedWithTimestamps()
    local results = {}
    for id, completed in pairs(self.completedAchievements) do
        if completed then
            results[id] = self.completedTimestamps[id] or 0
        end
    end
    return results
end

---Complete an achievement
---@param achievement Achievement
function engine:CompleteAchievement(achievement)
    local achievementId = achievement.id
    local debugUtils = Private.DebugUtils

    -- Debug log completion
    if debugUtils then
        debugUtils:LogCompletion(achievement)
    end

    -- Mark as completed
    self.completedAchievements[achievementId] = true
    self.completedTimestamps[achievementId] = time()

    -- Update UI
    self:UpdateUICompleted(achievementId)

    -- Show alert
    self:ShowAchievementAlert(achievement)

    -- Fire callback for other systems
    local callbacks = Private.CallbackUtils:GetCallbacks("AchievementCompleted")
    for _, cb in ipairs(callbacks) do
        cb:Trigger(achievementId, achievement)
    end

    -- Fire bridge event for meta achievements (e.g. Karazhan Champion)
    local eventBridge = Private.EventBridge
    if eventBridge and achievement.subCategory then
        eventBridge:Fire("ACHIEVEMENT_COMPLETED", {
            achievementId = achievementId,
            category = achievement.category,
            subCategory = achievement.subCategory,
        })
    end

    -- Print achievement link to chat
    self:PrintAchievementEarned(achievement)

    -- Send to guild chat
    self:SendAchievementToGuildChat(achievement)

    -- Broadcast to guild
    self:BroadcastAchievementToGuild(achievement)
end

-------------------------------------------------------------------------------
-- Achievement Chat Links & Announcements
-------------------------------------------------------------------------------

---Generate a clickable achievement link (styled like Blizzard achievement links)
---@param achievement Achievement
---@param playerName string|nil
---@return string link
function engine:CreateAchievementLink(achievement, playerName)
    -- Create a custom hyperlink that looks like Blizzard's achievement links
    -- Format: |cffffff00|Hreckoning:id:points:name|h[name]|h|r
    -- Using yellow color (cffffff00) like real achievements
    local safeName = achievement.name:gsub("|", "||") -- Escape any pipe characters
    local link = string.format(
        "|cffffff00|Hreckoning:%d:%d|h[%s]|h|r",
        achievement.id,
        achievement.points or 0,
        achievement.name
    )
    return link
end

---Print achievement earned message to player's chat
---@param achievement Achievement
function engine:PrintAchievementEarned(achievement)
    local const = Private.constants

    -- Check if personal messages are enabled
    if const and const.ANNOUNCEMENTS and const.ANNOUNCEMENTS.SHOW_PERSONAL_MESSAGE == false then
        return
    end

    local pointsName = const and const.DISPLAY and const.DISPLAY.POINTS_NAME or "Points"
    local link = self:CreateAchievementLink(achievement)

    -- Print to default chat frame with achievement link
    local message = string.format(
        "|cffFFD700Reckoning:|r You have earned the achievement %s for |cffffffff%d|r %s!",
        link,
        achievement.points or 0,
        pointsName
    )

    -- Use DEFAULT_CHAT_FRAME to show to the player
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    else
        -- Fallback to print if DEFAULT_CHAT_FRAME isn't available
        print(message)
    end
end

---Send achievement earned message to guild chat
---@param achievement Achievement
function engine:SendAchievementToGuildChat(achievement)
    local const = Private.constants

    if const and const.ANNOUNCEMENTS and const.ANNOUNCEMENTS.SEND_GUILD_CHAT == false then
        return
    end

    if type(SendChatMessage) ~= "function" or not IsInGuild() then
        return
    end

    local playerName = UnitName and UnitName("player") or "Player"
    local pointsName = const and const.DISPLAY and const.DISPLAY.POINTS_NAME or "Points"
    local link = self:CreateAchievementLink(achievement)
    local message = string.format(
        "Reckoning: %s earned %s for %d %s!",
        playerName,
        link,
        achievement.points or 0,
        pointsName
    )

    SendChatMessage(message, "GUILD")
end

---Broadcast achievement completion to guild members
---@param achievement Achievement
function engine:BroadcastAchievementToGuild(achievement)
    local const = Private.constants

    -- Check if guild broadcasts are enabled
    if const and const.ANNOUNCEMENTS and const.ANNOUNCEMENTS.BROADCAST_TO_GUILD == false then
        return
    end

    local commsUtils = Private.CommsUtils
    if not commsUtils then return end

    -- Only broadcast if player is in a guild
    if not IsInGuild() then return end

    -- Get player info
    local playerName = UnitName("player")
    local playerClass = select(2, UnitClass("player"))

    -- Send the achievement data to guild
    commsUtils:SendMessage("ACHIEVEMENT_EARNED", {
        achievementId = achievement.id,
        achievementName = achievement.name,
        achievementPoints = achievement.points or 0,
        achievementIcon = achievement.icon,
        playerName = playerName,
        playerClass = playerClass,
        timestamp = time(),
    }, "GUILD")
end

---Handle incoming achievement broadcast from guild member
---@param data table
function engine:OnGuildAchievementReceived(data)
    if not data then return end

    local const = Private.constants

    -- Check if showing guild messages is enabled
    if const and const.ANNOUNCEMENTS and const.ANNOUNCEMENTS.SHOW_GUILD_MESSAGES == false then
        return
    end

    local pointsName = const and const.DISPLAY and const.DISPLAY.POINTS_NAME or "Points"

    -- Don't show our own achievements (we already announced it)
    local myName = UnitName("player")
    if data.playerName == myName then return end

    -- Create achievement link
    local link = string.format(
        "|cffFFD700|Hreckoning:%d:%d|h[%s]|h|r",
        data.achievementId,
        data.achievementPoints or 0,
        data.achievementName
    )

    -- Get class color for player name
    local classColor = RAID_CLASS_COLORS[data.playerClass] or { r = 1, g = 1, b = 1 }
    local coloredName = string.format("|cff%02x%02x%02x%s|r",
        classColor.r * 255,
        classColor.g * 255,
        classColor.b * 255,
        data.playerName
    )

    -- Print to chat
    local message = string.format(
        "|cffFFD700Reckoning:|r %s has earned the achievement %s!",
        coloredName,
        link
    )

    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    end
end

---Initialize achievement link click handler and guild broadcast listener
function engine:InitAchievementLinks()
    -- Register for guild achievement broadcasts
    local commsUtils = Private.CommsUtils
    if commsUtils then
        commsUtils:AddCallback("ACHIEVEMENT_EARNED", function(data)
            self:OnGuildAchievementReceived(data)
        end)
    end

    -- Hook SetItemRef to intercept our custom links BEFORE Blizzard processes them
    local originalSetItemRef = SetItemRef
    SetItemRef = function(link, text, button, chatFrame)
        local linkType = strsplit(":", link)
        if linkType == "reckoning" then
            -- Handle our custom reckoning achievement links
            local _, achievementId, points = strsplit(":", link)
            achievementId = tonumber(achievementId)
            if achievementId then
                engine:ShowAchievementDetails(achievementId)
            end
            -- Don't call original - prevents the error
            return
        end
        -- For all other links, call the original handler
        return originalSetItemRef(link, text, button, chatFrame)
    end

    -- Set up hyperlink tooltip handler
    local tooltipHandler = function(self, link, text)
        local linkType, achievementId, points = strsplit(":", link)
        if linkType == "reckoning" then
            achievementId = tonumber(achievementId)
            points = tonumber(points) or 0
            if achievementId then
                local aUtils = Private.AchievementUtils
                local achievement = aUtils and aUtils:GetAchievement(achievementId)

                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                if achievement then
                    GameTooltip:AddLine(achievement.name, 1, 0.82, 0)
                    if achievement.description then
                        GameTooltip:AddLine(achievement.description, 1, 1, 1, true)
                    end
                    local const = Private.constants
                    local pointsName = const and const.DISPLAY and const.DISPLAY.POINTS_NAME or "Points"
                    GameTooltip:AddLine(pointsName .. ": " .. points, 0.7, 0.7, 0.7)

                    -- Show completion status
                    if engine.completedAchievements[achievementId] then
                        GameTooltip:AddLine("Completed", 0, 1, 0)
                    else
                        GameTooltip:AddLine("Not Completed", 1, 0, 0)
                    end
                else
                    GameTooltip:AddLine("Achievement #" .. achievementId, 1, 0.82, 0)
                    local const = Private.constants
                    local pointsName = const and const.DISPLAY and const.DISPLAY.POINTS_NAME or "Points"
                    GameTooltip:AddLine(pointsName .. ": " .. points, 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            end
        end
    end

    -- Hook chat frame hyperlink handlers for tooltips
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame then
            chatFrame:HookScript("OnHyperlinkEnter", tooltipHandler)
            chatFrame:HookScript("OnHyperlinkLeave", function()
                GameTooltip:Hide()
            end)
        end
    end
end

---Show achievement details when clicking a link
---@param achievementId number
function engine:ShowAchievementDetails(achievementId)
    local aUtils = Private.AchievementUtils
    local achievement = aUtils and aUtils:GetAchievement(achievementId)

    if not achievement then
        Private.Addon:Print("Achievement not found: " .. achievementId)
        return
    end

    -- Open the achievement frame
    if ReckoningAchievementFrame then
        ReckoningAchievementFrame:Show()

        -- Use the global function to select and scroll to the achievement
        if ReckoningAchievementFrame_SelectAchievement then
            ReckoningAchievementFrame_SelectAchievement(achievementId)
        end
    end
end

-------------------------------------------------------------------------------
-- UI Updates
-------------------------------------------------------------------------------

---Update UI with progress
---@param achievementId number
---@param current number
---@param total number
function engine:UpdateUIProgress(achievementId, current, total)
    local Data = Reckoning and Reckoning.Achievements
    if Data and Data.SetAchievementProgress then
        Data:SetAchievementProgress(achievementId, current, total, false)
    end

    -- Refresh the achievement frame if open
    if ReckoningAchievementFrame_Refresh then
        ReckoningAchievementFrame_Refresh()
    end
end

---Update UI when completed
---@param achievementId number
function engine:UpdateUICompleted(achievementId)
    local Data = Reckoning and Reckoning.Achievements
    if Data and Data.SetAchievementProgress then
        local achievement = Private.AchievementUtils:GetAchievement(achievementId)
        local total = achievement and achievement.progress and achievement.progress.required or 1
        Data:SetAchievementProgress(achievementId, total, total, true)
    end

    -- Refresh the achievement frame if open
    if ReckoningAchievementFrame_Refresh then
        ReckoningAchievementFrame_Refresh()
    end
end

---Show achievement alert toast
---@param achievement Achievement
function engine:ShowAchievementAlert(achievement)
    -- Use the existing alert system
    if ReckoningAchievementAlert_Show then
        ReckoningAchievementAlert_Show(achievement.id)
    end
end

-------------------------------------------------------------------------------
-- Debug Commands
-------------------------------------------------------------------------------

---Force complete an achievement (debug)
---@param achievementId number
function engine:DebugComplete(achievementId)
    local aUtils = Private.AchievementUtils
    local achievement = aUtils:GetAchievement(achievementId)

    if achievement then
        self:CompleteAchievement(achievement)
    else
        Private.Addon:Print("Achievement not found: " .. achievementId)
    end
end

---Reset an achievement (debug)
---@param achievementId number
function engine:DebugReset(achievementId)
    self.progressData[achievementId] = 0
    self.criteriaProgress[achievementId] = {}
    self.completedAchievements[achievementId] = nil
    self.completedTimestamps[achievementId] = nil
    self.failedState[achievementId] = nil

    local aUtils = Private.AchievementUtils
    local achievement = aUtils:GetAchievement(achievementId)
    if achievement then
        local total = achievement.progress and achievement.progress.required or 1
        self:UpdateUIProgress(achievementId, 0, total)
    end

    Private.Addon:Print("Achievement reset: " .. achievementId)
end

---Print current progress (debug)
---@param achievementId number
function engine:DebugProgress(achievementId)
    local current = self.progressData[achievementId] or 0
    local completed = self.completedAchievements[achievementId]
    local criteria = self.criteriaProgress[achievementId]

    Private.Addon:Print(string.format("Achievement %d: progress=%d, completed=%s",
        achievementId, current, tostring(completed)))

    if criteria then
        Private.Addon:Print("Criteria: " .. table.concat(criteria, ", "))
    end
end
