---@class AddonPrivate
local Private = select(2, ...)

-------------------------------------------------------------------------------
-- Debug Utils - Debug logging and inspection tools
-------------------------------------------------------------------------------

---@class DebugUtils
local debugUtils = {
    ---@type boolean
    enabled = false,
    ---@type boolean
    verbose = false,
    ---@type table<string, boolean> -- Category filters
    filters = {
        EVENTS = true,      -- Event firing and handling
        TRIGGERS = true,    -- Achievement trigger evaluation
        CONDITIONS = true,  -- Condition checking
        PROGRESS = true,    -- Progress updates
        COMPLETION = true,  -- Achievement completions
        WEEKLY = true,      -- Weekly reset handling
        DATABASE = true,    -- Database operations
        UI = true,          -- UI updates
    },
    ---@type table<number, string> -- Log history
    logHistory = {},
    ---@type number
    maxHistory = 500,
}
Private.DebugUtils = debugUtils

-- Color codes for different log categories
local COLORS = {
    EVENTS = "|cff00ff00",      -- Green
    TRIGGERS = "|cff00ffff",    -- Cyan
    CONDITIONS = "|cffffcc00",  -- Gold
    PROGRESS = "|cff9966ff",    -- Purple
    COMPLETION = "|cffff00ff",  -- Magenta
    WEEKLY = "|cffff9900",      -- Orange
    DATABASE = "|cff6699ff",    -- Light Blue
    UI = "|cffcccccc",          -- Gray
    ERROR = "|cffff0000",       -- Red
    WARNING = "|cffffff00",     -- Yellow
    INFO = "|cffffffff",        -- White
}

-------------------------------------------------------------------------------
-- Core Logging Functions
-------------------------------------------------------------------------------

---Log a debug message
---@param category string
---@param message string
---@param ... any
function debugUtils:Log(category, message, ...)
    if not self.enabled then return end
    if not self.filters[category] then return end

    local color = COLORS[category] or COLORS.INFO
    local timestamp = date("%H:%M:%S")
    local formatted = string.format(message, ...)

    local output = string.format("%s[%s][%s]|r %s", color, timestamp, category, formatted)

    -- Store in history
    table.insert(self.logHistory, output)
    if #self.logHistory > self.maxHistory then
        table.remove(self.logHistory, 1)
    end

    -- Print to chat
    if Private.Addon then
        Private.Addon:Print(output)
    else
        print("[Reckoning Debug] " .. output)
    end
end

---Log verbose message (only in verbose mode)
---@param category string
---@param message string
---@param ... any
function debugUtils:LogVerbose(category, message, ...)
    if not self.verbose then return end
    self:Log(category, message, ...)
end

---Log an error (always shows if debug enabled)
---@param message string
---@param ... any
function debugUtils:Error(message, ...)
    if not self.enabled then return end
    self:Log("ERROR", "|cffff0000ERROR:|r " .. message, ...)
end

---Log a warning
---@param message string
---@param ... any
function debugUtils:Warning(message, ...)
    if not self.enabled then return end
    self:Log("WARNING", "|cffffff00WARNING:|r " .. message, ...)
end

-------------------------------------------------------------------------------
-- Event Logging
-------------------------------------------------------------------------------

---Log a bridge event being fired
---@param eventName string
---@param payload table
function debugUtils:LogEvent(eventName, payload)
    if not self.enabled or not self.filters.EVENTS then return end

    local payloadStr = self:TableToString(payload, 1)
    self:Log("EVENTS", "Event fired: |cffffffff%s|r", eventName)
    if self.verbose and payload then
        self:Log("EVENTS", "  Payload: %s", payloadStr)
    end
end

---Log a WoW event being received
---@param event string
---@param ... any
function debugUtils:LogWowEvent(event, ...)
    if not self.verbose then return end
    if not self.enabled or not self.filters.EVENTS then return end

    local args = {...}
    local argStr = ""
    for i, v in ipairs(args) do
        if i > 1 then argStr = argStr .. ", " end
        argStr = argStr .. tostring(v)
    end

    self:Log("EVENTS", "WoW Event: |cff888888%s|r (%s)", event, argStr)
end

-------------------------------------------------------------------------------
-- Achievement Logging
-------------------------------------------------------------------------------

