---@class AddonPrivate
local Private = select(2, ...)

--[[
    DEBUG COMMANDS MODULE

    This file contains all debug/testing commands for development purposes.

    TO ENABLE DEBUG COMMANDS:
    1. Add this line to utils.xml BEFORE CommandUtils.lua:
       <script file="DebugCommands.lua" />

    OR add to Reckoning.toc if you want it loaded separately.

    IMPORTANT: Do NOT include this file in release builds!
    Regular players should not have access to these commands.
]]

---@class DebugCommands
local debugCommands = {}
Private.DebugCommands = debugCommands

-- Flag to check if debug commands are loaded
debugCommands.isLoaded = true

-------------------------------------------------------------------------------
-- Debug Command Registration
-------------------------------------------------------------------------------

function debugCommands:GetCommands()
    return {
        -- Debug utilities
        ["debug"] = self.OnDebugCommand,
        ["fire"] = self.OnFireEventCommand,
        ["week"] = self.OnSetWeekCommand,
        ["reset"] = self.OnResetProgressCommand,
        ["inspect"] = self.OnInspectCommand,

        -- Achievement manipulation
        ["complete"] = self.OnCompleteCommand,
        ["alert"] = self.OnAlertCommand,
        ["progress"] = self.OnProgressCommand,
        ["list"] = self.OnListCommand,
        ["test"] = self.OnTestCommand,

        -- Database testing
        ["save"] = self.OnSaveCommand,
        ["load"] = self.OnLoadCommand,
        ["dbtest"] = self.OnDbTestCommand,
    }
end

-------------------------------------------------------------------------------
-- Debug Commands
-------------------------------------------------------------------------------

function debugCommands:OnDebugCommand(args)
    local addon = Private.Addon
    local debugUtils = Private.DebugUtils

    -- Handle subcommands
    if args and #args > 0 then
        local subcmd = string.lower(args[1])

        if subcmd == "on" or subcmd == "enable" then
            debugUtils:Enable()
            return
        elseif subcmd == "off" or subcmd == "disable" then
            debugUtils:Disable()
            return
        elseif subcmd == "toggle" then
            debugUtils:Toggle()
            return
        elseif subcmd == "verbose" or subcmd == "v" then
            debugUtils:ToggleVerbose()
            return
        elseif subcmd == "filter" or subcmd == "f" then
            if args[2] then
                debugUtils:ToggleFilter(args[2])
            else
                debugUtils:PrintFilters()
            end
            return
        elseif subcmd == "status" or subcmd == "s" then
            debugUtils:PrintStatus()
            return
        elseif subcmd == "history" or subcmd == "h" then
            local count = args[2] and tonumber(args[2]) or 20
            debugUtils:PrintHistory(count)
            return
        elseif subcmd == "clear" then
            debugUtils:ClearHistory()
            return
        elseif subcmd == "help" or subcmd == "?" then
            self:PrintDebugHelp()
            return
        elseif subcmd == "info" then
            self:PrintBasicDebugInfo()
            return
        end
    end

    -- No args or unknown - toggle debug mode
    debugUtils:Toggle()
end

