---@class AddonPrivate
local Private = select(2, ...)

local const = Private.constants

-------------------------------------------------------------------------------
-- Achievement correction sync (officer/GM only to create; all receive and apply)
-- Types: full_invalidate, invalidate_from_date, revalidate, cancel (voids a prior correction).
-------------------------------------------------------------------------------

---@class AchievementCorrection
---@field id string
---@field achievementId number
---@field type "full_invalidate"|"invalidate_from_date"|"revalidate"|"cancel"|"reset"
---@field issuedBy string
---@field issuedAt number
---@field fromDate number|nil For invalidate_from_date: don't count completions with completedAt >= fromDate
---@field addonVersion string|nil For revalidate: min achiever addon version that may count
---@field effectiveAt number|nil Optional effective timestamp for revalidate
---@field targetCorrectionId string|nil For cancel: the correction being canceled
---@field revertedByCorrectionId string|nil Set when this correction is voided (by a cancel or legacy revert)
---@field beforeDate number|nil For reset: completions with completedAt before this are masked (virtual uncomplete)
---@field beforeVersion string|nil For reset: completions with completionVersion < this (semver) are masked
---@field mode string|nil For reset: "points" (scoring only) or "uncomplete" (scoring + treat as incomplete in UI); both evaluated same for counting

---@class CorrectionSyncUtils
local correctionSync = {
    ---@type table<string, AchievementCorrection> id -> correction
    corrections = {},
    ---@type number
    lastRequestAt = 0,
    ---@type number
    REQUEST_COOLDOWN = 60,
}
Private.CorrectionSyncUtils = correctionSync