---Log achievement trigger evaluation
---@param achievement table
---@param event string
function debugUtils:LogTriggerEval(achievement, event)
    if not self.enabled or not self.filters.TRIGGERS then return end
    self:Log("TRIGGERS", "Evaluating: [%d] %s (event: %s)",
        achievement.id, achievement.name, event)
end

---Log condition check
---@param conditionName string
---@param expected any
---@param actual any
---@param result boolean
function debugUtils:LogCondition(conditionName, expected, actual, result)
    if not self.verbose then return end
    if not self.enabled or not self.filters.CONDITIONS then return end

    local resultStr = result and "|cff00ff00PASS|r" or "|cffff0000FAIL|r"
    self:Log("CONDITIONS", "  %s: expected=%s, actual=%s -> %s",
        conditionName, tostring(expected), tostring(actual), resultStr)
end

---Log progress update
---@param achievementId number
---@param achievementName string
---@param current number
---@param required number
function debugUtils:LogProgress(achievementId, achievementName, current, required)
    if not self.enabled or not self.filters.PROGRESS then return end
    self:Log("PROGRESS", "[%d] %s: %d/%d",
        achievementId, achievementName, current, required)
end

---Log achievement completion
---@param achievement table
function debugUtils:LogCompletion(achievement)
    if not self.enabled or not self.filters.COMPLETION then return end
    self:Log("COMPLETION", "|cff00ff00COMPLETED:|r [%d] %s (%d points)",
        achievement.id, achievement.name, achievement.points or 0)
end

---Log achievement skipped
---@param achievementId number
---@param reason string
function debugUtils:LogSkipped(achievementId, reason)
    if not self.verbose then return end
    if not self.enabled or not self.filters.TRIGGERS then return end
    self:Log("TRIGGERS", "  Skipped [%d]: %s", achievementId, reason)
end

-------------------------------------------------------------------------------
-- Weekly/Database Logging
-------------------------------------------------------------------------------

---Log weekly reset
---@param oldWeek number
---@param newWeek number
function debugUtils:LogWeeklyReset(oldWeek, newWeek)
    if not self.enabled or not self.filters.WEEKLY then return end
    self:Log("WEEKLY", "Weekly reset detected: Week %d -> Week %d", oldWeek, newWeek)
end

---Log database operation
---@param operation string
---@param details string
function debugUtils:LogDatabase(operation, details)
    if not self.enabled or not self.filters.DATABASE then return end
    self:Log("DATABASE", "%s: %s", operation, details)
end

-------------------------------------------------------------------------------
-- UI Logging
-------------------------------------------------------------------------------

---Log UI update
---@param component string
---@param action string
function debugUtils:LogUI(component, action)
    if not self.verbose then return end
    if not self.enabled or not self.filters.UI then return end
    self:Log("UI", "%s: %s", component, action)
end

-------------------------------------------------------------------------------
-- Toggle Functions
-------------------------------------------------------------------------------

---Enable debug mode
function debugUtils:Enable()
    self.enabled = true
    if Private.Addon then
        Private.Addon:Print("|cff00ff00Debug mode ENABLED|r")
        Private.Addon:Print("Use |cffffffff/r debug status|r to see current state")
        Private.Addon:Print("Use |cffffffff/r debug verbose|r to toggle verbose mode")
        Private.Addon:Print("Use |cffffffff/r debug filter <category>|r to toggle filters")
    end
end

---Disable debug mode
function debugUtils:Disable()
    self.enabled = false
    if Private.Addon then
        Private.Addon:Print("|cffff0000Debug mode DISABLED|r")
    end
end

---Toggle debug mode
function debugUtils:Toggle()
    if self.enabled then
        self:Disable()
    else
        self:Enable()
    end
end

---Toggle verbose mode
function debugUtils:ToggleVerbose()
    self.verbose = not self.verbose
    if Private.Addon then
        if self.verbose then
            Private.Addon:Print("|cff00ff00Verbose mode ENABLED|r - showing detailed logs")
        else
            Private.Addon:Print("|cffff9900Verbose mode DISABLED|r - showing normal logs")
        end
    end
end

