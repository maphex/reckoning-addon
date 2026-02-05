---@class AddonPrivate
local Private = select(2, ...)

---@class UnitCacheEntry
---@field lastUpdatedTime number
---@field level number
---@field class Enums.Class
---@field creatureType Enums.CreatureType

---@class UnitCache
local unitCache = {
    ---@type table<string, UnitCacheEntry>
    cache = {},
}
Private.UnitCache = unitCache

function unitCache:Init()
    local addon = Private.Addon

    addon:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "UnitCache_UpdateMouseoverUnit", function ()
        self:GatherAndCacheUnitInfo("mouseover")
    end)
    addon:RegisterEvent("PLAYER_FOCUS_CHANGED", "UnitCache_UpdateMouseoverUnit", function ()
        self:GatherAndCacheUnitInfo("focus")
    end)
    addon:RegisterEvent("UNIT_TARGET", "UnitCache_UpdateUnitTarget", function (_, _, unit)
        self:GatherAndCacheUnitInfo(unit .. "target")
    end)
    addon:RegisterEvent("NAME_PLATE_UNIT_ADDED", "UnitCache_UpdateUnitTarget", function (_, _, unit)
        self:GatherAndCacheUnitInfo(unit)
    end)
    addon:RegisterEvent("UNIT_LEVEL", "UnitCache_UpdateUnitTarget", function (_, _, unit)
        self:GatherAndCacheUnitInfo(unit)
    end)
end

---@param guid WOWGUID
---@param now number
---@return boolean isThrottled
function unitCache:IsCacheThrottledForGUID(guid, now)
    if not guid then return false end
    local cacheEntry = self.cache[guid]
    if not cacheEntry then return false end
    now = now or GetTime()
    if cacheEntry.lastUpdatedTime and now < cacheEntry.lastUpdatedTime + 1 then
        return true
    end
    return false
end

---@param unit UnitToken.base
function unitCache:GatherAndCacheUnitInfo(unit)
    local now = GetTime()
    local guid = UnitGUID(unit)
    if not guid then return end
    if self:IsCacheThrottledForGUID(guid, now) then return end

    local level = UnitLevel(unit)
    local class = select(3, UnitClassBase(unit))
    local creatureType = select(2, UnitCreatureType(unit))

    self.cache[guid] = {
        lastUpdatedTime = now,
        level = level,
        class = class,
        creatureType = creatureType,
    }
end

---@param guid WOWGUID
---@return UnitCacheEntry|nil unitCacheEntry
function unitCache:GetCacheByGUID(guid)
    return self.cache[guid]
end

---@param guid WOWGUID
---@param key "level"|"class"|"creatureType"
function unitCache:GetCacheValueByGUID(guid, key)
    local cacheEntry = self:GetCacheByGUID(guid)
    if cacheEntry then
        return cacheEntry[key]
    end
    return nil
end

---@param guid WOWGUID
---@return Enums.CreatureType|nil creatureType
function unitCache:GetCreatureTypeByGUID(guid)
    return self:GetCacheValueByGUID(guid, "creatureType")
end

---@param guid WOWGUID
---@return number|nil level
function unitCache:GetLevelByGUID(guid)
    return self:GetCacheValueByGUID(guid, "level")
end

---@param guid WOWGUID
---@return Enums.Class|nil class
function unitCache:GetClassByGUID(guid)
    return self:GetCacheValueByGUID(guid, "class")
end
