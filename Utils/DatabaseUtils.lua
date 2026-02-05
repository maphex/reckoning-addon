---@class AddonPrivate
local Private = select(2, ...)
local const = Private.constants

-------------------------------------------------------------------------------
-- Database Utils - Persistence with encoding/compression
-------------------------------------------------------------------------------

---@class DatabaseUtils
local databaseUtils = {
    -- Salt for hash verification (change this for your server)
    HASH_SALT = "ReckoningAchievementSalt2026",
}
Private.DatabaseUtils = databaseUtils

-------------------------------------------------------------------------------
-- Default Schema Updates
-------------------------------------------------------------------------------

---@param database table
---@param defaults table
function databaseUtils:CheckAndUpdate(database, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if database[key] == nil then
                database[key] = {}
            end
            self:CheckAndUpdate(database[key], value)
        else
            if database[key] == nil then
                database[key] = value
            end
        end
    end
end

function databaseUtils:LoadDefaultsForMissing()
    local addon = Private.Addon
    local defaults = addon.DefaultDatabase
    local database = addon.Database
    local charDefaults = addon.DefaultCharDatabase
    local charDatabase = addon.CharDatabase

    self:CheckAndUpdate(database, defaults)
    self:CheckAndUpdate(charDatabase, charDefaults)
end

-------------------------------------------------------------------------------
-- Hash Generation for Tamper Detection
-------------------------------------------------------------------------------

---Generate a simple hash from data string
---@param data string
---@return string
function databaseUtils:GenerateHash(data)
    -- Simple hash using string operations
    -- For TBC, we use a combination of checksums
    local hash = 0
    local salt = self.HASH_SALT

    -- Combine data with salt
    local combined = salt .. data .. salt

    for i = 1, #combined do
        local char = string.byte(combined, i)
        hash = ((hash * 31) + char) % 2147483647
    end

    -- Convert to hex string
    return string.format("%08X", hash)
end

---Verify hash matches data
---@param data string
---@param expectedHash string
---@return boolean
function databaseUtils:VerifyHash(data, expectedHash)
    local actualHash = self:GenerateHash(data)
    return actualHash == expectedHash
end

-------------------------------------------------------------------------------
-- Encoding/Decoding for Persistence
-------------------------------------------------------------------------------

---Convert table with numeric keys to string keys for JSON compatibility
---@param tbl table
---@return table
function databaseUtils:PrepareForJSON(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end

    local result = {}
    for k, v in pairs(tbl) do
        local newKey = type(k) == "number" and ("n" .. tostring(k)) or k
        local newValue = type(v) == "table" and self:PrepareForJSON(v) or v
        result[newKey] = newValue
    end
    return result
end

---Convert table with string keys back to numeric keys after JSON deserialization
---@param tbl table
---@return table
function databaseUtils:RestoreFromJSON(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end

    local result = {}
    for k, v in pairs(tbl) do
        local newKey = k
        -- Check if key starts with "n" followed by a number
        if type(k) == "string" and k:sub(1, 1) == "n" then
            local numKey = tonumber(k:sub(2))
            if numKey then
                newKey = numKey
            end
        end
        local newValue = type(v) == "table" and self:RestoreFromJSON(v) or v
        result[newKey] = newValue
    end
    return result
end

---Encode achievement data for storage
---@param data table
---@return string|nil encodedData
---@return string|nil hash
function databaseUtils:EncodeData(data)
    if not data then return nil, nil end

    -- Convert numeric keys to string keys for JSON compatibility
    local jsonSafe = self:PrepareForJSON(data)

    -- Serialize to JSON using C_EncodingUtil
    local jsonString = C_EncodingUtil.SerializeJSON(jsonSafe)

    if not jsonString then
        -- Fallback: manual serialization (works with numeric keys)
        jsonString = self:SimpleSerialize(data)
    end

    if not jsonString then
        return nil, nil
    end

    -- Generate verification hash BEFORE encoding
    local hash = self:GenerateHash(jsonString)

    -- Compress and encode to Base64
    local compressed = C_EncodingUtil.CompressString(jsonString)
    local encoded = C_EncodingUtil.EncodeBase64(compressed or jsonString)

    return encoded, hash
end

---Decode achievement data from storage
---@param encodedData string
---@param expectedHash string
---@return table|nil data
---@return boolean valid
function databaseUtils:DecodeData(encodedData, expectedHash)
    if not encodedData or encodedData == "" then
        return nil, false
    end

    -- Decode from Base64
    local decoded = C_EncodingUtil.DecodeBase64(encodedData)

    if not decoded then
        return nil, false
    end

    -- Try to decompress
    local decompressed = C_EncodingUtil.DecompressString(decoded)

    -- Use decompressed if available, otherwise use decoded directly
    local jsonString = decompressed or decoded

    -- Verify hash
    local hashValid = self:VerifyHash(jsonString, expectedHash or "")

    -- Deserialize from JSON
    local data = C_EncodingUtil.DeserializeJSON(jsonString)

    if data then
        -- Convert string keys back to numeric keys
        data = self:RestoreFromJSON(data)
    else
        -- Fallback: try simple deserialization
        data = self:SimpleDeserialize(jsonString)
    end

    if not data then
        return nil, false
    end

    return data, hashValid
end

-------------------------------------------------------------------------------
-- Simple Serialization Fallback (if C_EncodingUtil unavailable)
-------------------------------------------------------------------------------

---Simple table to string serialization
---@param tbl table
---@param indent? number
---@return string
function databaseUtils:SimpleSerialize(tbl, indent)
    if type(tbl) ~= "table" then
        if type(tbl) == "string" then
            return string.format("%q", tbl)
        elseif type(tbl) == "boolean" then
            return tbl and "true" or "false"
        else
            return tostring(tbl)
        end
    end

    local result = "{"
    local first = true

    for k, v in pairs(tbl) do
        if not first then
            result = result .. ","
        end
        first = false

        -- Key
        if type(k) == "number" then
            result = result .. "[" .. k .. "]="
        else
            result = result .. "[" .. string.format("%q", k) .. "]="
        end

        -- Value
        result = result .. self:SimpleSerialize(v)
    end

    return result .. "}"
end

---Simple string to table deserialization
---@param str string
---@return table|nil
function databaseUtils:SimpleDeserialize(str)
    if not str or str == "" then return nil end

    -- Try to load as Lua code (safe for our own serialized data)
    local func, err = loadstring("return " .. str)
    if func then
        local success, result = pcall(func)
        if success then
            return result
        end
    end

    return nil
end

-------------------------------------------------------------------------------
-- Achievement Progress Persistence
-------------------------------------------------------------------------------

---Wipe all local (player) achievement progress from the database.
---This intentionally does NOT touch settings or guild sync caches.
function databaseUtils:WipeLocalAchievementProgress()
    local addon = Private.Addon
    if not addon or not addon.Database then return end

    -- Encoded format
    addon.Database.achievementData = nil
    addon.Database.achievementHash = nil
    addon.Database.achievementVersion = 1
    addon.Database.lastSaved = 0

    -- Raw fallback (if encoding failed previously)
    addon.Database.achievementDataRaw = nil

    -- Legacy fields (kept for backwards compatibility)
    addon.Database.progress = {}
    addon.Database.criteriaProgress = {}
    addon.Database.completed = {}
    addon.Database.completedTimestamps = {}
    addon.Database.lastWeek = 0

    -- Exploration progress used by the achievement system
    addon.Database.exploredZones = {}
end

---Save achievement progress to SavedVariables
---@param achievements table Achievement progress data
function databaseUtils:SaveAchievementProgress(achievements)
    local addon = Private.Addon
    if not addon then
        print("|cffff0000[Reckoning] SaveAchievementProgress: addon not found|r")
        return false
    end

    if not addon.Database then
        print("|cffff0000[Reckoning] SaveAchievementProgress: addon.Database not found|r")
        return false
    end

    if not achievements then
        print("|cffff0000[Reckoning] SaveAchievementProgress: no achievements data provided|r")
        return false
    end

    local encoded, hash = self:EncodeData(achievements)

    if not encoded then
        print("|cffff0000[Reckoning] SaveAchievementProgress: encoding failed|r")
        -- Fallback: save raw data
        addon.Database.achievementDataRaw = achievements
        addon.Database.achievementData = nil
        addon.Database.achievementHash = nil
        return false
    end

    addon.Database.achievementData = encoded
    addon.Database.achievementHash = hash
    addon.Database.achievementVersion = 1
    addon.Database.lastSaved = time()

    -- Clear raw data if encoding succeeded
    addon.Database.achievementDataRaw = nil

    local debugUtils = Private.DebugUtils
    if debugUtils and debugUtils.enabled then
        debugUtils:Log("DATABASE", "Saved achievement progress (encoded=%d bytes, hash=%s)", #encoded, hash or "nil")
    end

    return true
end

---Load achievement progress from SavedVariables
---@return table|nil achievements
---@return boolean valid Whether data passed hash verification
function databaseUtils:LoadAchievementProgress()
    local addon = Private.Addon
    if not addon then
        print("|cffff0000[Reckoning] LoadAchievementProgress: addon not found|r")
        return nil, false
    end

    if not addon.Database then
        print("|cffff0000[Reckoning] LoadAchievementProgress: addon.Database not found|r")
        return nil, false
    end

    -- Check for raw data fallback first
    if addon.Database.achievementDataRaw then
        local debugUtils = Private.DebugUtils
        if debugUtils and debugUtils.enabled then
            debugUtils:Log("DATABASE", "Loading achievement progress from raw fallback data")
        end
        return addon.Database.achievementDataRaw, true
    end

    local encoded = addon.Database.achievementData
    local hash = addon.Database.achievementHash

    if not encoded then
        -- No data yet, but valid state (new player)
        return nil, true
    end

    local data, valid = self:DecodeData(encoded, hash)

    if not data then
        print("|cffff0000[Reckoning] LoadAchievementProgress: decoding failed|r")
        return nil, false
    end

    local debugUtils = Private.DebugUtils
    if debugUtils and debugUtils.enabled then
        local completedCount = data.completed and self:CountTable(data.completed) or 0
        debugUtils:Log("DATABASE", "Loaded achievement progress (completed=%d, valid=%s)", completedCount, tostring(valid))
    end

    if not valid then
        -- Data was tampered with!
        print("|cffff0000[Reckoning] Warning: Achievement data appears to have been modified externally.|r")
    end

    return data, valid
end

---Helper to count table entries
---@param tbl table
---@return number
function databaseUtils:CountTable(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-------------------------------------------------------------------------------
-- Weekly Progress Tracking
-------------------------------------------------------------------------------

---Get the current week number based on server reset
---Week 0 = pre-launch (before TBC_ANNIVERSARY_EPOCH). IsAchievementAvailable treats week 0 as unavailable.
---@return number weekNumber
function databaseUtils:GetCurrentWeek()
    -- Calculate weeks since TBC Anniversary launch (February 3, 2026)
    -- Week 1 starts on launch day
    local TBC_ANNIVERSARY_EPOCH = 1770076800 -- Unix timestamp for Feb 3, 2026 00:00:00 UTC
    local WEEK_SECONDS = 604800 -- 7 days in seconds

    local now = time()
    local secondsSinceLaunch = now - TBC_ANNIVERSARY_EPOCH

    -- Before launch: return 0 so week gating can treat all time-limited achievements as unavailable
    if secondsSinceLaunch < 0 then
        return 0
    end

    -- Week 1 is the first week (0-6 days after launch = week 1)
    local weekNumber = math.floor(secondsSinceLaunch / WEEK_SECONDS) + 1

    return weekNumber
end

---Check if weekly reset has occurred since last login
---@param lastSavedWeek number
---@return boolean
function databaseUtils:HasWeeklyReset(lastSavedWeek)
    return self:GetCurrentWeek() > lastSavedWeek
end

---Get progress data for an achievement
---@param achievementId number
---@return table|nil progress
function databaseUtils:GetAchievementProgress(achievementId)
    local addon = Private.Addon
    if not addon or not addon.Database then return nil end

    local progress = addon.Database.progress or {}
    return progress[achievementId]
end

---Set progress data for an achievement
---@param achievementId number
---@param progressData table
function databaseUtils:SetAchievementProgress(achievementId, progressData)
    local addon = Private.Addon
    if not addon or not addon.Database then return end

    addon.Database.progress = addon.Database.progress or {}
    addon.Database.progress[achievementId] = progressData
end

---Rebuild addon.Database.completed from engine state (after load). Non-destructive: only sets entries for completed achievement IDs.
---@param completedAchievements table<number, boolean>
---@param completedTimestamps table<number, number>
---@param completionVersions table<number, string>|nil
function databaseUtils:RebuildCompletedFromEngine(completedAchievements, completedTimestamps, completionVersions)
    local addon = Private.Addon
    if not addon or not addon.Database then return end
    addon.Database.completed = addon.Database.completed or {}
    completionVersions = completionVersions or {}
    for id, _ in pairs(completedAchievements or {}) do
        local ts = (completedTimestamps and completedTimestamps[id]) or time()
        local ver = completionVersions[id] and tostring(completionVersions[id]) or nil
        addon.Database.completed[id] = {
            completedAt = ts,
            week = nil, -- do not guess historical week for loaded data
            addonVersion = ver,
        }
    end
end

---Clear a single achievement from the completed cache (call when engine uncompletes).
---@param achievementId number
function databaseUtils:ClearCompletion(achievementId)
    local addon = Private.Addon
    if not addon or not addon.Database then return end
    if addon.Database.completed and addon.Database.completed[achievementId] then
        addon.Database.completed[achievementId] = nil
    end
end

---Clear all completed cache (e.g. on full progress wipe).
function databaseUtils:ClearAllCompletions()
    local addon = Private.Addon
    if not addon or not addon.Database then return end
    addon.Database.completed = {}
end

---Mark an achievement as completed
---@param achievementId number
---@param timestamp? number
function databaseUtils:CompleteAchievement(achievementId, timestamp)
    local addon = Private.Addon
    if not addon or not addon.Database then return end

    addon.Database.completed = addon.Database.completed or {}
    addon.Database.completed[achievementId] = {
        completedAt = timestamp or time(),
        week = self:GetCurrentWeek(),
        addonVersion = (const and const.ADDON_VERSION) and tostring(const.ADDON_VERSION) or nil,
    }
end

---Check if an achievement is completed
---@param achievementId number
---@return boolean
---@return number|nil completedAt
---@return string|nil addonVersion addon version at completion time (nil for legacy entries)
function databaseUtils:IsAchievementCompleted(achievementId)
    local addon = Private.Addon
    if not addon or not addon.Database then return false, nil, nil end

    local completed = addon.Database.completed or {}
    local data = completed[achievementId]

    if data then
        return true, data.completedAt, data.addonVersion and tostring(data.addonVersion) or nil
    end

    return false, nil, nil
end

---Reset weekly achievements
function databaseUtils:ResetWeeklyAchievements()
    local addon = Private.Addon
    if not addon or not addon.Database then return end

    local aUtils = Private.AchievementUtils
    if not aUtils then return end

    -- Get all weekly achievements
    for id, achievement in pairs(aUtils.achievements) do
        if achievement.cadence == Private.Enums.Cadence.Weekly then
            -- Reset progress for weekly achievements
            self:SetAchievementProgress(id, nil)

            -- Remove from completed if it was weekly
            if addon.Database.completed and addon.Database.completed[id] then
                addon.Database.completed[id] = nil
            end
        end
    end

    -- Update last reset week
    addon.Database.lastResetWeek = self:GetCurrentWeek()
end

-------------------------------------------------------------------------------
-- Explored Zones Persistence
-------------------------------------------------------------------------------

---Save explored zones
---@param zones table<string, boolean>
function databaseUtils:SaveExploredZones(zones)
    local addon = Private.Addon
    if not addon or not addon.Database then return end

    addon.Database.exploredZones = zones
end

---Load explored zones
---@return table<string, boolean>
function databaseUtils:LoadExploredZones()
    local addon = Private.Addon
    if not addon or not addon.Database then return {} end

    return addon.Database.exploredZones or {}
end