---Toggle a filter category
---@param category string
function debugUtils:ToggleFilter(category)
    category = string.upper(category)
    if self.filters[category] ~= nil then
        self.filters[category] = not self.filters[category]
        if Private.Addon then
            local status = self.filters[category] and "|cff00ff00ON|r" or "|cffff0000OFF|r"
            Private.Addon:Print(string.format("Filter %s: %s", category, status))
        end
    else
        if Private.Addon then
            Private.Addon:Print("|cffff0000Unknown filter:|r " .. category)
            self:PrintFilters()
        end
    end
end

---Print current filter status
function debugUtils:PrintFilters()
    if not Private.Addon then return end
    Private.Addon:Print("=== Debug Filters ===")
    for category, enabled in pairs(self.filters) do
        local status = enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        local color = COLORS[category] or "|cffffffff"
        Private.Addon:Print(string.format("  %s%s|r: %s", color, category, status))
    end
end

---Print debug status
function debugUtils:PrintStatus()
    if not Private.Addon then return end
    local addon = Private.Addon

    addon:Print("=== Debug Status ===")
    addon:Print("Debug Mode: " .. (self.enabled and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
    addon:Print("Verbose Mode: " .. (self.verbose and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
    addon:Print("Log History: " .. #self.logHistory .. "/" .. self.maxHistory)

    self:PrintFilters()
end

---Print recent log history
---@param count number|nil
function debugUtils:PrintHistory(count)
    count = count or 20
    if not Private.Addon then return end

    Private.Addon:Print("=== Recent Debug Log (" .. count .. " entries) ===")
    local start = math.max(1, #self.logHistory - count + 1)
    for i = start, #self.logHistory do
        print(self.logHistory[i])
    end
end

---Clear log history
function debugUtils:ClearHistory()
    self.logHistory = {}
    if Private.Addon then
        Private.Addon:Print("Debug log history cleared")
    end
end

-------------------------------------------------------------------------------
-- Utility Functions
-------------------------------------------------------------------------------

---Convert table to string for logging
---@param tbl table
---@param depth number|nil
---@return string
function debugUtils:TableToString(tbl, depth)
    if type(tbl) ~= "table" then
        return tostring(tbl)
    end

    depth = depth or 3
    if depth <= 0 then
        return "{...}"
    end

    local parts = {}
    local count = 0
    for k, v in pairs(tbl) do
        count = count + 1
        if count > 10 then
            table.insert(parts, "...")
            break
        end

        local key = type(k) == "string" and k or "[" .. tostring(k) .. "]"
        local value
        if type(v) == "table" then
            value = self:TableToString(v, depth - 1)
        elseif type(v) == "string" then
            value = '"' .. v .. '"'
        elseif type(v) == "function" then
            value = "<function>"
        else
            value = tostring(v)
        end
        table.insert(parts, key .. "=" .. value)
    end

    return "{" .. table.concat(parts, ", ") .. "}"
end

---Inspect an achievement
---@param achievementId number
function debugUtils:InspectAchievement(achievementId)
    if not Private.Addon then return end
    local addon = Private.Addon
    local aUtils = Private.AchievementUtils
    local engine = Private.AchievementEngine

    local achievement = aUtils and aUtils.achievements[achievementId]
    if not achievement then
        addon:Print("|cffff0000Achievement not found:|r " .. achievementId)
        return
    end

    addon:Print("=== Achievement Inspection ===")
    addon:Print("ID: " .. achievement.id)
    addon:Print("Name: " .. achievement.name)
    addon:Print("Description: " .. (achievement.description or "N/A"))
    addon:Print("Category: " .. achievement.category .. "/" .. (achievement.subCategory or "N/A"))
    addon:Print("Points: " .. (achievement.points or 0))
    addon:Print("Cadence: " .. (achievement.cadence or "Unknown"))
    addon:Print("Start Week: " .. (achievement.startWeek or 1))

    if achievement.trigger then
        addon:Print("Trigger Event: " .. (achievement.trigger.event or "N/A"))
        addon:Print("Conditions: " .. self:TableToString(achievement.trigger.conditions, 2))
    end

    if achievement.progress then
        addon:Print("Progress Type: " .. (achievement.progress.type or "N/A"))
        addon:Print("Required: " .. (achievement.progress.required or 1))
    end

    if engine then
        local progress = engine.progressData[achievementId] or 0
        local completed = engine:IsCompleted(achievementId)
        addon:Print("Current Progress: " .. progress)
        addon:Print("Completed: " .. (completed and "|cff00ff00Yes|r" or "|cffff0000No|r"))
    end
end
