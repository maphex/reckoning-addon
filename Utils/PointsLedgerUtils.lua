---@class AddonPrivate
local Private = select(2, ...)

local const = Private.constants

-------------------------------------------------------------------------------
-- Points Ledger (OnlyFangs-style)
-- - Transaction-based manual point adjustments (add/subtract)
-- - Idempotent by transaction ID
-- - Broadcast to guild; snapshot request/response for catch-up
-- - Stored in guildCache.pointsLedger (per-guild), targeted per-character (short name)
-------------------------------------------------------------------------------

---@class PointsLedgerTransaction
---@field id string
---@field targetPlayer string
---@field delta number
---@field reason string|nil
---@field issuedBy string
---@field issuedAt number

---@class PointsLedgerUtils
local pointsLedger = {
    ---@type table<string, PointsLedgerTransaction> id -> tx (bound to SavedVariables)
    ledger = {},
    ---@type table<string, table<string, table>> senderShort -> requestId -> state
    pendingChunks = {},
    ---@type number
    lastRequestAt = 0,
    ---@type number
    REQUEST_COOLDOWN = 30,
}
Private.PointsLedgerUtils = pointsLedger

local MSG_TYPE = {
    TX = "GPL_TX",         -- Single transaction broadcast (GUILD)
    REQ = "GPL_REQ",        -- Request snapshot (GUILD)
    CHUNK = "GPL_CHNK",     -- Chunked snapshot response (WHISPER)
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function Trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function GetPlayerShortName()
    if type(UnitName) ~= "function" then return nil end
    local name = UnitName("player")
    if not name or name == "" then return nil end
    return tostring(name):match("^([^%-]+)") or tostring(name)
end

local function ShortName(name)
    if type(name) ~= "string" then return nil end
    if name == "" then return nil end
    return tostring(name):match("^([^%-]+)") or tostring(name)
end

local function IsInGuildSafe()
    return type(IsInGuild) == "function" and IsInGuild() == true
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

local function PackTx(tx)
    if type(tx) ~= "table" then return nil end
    return {
        i = tx.id,
        t = tx.targetPlayer,
        d = tx.delta,
        r = tx.reason,
        b = tx.issuedBy,
        a = tx.issuedAt,
    }
end

local function UnpackTx(packed)
    if type(packed) ~= "table" then return nil end
    local id = packed.i and tostring(packed.i) or nil
    local target = packed.t and tostring(packed.t) or nil
    local delta = tonumber(packed.d)
    local issuedBy = packed.b and tostring(packed.b) or nil
    local issuedAt = tonumber(packed.a)
    if not id or id == "" then return nil end
    if not target or target == "" then return nil end
    if not delta or delta == 0 then return nil end
    if not issuedBy or issuedBy == "" then return nil end
    if not issuedAt or issuedAt <= 0 then return nil end
    local reason = packed.r
    if reason ~= nil then reason = tostring(reason) end
    return {
        id = id,
        targetPlayer = target,
        delta = delta,
        reason = reason,
        issuedBy = issuedBy,
        issuedAt = issuedAt,
    }
end

-------------------------------------------------------------------------------
-- Auth / Admin checks
-------------------------------------------------------------------------------

function pointsLedger:IsAdmin()
    local ts = Private.TicketSyncUtils
    if ts and ts.IsAdmin then
        return ts:IsAdmin() == true
    end

    if not IsInGuildSafe() then return false end
    if type(GetGuildInfo) ~= "function" then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    rankIndex = tonumber(rankIndex)
    return rankIndex ~= nil and rankIndex <= 1
end

local function IsSenderAdminByRoster(senderShort)
    if not IsInGuildSafe() then return false end
    if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
        return false
    end
    senderShort = ShortName(senderShort)
    if not senderShort then return false end
    local num = GetNumGuildMembers()
    for i = 1, num do
        local fullName, _, rankIndex = GetGuildRosterInfo(i)
        local short = fullName and ShortName(fullName)
        if short == senderShort then
            rankIndex = tonumber(rankIndex)
            return rankIndex ~= nil and rankIndex <= 1
        end
    end
    return false
end

-------------------------------------------------------------------------------
-- Persistence
-------------------------------------------------------------------------------

function pointsLedger:EnsureLedgerBound()
    local addon = Private.Addon
    if not addon or not addon.Database then return end
    local db = addon.Database
    db.guildCache = db.guildCache or {}
    db.guildCache.pointsLedger = db.guildCache.pointsLedger or {}
    self.ledger = db.guildCache.pointsLedger
end

function pointsLedger:WipeAllTransactions()
    self:EnsureLedgerBound()
    for k in pairs(self.ledger or {}) do
        self.ledger[k] = nil
    end

    local addon = Private.Addon
    if addon and addon.Database and addon.Database.guildCache then
        addon.Database.guildCache.pointsLedgerSavedAt = time()
    end

    local gs = Private.GuildSyncUtils
    if gs and gs.NotifyUIUpdate then
        gs:NotifyUIUpdate()
    end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function pointsLedger:GenerateTransactionId()
    self:EnsureLedgerBound()
    local t = ToBase36(time() or 0)
    local r1 = ToBase36(math.random(0, 36 * 36 * 36 - 1))
    local r2 = ToBase36(math.random(0, 36 * 36 - 1))
    local id = t .. "-" .. r1 .. r2
    while self.ledger and self.ledger[id] do
        r1 = ToBase36(math.random(0, 36 * 36 * 36 - 1))
        r2 = ToBase36(math.random(0, 36 * 36 - 1))
        id = t .. "-" .. r1 .. r2
    end
    return id
end

---@param targetPlayer string
---@param delta number
---@param reason string|nil
---@return PointsLedgerTransaction|nil
function pointsLedger:CreateTransaction(targetPlayer, delta, reason)
    if not self:IsAdmin() then return nil end
    if not IsInGuildSafe() then return nil end

    self:EnsureLedgerBound()

    local target = ShortName(targetPlayer)
    if not target or target == "" then return nil end

    delta = tonumber(delta)
    if not delta or delta == 0 then return nil end
    delta = math.floor(delta)
    if delta == 0 then return nil end

    reason = Trim(reason or "")
    if reason == "" then reason = nil end
    if reason and #reason > 96 then
        reason = reason:sub(1, 96)
    end

    local now = time()
    local tx = {
        id = self:GenerateTransactionId(),
        targetPlayer = target,
        delta = delta,
        reason = reason,
        issuedBy = GetPlayerShortName() or "Officer",
        issuedAt = now,
    }

    -- Idempotent insert (local create always new, but keep semantics consistent)
    if not self.ledger[tx.id] then
        self.ledger[tx.id] = tx
    end

    local addon = Private.Addon
    if addon and addon.Database and addon.Database.guildCache then
        addon.Database.guildCache.pointsLedgerSavedAt = now
    end

    self:BroadcastTransaction(tx)

    local gs = Private.GuildSyncUtils
    if gs and gs.NotifyUIUpdate then
        gs:NotifyUIUpdate()
    end

    return tx
end

---@param shortName string
---@return number
function pointsLedger:SumAdjustmentsForPlayer(shortName)
    self:EnsureLedgerBound()
    shortName = ShortName(shortName)
    if not shortName then return 0 end
    local sum = 0
    for _, tx in pairs(self.ledger or {}) do
        if type(tx) == "table" and tx.targetPlayer == shortName then
            sum = sum + (tonumber(tx.delta) or 0)
        end
    end
    return sum
end

---@param targetPlayer? string
---@return PointsLedgerTransaction[]
function pointsLedger:GetLedgerHistory(targetPlayer)
    self:EnsureLedgerBound()
    local target = targetPlayer and ShortName(targetPlayer) or nil
    local out = {}
    for _, tx in pairs(self.ledger or {}) do
        if type(tx) == "table" and tx.id then
            if not target or tx.targetPlayer == target then
                out[#out + 1] = tx
            end
        end
    end
    table.sort(out, function(a, b)
        local at = tonumber(a.issuedAt) or 0
        local bt = tonumber(b.issuedAt) or 0
        if at ~= bt then return at > bt end
        return tostring(a.id or "") > tostring(b.id or "")
    end)
    return out
end

-------------------------------------------------------------------------------
-- Comms
-------------------------------------------------------------------------------

function pointsLedger:BroadcastTransaction(tx)
    local comms = Private.CommsUtils
    if not comms or not comms.SendMessage then return end
    if not IsInGuildSafe() then return end

    local payload = {
        tx = PackTx(tx),
        protocolVersion = const and const.ADDON_COMMS and const.ADDON_COMMS.PROTOCOL_VERSION or 1,
        timestamp = time(),
        priority = "NORMAL",
    }
    comms:SendMessage(MSG_TYPE.TX, payload, "GUILD")
end

function pointsLedger:RequestLedgerSnapshot()
    if not IsInGuildSafe() then return end
    local now = time()
    if (now - (tonumber(self.lastRequestAt) or 0)) < (tonumber(self.REQUEST_COOLDOWN) or 30) then
        return
    end
    self.lastRequestAt = now

    self:EnsureLedgerBound()

    local comms = Private.CommsUtils
    if not comms or not comms.SendMessage then return end

    comms:SendMessage(MSG_TYPE.REQ, {
        requestId = self:GenerateTransactionId(),
        knownCount = (function()
            local c = 0
            for _ in pairs(self.ledger or {}) do c = c + 1 end
            return c
        end)(),
        protocolVersion = const and const.ADDON_COMMS and const.ADDON_COMMS.PROTOCOL_VERSION or 1,
        timestamp = now,
        priority = "BULK",
    }, "GUILD")
end

function pointsLedger:OnPlayerLogin()
    -- Ask the guild for a snapshot so multi-PC / offline clients converge.
    self:RequestLedgerSnapshot()
end

local function EncodeIfFits(comms, subPrefix, payload)
    payload.subPrefix = subPrefix
    local encoded = comms:Encode(payload)
    if not encoded then return nil end
    if #encoded > 255 then return nil end
    return encoded
end

function pointsLedger:SendLedgerSnapshotChunked(requestId, target)
    if not requestId or requestId == "" then return end
    if not target or target == "" then return end
    self:EnsureLedgerBound()

    local comms = Private.CommsUtils
    if not comms or not comms.Encode or not comms.SendEncodedMessage then return end

    local ids = {}
    for id in pairs(self.ledger or {}) do
        ids[#ids + 1] = id
    end
    table.sort(ids)

    local idx = 1
    local seq = 1

    while idx <= #ids do
        local slice = {}
        local take = 0
        local lastGoodEncoded = nil

        while (idx + take) <= #ids do
            local id = ids[idx + take]
            local tx = self.ledger[id]
            slice[id] = PackTx(tx)

            local isLast = ((idx + take) == #ids)
            local payload = {
                requestId = requestId,
                seq = seq,
                last = isLast or nil,
                tx = slice,
                protocolVersion = const and const.ADDON_COMMS and const.ADDON_COMMS.PROTOCOL_VERSION or 1,
                timestamp = time(),
                priority = "BULK",
            }
            local encoded = EncodeIfFits(comms, MSG_TYPE.CHUNK, payload)
            if encoded then
                lastGoodEncoded = encoded
                take = take + 1
            else
                slice[id] = nil
                break
            end
        end

        if take <= 0 then
            -- Single tx too large; retry without reason
            local id = ids[idx]
            local tx = self.ledger[id]
            local packed = PackTx(tx)
            if packed then packed.r = nil end
            slice = { [id] = packed }
            local isLast = (idx == #ids)
            local payload = {
                requestId = requestId,
                seq = seq,
                last = isLast or nil,
                tx = slice,
                protocolVersion = const and const.ADDON_COMMS and const.ADDON_COMMS.PROTOCOL_VERSION or 1,
                timestamp = time(),
                priority = "BULK",
            }
            local encoded = EncodeIfFits(comms, MSG_TYPE.CHUNK, payload)
            if not encoded then
                -- Give up on this tx to avoid stalling the snapshot.
                idx = idx + 1
                seq = seq + 1
            else
                comms:SendEncodedMessage(MSG_TYPE.CHUNK, encoded, "WHISPER", target, "BULK")
                idx = idx + 1
                seq = seq + 1
            end
        else
            if lastGoodEncoded then
                comms:SendEncodedMessage(MSG_TYPE.CHUNK, lastGoodEncoded, "WHISPER", target, "BULK")
            end
            idx = idx + take
            seq = seq + 1
        end
    end

    if #ids == 0 then
        -- Still send an empty \"last\" so the requester can complete quickly.
        local encoded = EncodeIfFits(comms, MSG_TYPE.CHUNK, {
            requestId = requestId,
            seq = 1,
            last = true,
            tx = {},
            protocolVersion = const and const.ADDON_COMMS and const.ADDON_COMMS.PROTOCOL_VERSION or 1,
            timestamp = time(),
            priority = "BULK",
        })
        if encoded then
            comms:SendEncodedMessage(MSG_TYPE.CHUNK, encoded, "WHISPER", target, "BULK")
        end
    end
end

function pointsLedger:ApplyTransaction(tx, senderShort)
    if type(tx) ~= "table" or not tx.id then return false end
    self:EnsureLedgerBound()

    if self.ledger[tx.id] then
        return false
    end

    -- Reasonable auth: require issuer to be officer/GM when we can verify via roster.
    if type(GetNumGuildMembers) == "function" and type(GetGuildRosterInfo) == "function" and IsInGuildSafe() then
        local issuerShort = ShortName(tx.issuedBy)
        if issuerShort and issuerShort ~= "" then
            if not IsSenderAdminByRoster(issuerShort) then
                return false
            end
        end
    end

    self.ledger[tx.id] = tx

    local addon = Private.Addon
    if addon and addon.Database and addon.Database.guildCache then
        addon.Database.guildCache.pointsLedgerSavedAt = time()
    end

    local gs = Private.GuildSyncUtils
    if gs and gs.NotifyUIUpdate then
        gs:NotifyUIUpdate()
    end

    return true
end

function pointsLedger:OnTxReceived(data)
    if type(data) ~= "table" then return end
    if not data.tx then return end
    if not IsInGuildSafe() then return end

    local senderShort = ShortName(data.sender)
    if senderShort and senderShort == GetPlayerShortName() then
        return
    end

    if data.protocolVersion and const and const.ADDON_COMMS and data.protocolVersion ~= const.ADDON_COMMS.PROTOCOL_VERSION then
        return
    end

    local tx = UnpackTx(data.tx)
    if not tx then return end
    self:ApplyTransaction(tx, senderShort)
end

function pointsLedger:OnReqReceived(data)
    if type(data) ~= "table" then return end
    if not IsInGuildSafe() then return end

    local sender = data.sender
    local senderShort = ShortName(sender)
    if not senderShort or senderShort == GetPlayerShortName() then
        return
    end
    if not data.requestId then return end
    if data.protocolVersion and const and const.ADDON_COMMS and data.protocolVersion ~= const.ADDON_COMMS.PROTOCOL_VERSION then
        return
    end

    local gs = Private.GuildSyncUtils
    local onlineCount = (gs and gs.CountOnlineMembers and gs:CountOnlineMembers()) or 0
    local shouldRespond = true
    if gs and gs.ShouldRespondToProgressRequest then
        shouldRespond = gs:ShouldRespondToProgressRequest(senderShort, onlineCount)
    end
    if not shouldRespond then
        return
    end

    -- Jitter to avoid bursts
    local delay = math.random(1, 4)
    if type(C_Timer) == "table" and C_Timer.After then
        C_Timer.After(delay, function()
            self:SendLedgerSnapshotChunked(tostring(data.requestId), tostring(sender))
        end)
    else
        self:SendLedgerSnapshotChunked(tostring(data.requestId), tostring(sender))
    end
end

function pointsLedger:OnChunkReceived(data)
    if type(data) ~= "table" then return end
    if not IsInGuildSafe() then return end
    if not data.requestId or not data.seq then return end
    if type(data.tx) ~= "table" then return end
    if data.protocolVersion and const and const.ADDON_COMMS and data.protocolVersion ~= const.ADDON_COMMS.PROTOCOL_VERSION then
        return
    end

    local senderShort = ShortName(data.sender) or "?"
    if senderShort == GetPlayerShortName() then
        return
    end

    local requestId = tostring(data.requestId)
    local seq = tonumber(data.seq) or 0
    if seq <= 0 then return end

    self.pendingChunks[senderShort] = self.pendingChunks[senderShort] or {}
    local state = self.pendingChunks[senderShort][requestId]
    if not state then
        state = {
            received = {},
            lastSeq = nil,
            startedAt = time(),
        }
        self.pendingChunks[senderShort][requestId] = state
    end

    state.received[seq] = data.tx
    if data.last == true then
        state.lastSeq = seq
    end

    if not state.lastSeq then
        return
    end

    -- If we have all chunks up to lastSeq, apply and finalize.
    for i = 1, state.lastSeq do
        if not state.received[i] then
            return
        end
    end

    for i = 1, state.lastSeq do
        local chunkTx = state.received[i]
        for _, packed in pairs(chunkTx) do
            local tx = UnpackTx(packed)
            if tx then
                self:ApplyTransaction(tx, senderShort)
            end
        end
    end

    self.pendingChunks[senderShort][requestId] = nil
    if not next(self.pendingChunks[senderShort]) then
        self.pendingChunks[senderShort] = nil
    end
end

function pointsLedger:Init()
    self:EnsureLedgerBound()

    local comms = Private.CommsUtils
    if not comms or not comms.AddCallback then return end

    comms:AddCallback(MSG_TYPE.TX, function(data)
        self:OnTxReceived(data)
    end)
    comms:AddCallback(MSG_TYPE.REQ, function(data)
        self:OnReqReceived(data)
    end)
    comms:AddCallback(MSG_TYPE.CHUNK, function(data)
        self:OnChunkReceived(data)
    end)
end