function debugCommands:PrintDebugHelp()
    local addon = Private.Addon
    addon:Print("|cffff6600=== DEBUG MODE ENABLED ===|r")
    addon:Print("|cffff6600WARNING: These commands are for development only!|r")
    addon:Print("")
    addon:Print("=== Debug Commands ===")
    addon:Print("|cffffffff/r debug|r - Toggle debug mode")
    addon:Print("|cffffffff/r debug on/off|r - Enable/disable debug")
    addon:Print("|cffffffff/r debug verbose|r - Toggle verbose logging")
    addon:Print("|cffffffff/r debug filter <category>|r - Toggle filter")
    addon:Print("|cffffffff/r debug status|r - Show debug status")
    addon:Print("|cffffffff/r debug history [count]|r - Show log history")
    addon:Print("|cffffffff/r debug clear|r - Clear log history")
    addon:Print("|cffffffff/r debug info|r - Show basic addon info")
    addon:Print("")
    addon:Print("=== Testing Commands ===")
    addon:Print("|cffffffff/r complete <id>|r - Force complete achievement")
    addon:Print("|cffffffff/r alert <id>|r - Show achievement alert")
    addon:Print("|cffffffff/r progress <id> [value]|r - View/set progress")
    addon:Print("|cffffffff/r list [filter]|r - List achievements")
    addon:Print("|cffffffff/r test|r - Run test scenarios")
    addon:Print("|cffffffff/r inspect <id>|r - Inspect achievement")
    addon:Print("|cffffffff/r fire <event> [args]|r - Fire test event")
    addon:Print("|cffffffff/r week [num]|r - Get/set current week")
    addon:Print("|cffffffff/r reset|r - Reset all progress")
    addon:Print("")
    addon:Print("=== Database Commands ===")
    addon:Print("|cffffffff/r save|r - Force save progress now")
    addon:Print("|cffffffff/r load|r - Force reload progress")
    addon:Print("|cffffffff/r dbtest|r - Test database encoding/decoding")
    addon:Print("")
    addon:Print("Filter categories: EVENTS, TRIGGERS, CONDITIONS, PROGRESS, COMPLETION, WEEKLY, DATABASE, UI")
end