local MSG_TYPE = {
    CREATE = "GCORR_CREATE",
    REQ = "GCORR_REQ",
    RESP = "GCORR_RESP",
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function GetPlayerShortName()
    if type(UnitName) ~= "function" then return nil end
    local name = UnitName("player")
    if not name or name == "" then return nil end
    return tostring(name):match("^([^%-]+)") or tostring(name)
end

local function IsInGuildSafe()
    if type(IsInGuild) ~= "function" then return false end
    return IsInGuild() == true
end

local function IsAdmin()
    if not IsInGuildSafe() then return false end
    if type(GetGuildInfo) ~= "function" then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    rankIndex = tonumber(rankIndex)
    return rankIndex ~= nil and rankIndex <= 1
end

local function GetGuildKey()
    if not IsInGuildSafe() then return nil end
    local guildName = GetGuildInfo("player")
    if not guildName or guildName == "" then return nil end
    local realm = (type(GetRealmName) == "function") and GetRealmName() or ""
    return tostring(guildName) .. "@" .. tostring(realm)
end

local function ToBase36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz"
    local out = {}
    while n > 0 do
        local r = (n % 36) + 1
        out[#out + 1] = BASE36:sub(r, r)
        n = math.floor(n / 36)
    end
    for i = 1, math.floor(#out / 2) do
        out[i], out[#out - i + 1] = out[#out - i + 1], out[i]
    end
    return table.concat(out)
end

-------------------------------------------------------------------------------
-- Persistence
-------------------------------------------------------------------------------

function correctionSync:EnsureCorrectionsBound()
    local addon = Private.Addon
    if not addon or not addon.Database then return end
    local db = addon.Database
    db.guildCache = db.guildCache or {}
    db.guildCache.achievementCorrections = db.guildCache.achievementCorrections or {}
    self.corrections = db.guildCache.achievementCorrections
end

function correctionSync:LoadCachedCorrections()
    self:EnsureCorrectionsBound()
end

function correctionSync:SaveCachedCorrections()
    local addon = Private.Addon
    if not addon or not addon.Database then return end
    addon.Database.guildCache = addon.Database.guildCache or {}
    addon.Database.guildCache.achievementCorrections = self.corrections or {}
    addon.Database.achievementCorrectionsSavedAt = time()
end

-------------------------------------------------------------------------------
-- Comms
-------------------------------------------------------------------------------

function correctionSync:SendGuildMessage(subPrefix, payload, priority)
    local comms = Private.CommsUtils
    if not comms then return end
    if not IsInGuildSafe() then return end
    payload.subPrefix = subPrefix
    payload.protocolVersion = const and const.ADDON_COMMS and const.ADDON_COMMS.PROTOCOL_VERSION or 1
    payload.timestamp = payload.timestamp or time()
    if priority then payload.priority = priority end
    local encoded = comms:Encode(payload)
    if not encoded then return end
    comms:SendEncodedMessage(subPrefix, encoded, "GUILD", nil, priority or "NORMAL")
end

-------------------------------------------------------------------------------
-- Correction logic: should we count this achievement's points?
-------------------------------------------------------------------------------

--- Returns whether a correction is voided (canceled or reverted).
---@param c table
---@return boolean
local function IsCorrectionVoided(c)
    return type(c) == "table" and (c.revertedByCorrectionId and c.revertedByCorrectionId ~= "")
end

---@param achievementId number
---@param completedAt number|nil Unix timestamp when achievement was completed (nil = treat as "long ago" for full_invalidate only)
---@param completionVersion string|nil Achiever's addon version at completion time (for revalidate gating; applied in version-gate todo)
---@return boolean
function correctionSync:ShouldCountAchievementPoints(achievementId, completedAt, completionVersion)
    self:EnsureCorrectionsBound()
    achievementId = tonumber(achievementId)
    if not achievementId then return true end

    local list = {}
    for _, c in pairs(self.corrections or {}) do
        if type(c) == "table" and c.achievementId == achievementId and not IsCorrectionVoided(c) and c.type ~= "cancel" then
            list[#list + 1] = c
        end
    end
    if #list == 0 then return true end
    table.sort(list, function(a, b)
        return (tonumber(a.issuedAt) or 0) < (tonumber(b.issuedAt) or 0)
    end)

    local fullyInvalidated = false
    local invalidAfter = nil
    local minCompletionVersion = nil
    for _, c in ipairs(list) do
        if c.type == "full_invalidate" then
            fullyInvalidated = true
            invalidAfter = nil
            minCompletionVersion = nil
        elseif c.type == "invalidate_from_date" then
            invalidAfter = tonumber(c.fromDate)
        elseif c.type == "revalidate" then
            fullyInvalidated = false
            invalidAfter = nil
            minCompletionVersion = c.addonVersion and tostring(c.addonVersion) or nil
        end
    end

    if fullyInvalidated then return false end
    if invalidAfter and completedAt and completedAt >= invalidAfter then return false end
    if minCompletionVersion and minCompletionVersion ~= "" then
        if not completionVersion or completionVersion == "" then return false end
        local guildSync = Private.GuildSyncUtils
        if guildSync and guildSync.CompareSemVer then
            local cmp = guildSync:CompareSemVer(completionVersion, minCompletionVersion)
            if cmp == nil or cmp < 0 then return false end
        end
    end

    -- Reset: virtual uncomplete for completions before date or before version
    for _, c in ipairs(list) do
        if c.type == "reset" then
            local match = false
            if c.beforeDate and completedAt and completedAt < tonumber(c.beforeDate) then
                match = true
            end
            if not match and c.beforeVersion and c.beforeVersion ~= "" and completionVersion then
                local guildSync = Private.GuildSyncUtils
                if guildSync and guildSync.CompareSemVer then
                    local cmp = guildSync:CompareSemVer(completionVersion, c.beforeVersion)
                    if cmp ~= nil and cmp < 0 then match = true end
                end
            end
            if match then return false end
        end
    end
    return true
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

---@return string
function correctionSync:GenerateCorrectionId()
    local t = ToBase36(time() or 0)
    local r1 = ToBase36(math.random(0, 36 * 36 * 36 - 1))
    local r2 = ToBase36(math.random(0, 36 * 36 - 1))
    local id = t .. "-" .. r1 .. r2
    while self.corrections[id] do
        r1 = ToBase36(math.random(0, 36 * 36 * 36 - 1))
        r2 = ToBase36(math.random(0, 36 * 36 - 1))
        id = t .. "-" .. r1 .. r2
    end
    return id
end

---@param achievementId number
---@param correctionType "full_invalidate"|"invalidate_from_date"|"revalidate"|"cancel"|"reset"
---@param opts table|nil { fromDate?, addonVersion?, effectiveAt?, targetCorrectionId?, beforeDate?, beforeVersion?, mode? }
---@return AchievementCorrection|nil
function correctionSync:CreateCorrection(achievementId, correctionType, opts)
    if not IsAdmin() then return nil end
    if not IsInGuildSafe() then return nil end

    opts = opts or {}
    if correctionType == "cancel" then
        local targetId = opts.targetCorrectionId and tostring(opts.targetCorrectionId) or nil
        if not targetId or targetId == "" then return nil end
        self:EnsureCorrectionsBound()
        local target = self.corrections[targetId]
        if not target or type(target) ~= "table" or IsCorrectionVoided(target) or target.type == "cancel" then
            return nil
        end
        achievementId = tonumber(target.achievementId) or 0
        if not achievementId then return nil end
    else
        achievementId = tonumber(achievementId)
        if not achievementId then return nil end
        if correctionType ~= "full_invalidate" and correctionType ~= "invalidate_from_date" and correctionType ~= "revalidate" and correctionType ~= "reset" then
            return nil
        end
        if correctionType == "reset" then
            local bd = opts.beforeDate and tonumber(opts.beforeDate)
            local bv = opts.beforeVersion and tostring(opts.beforeVersion)
            if (not bd or bd <= 0) and (not bv or bv == "") then return nil end
        end
    end

    self:EnsureCorrectionsBound()
    local now = time()
    local id = self:GenerateCorrectionId()

    local correction = {
        id = id,
        achievementId = achievementId,
        type = correctionType,
        issuedBy = GetPlayerShortName() or "Officer",
        issuedAt = now,
        fromDate = correctionType == "invalidate_from_date" and (tonumber(opts.fromDate) or now) or nil,
        addonVersion = correctionType == "revalidate" and (tostring(opts.addonVersion or "") or (const and const.ADDON_VERSION)) or nil,
        effectiveAt = correctionType == "revalidate" and (tonumber(opts.effectiveAt) or now) or nil,
        targetCorrectionId = correctionType == "cancel" and (opts.targetCorrectionId and tostring(opts.targetCorrectionId)) or nil,
        beforeDate = correctionType == "reset" and tonumber(opts.beforeDate) or nil,
        beforeVersion = correctionType == "reset" and (opts.beforeVersion and tostring(opts.beforeVersion)) or nil,
        mode = correctionType == "reset" and (opts.mode == "uncomplete" and "uncomplete" or "points") or nil,
    }

    self.corrections[id] = correction
    if correctionType == "cancel" and correction.targetCorrectionId then
        local t = self.corrections[correction.targetCorrectionId]
        if t then t.revertedByCorrectionId = id end
    end
    self:SaveCachedCorrections()
    return correction
end

---@param correction AchievementCorrection
function correctionSync:BroadcastCorrection(correction)
    if not correction or type(correction.id) ~= "string" then return end
    self:SendGuildMessage(MSG_TYPE.CREATE, { correction = correction }, "NORMAL")
end

function correctionSync:GetCorrections()
    self:EnsureCorrectionsBound()
    return self.corrections or {}
end

---@param c table correction record
---@return boolean true if this correction is voided (canceled/reverted)
function correctionSync:IsCorrectionVoided(c)
    return IsCorrectionVoided(c)
end

---@param achievementId number
---@return AchievementCorrection[]
function correctionSync:GetCorrectionsForAchievement(achievementId)
    local out = {}
    for _, c in pairs(self:GetCorrections()) do
        if type(c) == "table" and c.achievementId == achievementId then
            out[#out + 1] = c
        end
    end
    table.sort(out, function(a, b)
        return (tonumber(a.issuedAt) or 0) > (tonumber(b.issuedAt) or 0)
    end)
    return out
end

function correctionSync:WipeAllCorrections()
    self.corrections = {}
    self:SaveCachedCorrections()
end

--- Cancel a prior correction (void it). Creates and broadcasts a "cancel" correction.
---@param targetCorrectionId string
---@return AchievementCorrection|nil the new cancel correction, or nil on failure
function correctionSync:CancelCorrection(targetCorrectionId)
    if not IsAdmin() then return nil end
    if not IsInGuildSafe() then return nil end
    targetCorrectionId = tostring(targetCorrectionId or "")
    if targetCorrectionId == "" then return nil end

    local newC = self:CreateCorrection(0, "cancel", { targetCorrectionId = targetCorrectionId })
    if not newC then return nil end
    self:BroadcastCorrection(newC)
    return newC
end

function correctionSync:IsAdmin()
    return IsAdmin()
end

-------------------------------------------------------------------------------
-- Message handlers
-------------------------------------------------------------------------------

function correctionSync:RegisterMessageHandlers()
    local comms = Private.CommsUtils
    if not comms then return end
    comms:AddCallback(MSG_TYPE.CREATE, function(data) self:OnCorrectionCreate(data) end)
    comms:AddCallback(MSG_TYPE.REQ, function(data) self:OnCorrectionRequest(data) end)
    comms:AddCallback(MSG_TYPE.RESP, function(data) self:OnCorrectionResponse(data) end)
end

function correctionSync:OnCorrectionCreate(data)
    if not data or not data.correction then return end
    if not IsInGuildSafe() then return end

    local c = data.correction
    if type(c) ~= "table" or type(c.id) ~= "string" then return end

    self:EnsureCorrectionsBound()
    self.corrections[c.id] = {
        id = c.id,
        achievementId = tonumber(c.achievementId) or 0,
        type = c.type or "full_invalidate",
        issuedBy = tostring(c.issuedBy or ""),
        issuedAt = tonumber(c.issuedAt) or time(),
        fromDate = c.fromDate and tonumber(c.fromDate) or nil,
        addonVersion = c.addonVersion and tostring(c.addonVersion) or nil,
        effectiveAt = c.effectiveAt and tonumber(c.effectiveAt) or nil,
        revertedByCorrectionId = c.revertedByCorrectionId and tostring(c.revertedByCorrectionId) or nil,
        revertsCorrectionId = c.revertsCorrectionId and tostring(c.revertsCorrectionId) or nil,
        targetCorrectionId = c.targetCorrectionId and tostring(c.targetCorrectionId) or nil,
        beforeDate = c.beforeDate and tonumber(c.beforeDate) or nil,
        beforeVersion = c.beforeVersion and tostring(c.beforeVersion) or nil,
        mode = c.mode and tostring(c.mode) or nil,
    }
    if c.type == "cancel" and c.targetCorrectionId then
        local origId = tostring(c.targetCorrectionId)
        if self.corrections[origId] then
            self.corrections[origId].revertedByCorrectionId = c.id
        end
    elseif c.revertsCorrectionId then
        local origId = tostring(c.revertsCorrectionId)
        if self.corrections[origId] then
            self.corrections[origId].revertedByCorrectionId = c.id
        end
    end
    self:SaveCachedCorrections()
end

function correctionSync:RequestCorrections()
    if not IsAdmin() then return end
    if not IsInGuildSafe() then return end
    local now = time()
    if (now - (self.lastRequestAt or 0)) < (self.REQUEST_COOLDOWN or 60) then return end
    self.lastRequestAt = now
    self:SendGuildMessage(MSG_TYPE.REQ, {
        requester = GetPlayerShortName() or "Admin",
        requestId = tostring(now) .. "-" .. tostring(math.random(100000, 999999)),
    }, "NORMAL")
end

function correctionSync:OnCorrectionRequest(data)
    if not data or not data.requestId then return end
    if not IsInGuildSafe() then return end
    self:EnsureCorrectionsBound()
    local list = {}
    for _, c in pairs(self.corrections or {}) do
        if type(c) == "table" then list[#list + 1] = c end
    end
    if #list == 0 then return end
    self:SendGuildMessage(MSG_TYPE.RESP, {
        requestId = data.requestId,
        corrections = list,
        timestamp = time(),
    }, "NORMAL")
end

function correctionSync:OnCorrectionResponse(data)
    if not data or not data.corrections then return end
    if not IsInGuildSafe() then return end
    self:EnsureCorrectionsBound()
    for _, c in ipairs(data.corrections) do
        if type(c) == "table" and type(c.id) == "string" then
            self.corrections[c.id] = {
                id = c.id,
                achievementId = tonumber(c.achievementId) or 0,
                type = c.type or "full_invalidate",
                issuedBy = tostring(c.issuedBy or ""),
                issuedAt = tonumber(c.issuedAt) or time(),
                fromDate = c.fromDate and tonumber(c.fromDate) or nil,
                addonVersion = c.addonVersion and tostring(c.addonVersion) or nil,
                effectiveAt = c.effectiveAt and tonumber(c.effectiveAt) or nil,
                revertedByCorrectionId = c.revertedByCorrectionId and tostring(c.revertedByCorrectionId) or nil,
                revertsCorrectionId = c.revertsCorrectionId and tostring(c.revertsCorrectionId) or nil,
                targetCorrectionId = c.targetCorrectionId and tostring(c.targetCorrectionId) or nil,
                beforeDate = c.beforeDate and tonumber(c.beforeDate) or nil,
                beforeVersion = c.beforeVersion and tostring(c.beforeVersion) or nil,
                mode = c.mode and tostring(c.mode) or nil,
            }
            if c.type == "cancel" and c.targetCorrectionId then
                local origId = tostring(c.targetCorrectionId)
                if self.corrections[origId] then
                    self.corrections[origId].revertedByCorrectionId = c.id
                end
            elseif c.revertsCorrectionId then
                local origId = tostring(c.revertsCorrectionId)
                if self.corrections[origId] then
                    self.corrections[origId].revertedByCorrectionId = c.id
                end
            end
        end
    end
    self:SaveCachedCorrections()
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------

function correctionSync:Init()
    self:LoadCachedCorrections()
    self:RegisterMessageHandlers()
end