function debugCommands:PrintBasicDebugInfo()
    local addon = Private.Addon
    local aUtils = Private.AchievementUtils
    local engine = Private.AchievementEngine
    local dbUtils = Private.DatabaseUtils

    addon:Print("=== Reckoning Debug Info ===")
    addon:Print("Current Week: " .. (dbUtils and dbUtils:GetCurrentWeek() or "N/A"))
    addon:Print("UI Week: " .. (aUtils and aUtils:GetCurrentWeek() or "N/A"))
    addon:Print("Registered Categories: " .. self:CountTable(aUtils and aUtils.categories or {}))
    addon:Print("Registered Achievements: " .. self:CountTable(aUtils and aUtils.achievements or {}))
    addon:Print("Events with triggers: " .. self:CountTable(aUtils and aUtils.achievementsByEvent or {}))

    -- Show completed achievements
    local completed = 0
    if engine and engine.completedAchievements then
        for _ in pairs(engine.completedAchievements) do
            completed = completed + 1
        end
    end
    addon:Print("Completed Achievements: " .. completed)

    -- Debug mode status
    local debugUtils = Private.DebugUtils
    if debugUtils then
        addon:Print("Debug Mode: " .. (debugUtils.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    end
end

function debugCommands:OnInspectCommand(args)
    if not args or #args == 0 then
        Private.Addon:Print("Usage: /r inspect <achievement_id>")
        Private.Addon:Print("Example: /r inspect 1001")
        return
    end

    local achievementId = tonumber(args[1])
    if achievementId then
        Private.DebugUtils:InspectAchievement(achievementId)
    else
        Private.Addon:Print("Invalid achievement ID")
    end
end

function debugCommands:OnFireEventCommand(args)
    if not args or #args == 0 then
        Private.Addon:Print("Usage: /r fire <event> [key=value ...]")
        Private.Addon:Print("Example: /r fire DUNGEON_BOSS_KILLED bossName=Murmur")
        return
    end

    local eventName = args[1]
    local payload = {}

    -- Parse key=value pairs
    for i = 2, #args do
        local key, value = strsplit("=", args[i])
        if key and value then
            -- Try to convert to number
            local numValue = tonumber(value)
            payload[key] = numValue or value
        end
    end

    Private.Addon:Print("Firing event: " .. eventName)
    Private.EventBridge:Fire(eventName, payload)
end

function debugCommands:OnSetWeekCommand(args)
    if not args or #args == 0 then
        Private.Addon:Print("Current week: " .. Private.AchievementUtils:GetCurrentWeek())
        Private.Addon:Print("Usage: /r week <number>")
        return
    end

    local week = tonumber(args[1])
    if week then
        Private.AchievementUtils:SetCurrentWeek(week)
        Private.Addon.CharDatabase.currentWeek = week
        Private.Addon:Print("Set current week to: " .. week)
    else
        Private.Addon:Print("Invalid week number")
    end
end

function debugCommands:OnResetProgressCommand(args)
    local addon = Private.Addon

    if addon.CharDatabase then
        addon.CharDatabase.achievementProgress = {}
        addon.CharDatabase.criteriaProgress = {}
        addon.CharDatabase.completedAchievements = {}
        addon.CharDatabase.completedTimestamps = {}

        Private.AchievementEngine.progressData = {}
        Private.AchievementEngine.criteriaProgress = {}

        addon:Print("|cffff0000All achievement progress has been reset!|r")
    end
end

function debugCommands:CountTable(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-------------------------------------------------------------------------------
-- Testing Commands
-------------------------------------------------------------------------------

---Force complete an achievement for testing
function debugCommands:OnCompleteCommand(args)
    local addon = Private.Addon
    local engine = Private.AchievementEngine

    if not args or #args == 0 then
        addon:Print("Usage: /r complete <achievement_id>")
        addon:Print("       /r complete all - Complete all achievements")
        addon:Print("Example: /r complete 1001")
        return
    end

    if args[1] == "all" then
        local aUtils = Private.AchievementUtils
        local count = 0
        for id, achievement in pairs(aUtils.achievements) do
            if not engine:IsCompleted(id) then
                engine:DebugComplete(id)
                count = count + 1
            end
        end
        addon:Print("Completed " .. count .. " achievements!")
        return
    end

    local achievementId = tonumber(args[1])
    if achievementId then
        engine:DebugComplete(achievementId)
        addon:Print("Force completed achievement: " .. achievementId)
    else
        addon:Print("Invalid achievement ID")
    end
end

---Show a test alert for any achievement
function debugCommands:OnAlertCommand(args)
    local addon = Private.Addon

    if not args or #args == 0 then
        addon:Print("Usage: /r alert <achievement_id>")
        addon:Print("       /r alert test - Show a test alert")
        addon:Print("Example: /r alert 1001")
        return
    end

    if args[1] == "test" then
        -- Show alert for first available achievement
        local aUtils = Private.AchievementUtils
        for id, _ in pairs(aUtils.achievements) do
            if ReckoningAchievementAlert_Show then
                ReckoningAchievementAlert_Show(id)
                addon:Print("Showing test alert for achievement: " .. id)
            end
            return
        end
        addon:Print("No achievements found to show alert for")
        return
    end

    local achievementId = tonumber(args[1])
    if achievementId then
        if ReckoningAchievementAlert_Show then
            ReckoningAchievementAlert_Show(achievementId)
            addon:Print("Showing alert for achievement: " .. achievementId)
        else
            addon:Print("Alert system not available")
        end
    else
        addon:Print("Invalid achievement ID")
    end
end

---Set or view progress for an achievement
function debugCommands:OnProgressCommand(args)
    local addon = Private.Addon
    local engine = Private.AchievementEngine
    local aUtils = Private.AchievementUtils

    if not args or #args == 0 then
        addon:Print("Usage: /r progress <achievement_id> [value]")
        addon:Print("       /r progress <id> - View current progress")
        addon:Print("       /r progress <id> 5 - Set progress to 5")
        addon:Print("       /r progress <id> +1 - Add 1 to progress")
        addon:Print("       /r progress <id> max - Set to required and auto-complete")
        return
    end

    local achievementId = tonumber(args[1])
    if not achievementId then
        addon:Print("Invalid achievement ID")
        return
    end

    local achievement = aUtils:GetAchievement(achievementId)
    if not achievement then
        addon:Print("Achievement not found: " .. achievementId)
        return
    end

    -- If no value provided, just show current progress
    if not args[2] then
        engine:DebugProgress(achievementId)
        return
    end

    -- Set or add progress
    local valueStr = args[2]
    local currentProgress = engine.progressData[achievementId] or 0
    local total = achievement.progress and achievement.progress.required or 1
    local newProgress
    local autoComplete = false

    if valueStr == "max" or valueStr == "full" then
        -- Set to max and trigger completion
        newProgress = total
        autoComplete = true
    elseif valueStr:sub(1, 1) == "+" then
        -- Add to current
        local addValue = tonumber(valueStr:sub(2)) or 1
        newProgress = currentProgress + addValue
    elseif valueStr:sub(1, 1) == "-" then
        -- Subtract from current
        local subValue = tonumber(valueStr:sub(2)) or 1
        newProgress = math.max(0, currentProgress - subValue)
    else
        -- Set absolute value
        newProgress = tonumber(valueStr) or 0
    end

    engine.progressData[achievementId] = newProgress

    -- Update UI
    engine:UpdateUIProgress(achievementId, newProgress, total)

    addon:Print(string.format("Achievement %d progress: %d -> %d (required: %d)",
        achievementId, currentProgress, newProgress, total))

    -- Auto-complete if requested or progress meets requirement
    if newProgress >= total and not engine:IsCompleted(achievementId) then
        if autoComplete then
            engine:CompleteAchievement(achievement)
            addon:Print("|cff00ff00Achievement completed!|r")
        else
            addon:Print("|cff888888(Debug: use '/r progress " .. achievementId .. " max' to auto-complete, or '/r complete " .. achievementId .. "')|r")
        end
    end
end

---List achievements with various filters
function debugCommands:OnListCommand(args)
    local addon = Private.Addon
    local aUtils = Private.AchievementUtils
    local engine = Private.AchievementEngine

    local filter = args and args[1] and string.lower(args[1]) or "all"

    addon:Print("=== Achievement List (" .. filter .. ") ===")

    local count = 0
    local maxShow = 20

    for id, achievement in pairs(aUtils.achievements) do
        local show = false
        local status = ""

        if engine:IsCompleted(id) then
            status = "|cff00ff00[COMPLETED]|r"
            if filter == "all" or filter == "completed" or filter == "done" then
                show = true
            end
        elseif engine:IsFailed(id) then
            status = "|cffff0000[FAILED]|r"
            if filter == "all" or filter == "failed" then
                show = true
            end
        else
            local progress = engine.progressData[id] or 0
            local required = achievement.progress and achievement.progress.required or 1
            if progress > 0 then
                status = string.format("|cffffff00[%d/%d]|r", progress, required)
                if filter == "all" or filter == "progress" or filter == "inprogress" then
                    show = true
                end
            else
                status = "|cff888888[Not started]|r"
                if filter == "all" or filter == "available" or filter == "new" then
                    show = true
                end
            end
        end

        if show and count < maxShow then
            addon:Print(string.format("  |cffffffff%d|r: %s %s", id, achievement.name, status))
            count = count + 1
        end
    end

    if count >= maxShow then
        addon:Print("  ... and more. Use a filter to narrow results.")
    end

    addon:Print("")
    addon:Print("Filters: all, completed, failed, progress, available")
    addon:Print("Usage: /r list [filter]")
end

---Run various test scenarios
function debugCommands:OnTestCommand(args)
    local addon = Private.Addon
    local aUtils = Private.AchievementUtils
    local engine = Private.AchievementEngine

    if not args or #args == 0 then
        addon:Print("=== Test Commands ===")
        addon:Print("|cffffffff/r test alert|r - Test alert animation")
        addon:Print("|cffffffff/r test boss <name>|r - Simulate boss kill")
        addon:Print("|cffffffff/r test quest <id>|r - Simulate quest complete")
        addon:Print("|cffffffff/r test dungeon <name>|r - Simulate dungeon clear")
        addon:Print("|cffffffff/r test skill <name> <level>|r - Simulate skill up")
        addon:Print("|cffffffff/r test kill|r - Simulate PvP kill")
        addon:Print("|cffffffff/r test loot <itemId>|r - Simulate item loot")
        addon:Print("|cffffffff/r test rep <faction> <standing>|r - Simulate rep gain")
        return
    end

    local testType = string.lower(args[1])

    if testType == "alert" then
        -- Test all alert animations
        local shown = 0
        for id, _ in pairs(aUtils.achievements) do
            if shown < 3 then
                C_Timer.After(shown * 2, function()
                    if ReckoningAchievementAlert_Show then
                        ReckoningAchievementAlert_Show(id)
                    end
                end)
                shown = shown + 1
            end
        end
        addon:Print("Queued " .. shown .. " test alerts!")

    elseif testType == "boss" then
        local bossName = args[2] or "Test Boss"
        Private.EventBridge:Fire("DUNGEON_BOSS_KILLED", {
            bossName = bossName,
            bossId = 99999,
            instanceName = "Test Dungeon",
            instanceId = 999,
            difficulty = 1,
            duration = 120,
            deaths = 0,
        })
        addon:Print("Fired DUNGEON_BOSS_KILLED for: " .. bossName)

    elseif testType == "quest" then
        local questId = tonumber(args[2]) or 99999
        Private.EventBridge:Fire("QUEST_COMPLETED", {
            questId = questId,
            questTitle = "Test Quest",
            isDaily = false,
        })
        addon:Print("Fired QUEST_COMPLETED for quest: " .. questId)

    elseif testType == "dungeon" then
        local dungeonName = args[2] or "Test Dungeon"
        Private.EventBridge:Fire("DUNGEON_CLEARED", {
            instanceName = dungeonName,
            instanceId = 999,
            difficulty = 1,
            duration = 1800,
            totalDeaths = 0,
        })
        addon:Print("Fired DUNGEON_CLEARED for: " .. dungeonName)

    elseif testType == "skill" then
        local skillName = args[2] or "Mining"
        local skillLevel = tonumber(args[3]) or 300
        Private.EventBridge:Fire("SKILL_UP", {
            skillName = skillName,
            skillLevel = skillLevel,
        })
        addon:Print("Fired SKILL_UP for: " .. skillName .. " to " .. skillLevel)

    elseif testType == "kill" then
        Private.EventBridge:Fire("PVP_KILL", {
            targetName = "TestEnemy",
            targetClass = "Warrior",
            targetRace = "Human",
            honorGained = 25,
            killingBlow = true,
        })
        addon:Print("Fired PVP_KILL event")

    elseif testType == "loot" then
        local itemId = tonumber(args[2]) or 28478 -- Badge of Justice
        Private.EventBridge:Fire("BADGE_EARNED", {
            itemId = itemId,
            itemName = "Test Item",
            count = 1,
        })
        addon:Print("Fired BADGE_EARNED for item: " .. itemId)

    elseif testType == "rep" then
        local faction = args[2] or "Test Faction"
        local standing = tonumber(args[3]) or 6 -- Revered
        Private.EventBridge:Fire("REPUTATION_GAINED", {
            faction = faction,
            standing = standing,
            standingName = ({"Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted"})[standing] or "Unknown",
            value = 21000,
            min = 0,
            max = 21000,
        })
        addon:Print("Fired REPUTATION_GAINED for: " .. faction .. " at standing " .. standing)

    else
        addon:Print("Unknown test type: " .. testType)
        addon:Print("Use /r test for help")
    end
end

-------------------------------------------------------------------------------
-- Database Debug Commands
-------------------------------------------------------------------------------

---Force save achievement progress
function debugCommands:OnSaveCommand(args)
    local addon = Private.Addon
    local engine = Private.AchievementEngine

    addon:Print("=== Manual Save ===")

    -- Count current data
    local completedCount = 0
    for _ in pairs(engine.completedAchievements or {}) do
        completedCount = completedCount + 1
    end

    local progressCount = 0
    for _ in pairs(engine.progressData or {}) do
        progressCount = progressCount + 1
    end

    addon:Print("Completed achievements: " .. completedCount)
    addon:Print("In-progress achievements: " .. progressCount)

    -- Force save
    engine:SaveProgress()

    addon:Print("|cff00ff00Save complete!|r")
end

---Force load achievement progress
function debugCommands:OnLoadCommand(args)
    local addon = Private.Addon
    local engine = Private.AchievementEngine

    addon:Print("=== Manual Load ===")

    -- Force load
    engine:LoadProgress()

    -- Count loaded data
    local completedCount = 0
    for _ in pairs(engine.completedAchievements or {}) do
        completedCount = completedCount + 1
    end

    local progressCount = 0
    for _ in pairs(engine.progressData or {}) do
        progressCount = progressCount + 1
    end

    addon:Print("Loaded completed: " .. completedCount)
    addon:Print("Loaded in-progress: " .. progressCount)
    addon:Print("|cff00ff00Load complete!|r")
end

---Test the database encoding/decoding system
function debugCommands:OnDbTestCommand(args)
    local addon = Private.Addon
    local dbUtils = Private.DatabaseUtils

    addon:Print("=== Database Encoding Test ===")

    -- Test data
    local testData = {
        progress = { [1001] = 5, [1002] = 10 },
        completed = { [1003] = { completedAt = time(), week = 1 } },
        criteria = { [1004] = { true, false, true } },
        timestamps = { [1003] = time() },
        lastWeek = 1,
        savedAt = time(),
    }

    addon:Print("Test data created with 2 progress, 1 completed")

    -- Test encoding
    local encoded, hash = dbUtils:EncodeData(testData)

    if not encoded then
        addon:Print("|cffff0000FAIL: Encoding returned nil|r")
        return
    end

    addon:Print("|cff00ff00PASS: Encoding succeeded|r")
    addon:Print("  Encoded length: " .. #encoded .. " bytes")
    addon:Print("  Hash: " .. (hash or "nil"))

    -- Test decoding
    local decoded, valid = dbUtils:DecodeData(encoded, hash)

    if not decoded then
        addon:Print("|cffff0000FAIL: Decoding returned nil|r")
        return
    end

    addon:Print("|cff00ff00PASS: Decoding succeeded|r")
    addon:Print("  Hash valid: " .. tostring(valid))

    -- Verify data integrity
    if decoded.progress and decoded.progress[1001] == 5 then
        addon:Print("|cff00ff00PASS: Progress data intact|r")
    else
        addon:Print("|cffff0000FAIL: Progress data corrupted|r")
    end

    if decoded.completed and decoded.completed[1003] then
        addon:Print("|cff00ff00PASS: Completed data intact|r")
    else
        addon:Print("|cffff0000FAIL: Completed data corrupted|r")
    end

    -- Test tamper detection
    local tamperedDecoded, tamperedValid = dbUtils:DecodeData(encoded, "WRONGHASH")
    if not tamperedValid then
        addon:Print("|cff00ff00PASS: Tamper detection working|r")
    else
        addon:Print("|cffff0000FAIL: Tamper detection not working|r")
    end

    addon:Print("")
    addon:Print("=== SavedVariables Status ===")
    addon:Print("achievementData: " .. (addon.Database.achievementData and (#addon.Database.achievementData .. " bytes") or "nil"))
    addon:Print("achievementHash: " .. (addon.Database.achievementHash or "nil"))
    addon:Print("lastSaved: " .. (addon.Database.lastSaved or 0))
end