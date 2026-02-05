---@class AddonPrivate
local Private = select(2, ...)

local const = Private.constants

-------------------------------------------------------------------------------
-- Ticket Sync System
-- Parallel to GuildSync heartbeat, but for achievement bug tickets.
-------------------------------------------------------------------------------

---@class AchievementBugTicket
---@field id string
---@field achievementId number
---@field reason string
---@field reporter string
---@field createdAt number
---@field status "open"|"resolved"
---@field ackedAt number|nil
---@field ackedBy string|nil
---@field resolvedAt number|nil
---@field resolvedBy string|nil

---@class TicketSyncUtils
local ticketSync = {
    ---@type table<string, AchievementBugTicket> ticketId -> ticket
    tickets = {},
    ---@type any? ticker handle
    ticker = nil,
    ---@type number
    hbIndex = 0,
    ---@type number
    TICK_SECONDS = 5,
    ---@type number
    EXPIRE_SECONDS = 3 * 24 * 60 * 60, -- 3 days
    ---@type table<string, table<string, any>> sender -> requestId -> state
    pendingChunks = {},
    ---@type table<string, number> requester -> last response time
    lastResponseToRequester = {},
    ---@type number
    RESPONSE_COOLDOWN = 30,
    ---@type number last time we requested full tickets
    lastRequestAt = 0,
    ---@type number
    REQUEST_COOLDOWN = 60,
    ---@type table<number, string>
    _hbIds = {},
    ---@type number
    _hbRebuildAt = 0,
    ---@type number
    _hbCounter = 0,
    ---@type number
    _lastPruneAt = 0,
}
Private.TicketSyncUtils = ticketSync

-- Message types (comms subPrefix)
local MSG_TYPE = {
    CREATE = "GTICK_CREATE",
    HEARTBEAT = "GTICK_HB",
    REQ = "GTICK_REQ",
    RESP = "GTICK_RESP",
    CHUNK = "GTICK_CHUNK",
    ACK = "GTICK_ACK",
    RESOLVE = "GTICK_RESOLVE",
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz"

---@param n number
---@return string
local function ToBase36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local out = {}
    while n > 0 do
        local r = (n % 36) + 1
        out[#out + 1] = BASE36:sub(r, r)
        n = math.floor(n / 36)
    end
    -- reverse
    for i = 1, math.floor(#out / 2) do
        out[i], out[#out - i + 1] = out[#out - i + 1], out[i]
    end
    return table.concat(out)
end

---@return string|nil
local function GetPlayerShortName()
    if type(UnitName) ~= "function" then return nil end
    local name = UnitName("player")
    if not name or name == "" then return nil end
    -- Strip realm if any; classic servers often omit it anyway.
    name = tostring(name):match("^([^%-]+)") or tostring(name)
    return name
end

---@param sender string|nil
---@return string|nil
local function ShortNameFromSender(sender)
    if not sender then return nil end
    if type(strsplit) == "function" then
        local shortName = strsplit("-", sender)
        return shortName
    end
    return tostring(sender):match("^([^%-]+)") or tostring(sender)
end

---@return boolean
local function IsInGuildSafe()
    if type(IsInGuild) ~= "function" then return false end
    return IsInGuild() == true
end

---@return boolean
local function IsAdmin()
    if not IsInGuildSafe() then return false end
    if type(GetGuildInfo) ~= "function" then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    rankIndex = tonumber(rankIndex)
    return rankIndex ~= nil and rankIndex <= 1
end

---@return string|nil
local function GetGuildKey()
    if not IsInGuildSafe() then return nil end
    if type(GetGuildInfo) ~= "function" then return nil end
    local guildName = GetGuildInfo("player")
    if not guildName or guildName == "" then return nil end
    local realm = (type(GetRealmName) == "function") and GetRealmName() or ""
    return tostring(guildName) .. "@" .. tostring(realm)
end

---@param s string|nil
---@return string
local function ClampReason(s)
    s = tostring(s or "")
    -- Normalize whitespace a bit; keep it short for comms.
    s = s:gsub("[%c\r\n\t]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #s > 140 then
        s = s:sub(1, 140)
    end
    return s
end

---@return string
function ticketSync:GenerateTicketId()
    -- Short, mostly-unique, comms-safe ID.
    -- base36(time) + base36(random) + base36(random)
    local t = ToBase36(time() or 0)
    local r1 = ToBase36(math.random(0, 36 ^ 3 - 1))
    local r2 = ToBase36(math.random(0, 36 ^ 2 - 1))
    local id = (t .. r1 .. r2):lower()
    -- Ensure uniqueness locally (extremely unlikely collision, but cheap to guard).
    while self.tickets[id] do
        r1 = ToBase36(math.random(0, 36 ^ 3 - 1))
        r2 = ToBase36(math.random(0, 36 ^ 2 - 1))
        id = (t .. r1 .. r2):lower()
    end
    return id
end

---@param ticket AchievementBugTicket
---@return boolean
function ticketSync:IsExpiredUnacked(ticket)
    if not ticket or ticket.ackedAt then return false end
    local createdAt = tonumber(ticket.createdAt) or 0
    if createdAt <= 0 then return true end
    return (time() - createdAt) >= (self.EXPIRE_SECONDS or (3 * 24 * 60 * 60))
end

---@param ticket AchievementBugTicket
---@return AchievementBugTicket
local function NormalizeTicket(ticket)
    ticket.achievementId = tonumber(ticket.achievementId) or 0
    ticket.createdAt = tonumber(ticket.createdAt) or 0
    ticket.ackedAt = tonumber(ticket.ackedAt) or nil
    ticket.resolvedAt = tonumber(ticket.resolvedAt) or nil
    ticket.reason = ClampReason(ticket.reason)
    ticket.reporter = tostring(ticket.reporter or "Player")
    ticket.status = ticket.status == "resolved" and "resolved" or "open"
    return ticket
end

---@param incoming AchievementBugTicket
function ticketSync:UpsertTicket(incoming)
    if not incoming or type(incoming.id) ~= "string" then return end
    local id = incoming.id
    incoming = NormalizeTicket(incoming)

    local existing = self.tickets[id]
    if not existing then
        self.tickets[id] = incoming
        return
    end

    -- Merge: keep earliest createdAt, and prefer resolved/acked info if present.
    existing.achievementId = tonumber(existing.achievementId) or incoming.achievementId
    existing.reason = existing.reason or incoming.reason
    existing.reporter = existing.reporter or incoming.reporter
    existing.createdAt = math.min(tonumber(existing.createdAt) or incoming.createdAt, incoming.createdAt)

    if incoming.ackedAt and (not existing.ackedAt or incoming.ackedAt < existing.ackedAt) then
        existing.ackedAt = incoming.ackedAt
        existing.ackedBy = incoming.ackedBy
    end

    if incoming.status == "resolved" or existing.status == "resolved" then
        existing.status = "resolved"
        existing.resolvedAt = incoming.resolvedAt or existing.resolvedAt
        existing.resolvedBy = incoming.resolvedBy or existing.resolvedBy
    end
end

-------------------------------------------------------------------------------
-- Persistence
-------------------------------------------------------------------------------

--- Re-bind self.tickets to the current addon DB so we always read/write the live table.
--- Call before reading or writing tickets so officers see their own newly created tickets.
function ticketSync:EnsureTicketsBound()
    local addon = Private.Addon
    if not addon or not addon.Database then return end
    local db = addon.Database
    db.guildCache = db.guildCache or {}
    db.guildCache.tickets = db.guildCache.tickets or {}
    self.tickets = db.guildCache.tickets
end

function ticketSync:LoadCachedTickets()
    self:EnsureTicketsBound()
end

function ticketSync:SaveCachedTickets()
    local addon = Private.Addon
    if not addon or not addon.Database then return end
    addon.Database.guildCache = addon.Database.guildCache or {}
    addon.Database.guildCache.tickets = self.tickets or {}
    addon.Database.guildCache.ticketsSavedAt = time()
end

-------------------------------------------------------------------------------
-- Comms
-------------------------------------------------------------------------------

---@param subPrefix string
---@param payload table
---@param priority? "BULK"|"NORMAL"|"ALERT"
function ticketSync:SendGuildMessage(subPrefix, payload, priority)
    local comms = Private.CommsUtils
    if not comms then return end
    if not IsInGuildSafe() then return end
    payload.subPrefix = subPrefix
    payload.protocolVersion = const and const.ADDON_COMMS and const.ADDON_COMMS.PROTOCOL_VERSION or 1
    payload.timestamp = payload.timestamp or time()
    if priority then
        payload.priority = priority
    end

    local encoded = comms:Encode(payload)
    if not encoded then return end

    if #encoded <= 255 then
        comms:SendEncodedMessage(subPrefix, encoded, "GUILD", nil, priority or "NORMAL")
        return
    end

    -- Oversized. For ticket create, shrink reason until it fits.
    if payload.ticket and type(payload.ticket) == "table" and type(payload.ticket.reason) == "string" then
        local reason = payload.ticket.reason
        local max = math.min(#reason, 140)
        while max >= 20 do
            payload.ticket.reason = reason:sub(1, max)
            encoded = comms:Encode(payload)
            if encoded and #encoded <= 255 then
                comms:SendEncodedMessage(subPrefix, encoded, "GUILD", nil, priority or "NORMAL")
                return
            end
            max = max - 10
        end
    end
end

function ticketSync:RegisterMessageHandlers()
    local comms = Private.CommsUtils
    if not comms then return end

    comms:AddCallback(MSG_TYPE.CREATE, function(data) self:OnTicketCreate(data) end)
    comms:AddCallback(MSG_TYPE.ACK, function(data) self:OnTicketAck(data) end)
    comms:AddCallback(MSG_TYPE.RESOLVE, function(data) self:OnTicketResolve(data) end)
    comms:AddCallback(MSG_TYPE.REQ, function(data) self:OnTicketRequest(data) end)
    comms:AddCallback(MSG_TYPE.RESP, function(data) self:OnTicketResponse(data) end)
    comms:AddCallback(MSG_TYPE.CHUNK, function(data) self:OnTicketChunk(data) end)
    comms:AddCallback(MSG_TYPE.HEARTBEAT, function(data) self:OnTicketHeartbeat(data) end)
end

---@param data table|nil
function ticketSync:OnTicketCreate(data)
    if not data or not data.ticket then return end
    if not IsInGuildSafe() then return end

    local senderShort = ShortNameFromSender(data.sender) or (data.ticket and data.ticket.reporter)
    if senderShort and type(UnitName) == "function" and senderShort == UnitName("player") then
        return
    end

    local ticket = data.ticket
    if type(ticket) ~= "table" or type(ticket.id) ~= "string" then return end

    -- Ignore brand-new unacked tickets that are already expired (non-admin policy).
    if not IsAdmin() and self:IsExpiredUnacked(ticket) then
        return
    end

    self:UpsertTicket(ticket)
    self:SaveCachedTickets()

    -- Admin auto-ACKs on first receipt, so non-admins can stop relaying.
    if IsAdmin() then
        self:SendGuildMessage(MSG_TYPE.ACK, {
            ticketId = ticket.id,
            ackedAt = time(),
            ackedBy = GetPlayerShortName() or (type(UnitName) == "function" and UnitName("player")) or "Admin",
        }, "NORMAL")
    end
end

---@param data table|nil
function ticketSync:OnTicketAck(data)
    if not data or not data.ticketId then return end
    if not IsInGuildSafe() then return end

    local id = tostring(data.ticketId)
    local ticket = self.tickets[id]
    if not ticket then
        -- Create a minimal placeholder so we can stop relaying if we later receive the full ticket.
        ticket = { id = id, achievementId = 0, reason = "", reporter = "", createdAt = tonumber(data.timestamp) or time(), status = "open" }
        self.tickets[id] = ticket
    end

    ticket.ackedAt = tonumber(data.ackedAt) or time()
    ticket.ackedBy = tostring(data.ackedBy or "")
    self:SaveCachedTickets()
end

---@param data table|nil
function ticketSync:OnTicketResolve(data)
    if not data or not data.ticketId then return end
    if not IsInGuildSafe() then return end

    local id = tostring(data.ticketId)
    local ticket = self.tickets[id]
    if not ticket then
        return
    end

    ticket.status = "resolved"
    ticket.resolvedAt = tonumber(data.resolvedAt) or time()
    ticket.resolvedBy = tostring(data.resolvedBy or "")
    self:SaveCachedTickets()

    -- Non-admins don't need to retain resolved tickets; remove to keep DB small.
    if not IsAdmin() then
        self.tickets[id] = nil
        self:SaveCachedTickets()
    end
end

---@param data table|nil
function ticketSync:OnTicketRequest(data)
    if not data then return end
    if not IsInGuildSafe() then return end

    local requester = data.sender or data.requester
    if not requester then return end

    local now = time()
    if self.lastResponseToRequester[requester] and (now - self.lastResponseToRequester[requester]) < (self.RESPONSE_COOLDOWN or 30) then
        return
    end
    self.lastResponseToRequester[requester] = now

    local requestId = tostring(data.requestId or (tostring(now) .. "-" .. tostring(math.random(100000, 999999))))
    self:SendTicketsResponse(requestId)
end

---@param requestId string
function ticketSync:SendTicketsResponse(requestId)
    local comms = Private.CommsUtils
    if not comms then return end
    if not IsInGuildSafe() then return end

    local now = time()
    local myName = GetPlayerShortName() or (type(UnitName) == "function" and UnitName("player")) or "Player"

    local tickets = {}
    for id, t in pairs(self.tickets or {}) do
        if type(t) == "table" and t.status ~= "resolved" then
            -- Non-admins only share unacked and unexpired.
            if not IsAdmin() then
                if not t.ackedAt and not self:IsExpiredUnacked(t) then
                    tickets[#tickets + 1] = t
                end
            else
                -- Admins share open tickets they know about (acked or still within expiry window).
                if t.ackedAt or not self:IsExpiredUnacked(t) then
                    tickets[#tickets + 1] = t
                end
            end
        end
    end

    -- Attempt single response; otherwise chunk by single-ticket chunks.
    local payload = {
        subPrefix = MSG_TYPE.RESP,
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        requestId = requestId,
        responder = myName,
        tickets = tickets,
        timestamp = now,
    }

    local encoded = comms:Encode(payload)
    if encoded and #encoded <= 255 then
        comms:SendEncodedMessage(MSG_TYPE.RESP, encoded, "GUILD", nil, "NORMAL")
        return
    end

    local seq = 1
    for i = 1, #tickets do
        local chunkPayload = {
            subPrefix = MSG_TYPE.CHUNK,
            protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
            requestId = requestId,
            seq = seq,
            isLast = (i == #tickets),
            responder = myName,
            tickets = { tickets[i] },
            timestamp = now,
        }
        encoded = comms:Encode(chunkPayload)
        if encoded and #encoded <= 255 then
            comms:SendEncodedMessage(MSG_TYPE.CHUNK, encoded, "GUILD", nil, "BULK")
            seq = seq + 1
        end
    end

    -- Edge case: no tickets, send empty last chunk so requesters learn "none".
    if #tickets == 0 then
        local empty = {
            subPrefix = MSG_TYPE.CHUNK,
            protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
            requestId = requestId,
            seq = 1,
            isLast = true,
            responder = myName,
            tickets = {},
            timestamp = now,
        }
        encoded = comms:Encode(empty)
        if encoded and #encoded <= 255 then
            comms:SendEncodedMessage(MSG_TYPE.CHUNK, encoded, "GUILD", nil, "BULK")
        end
    end
end

---@param data table|nil
function ticketSync:OnTicketResponse(data)
    if not data or not data.requestId then return end
    if not IsInGuildSafe() then return end
    if type(data.tickets) ~= "table" then return end

    for _, t in ipairs(data.tickets) do
        if type(t) == "table" then
            if not IsAdmin() and self:IsExpiredUnacked(t) then
                -- ignore
            else
                self:UpsertTicket(t)
            end
        end
    end
    self:SaveCachedTickets()
end

---@param data table|nil
function ticketSync:OnTicketChunk(data)
    if not data or not data.requestId or not data.sender then return end
    if not IsInGuildSafe() then return end

    local sender = tostring(data.sender)
    local requestId = tostring(data.requestId)
    local seq = tonumber(data.seq) or 0
    if seq <= 0 then return end

    self.pendingChunks[sender] = self.pendingChunks[sender] or {}
    local state = self.pendingChunks[sender][requestId]
    if not state then
        state = {
            startedAt = time(),
            lastUpdate = time(),
            received = {},
            tickets = {},
            lastSeq = nil,
        }
        self.pendingChunks[sender][requestId] = state
    end

    state.lastUpdate = time()
    if state.received[seq] then
        return
    end
    state.received[seq] = true

    if type(data.tickets) == "table" then
        for _, t in ipairs(data.tickets) do
            if type(t) == "table" then
                state.tickets[#state.tickets + 1] = t
            end
        end
    end

    if data.isLast then
        state.lastSeq = seq
    end

    -- Finalize if lastSeq is known and all chunks are received
    if state.lastSeq then
        for i = 1, state.lastSeq do
            if not state.received[i] then
                return
            end
        end

        for _, t in ipairs(state.tickets) do
            if type(t) == "table" then
                if not IsAdmin() and self:IsExpiredUnacked(t) then
                    -- ignore
                else
                    self:UpsertTicket(t)
                end
            end
        end

        self.pendingChunks[sender][requestId] = nil
        if not next(self.pendingChunks[sender]) then
            self.pendingChunks[sender] = nil
        end

        self:SaveCachedTickets()
    end
end

function ticketSync:CleanupPendingChunks()
    local now = time()
    local timeout = 60
    for sender, requests in pairs(self.pendingChunks) do
        for requestId, state in pairs(requests) do
            local lastUpdate = state.lastUpdate or state.startedAt or now
            if (now - lastUpdate) > timeout then
                requests[requestId] = nil
            end
        end
        if not next(requests) then
            self.pendingChunks[sender] = nil
        end
    end
end

---@param data table|nil
function ticketSync:OnTicketHeartbeat(data)
    -- Wired in ticket-heartbeat todo; for now accept heartbeat payloads that contain tickets.
    if not data or type(data.tickets) ~= "table" then return end
    if not IsInGuildSafe() then return end

    for _, t in ipairs(data.tickets) do
        if type(t) == "table" then
            if not IsAdmin() and self:IsExpiredUnacked(t) then
                -- ignore
            else
                self:UpsertTicket(t)
            end
        end
    end
    self:SaveCachedTickets()

    if IsAdmin() then
        -- Admins ACK on first sight of any unacked ticket in heartbeat.
        for _, t in ipairs(data.tickets) do
            if type(t) == "table" and t.id and not t.ackedAt then
                self:SendGuildMessage(MSG_TYPE.ACK, {
                    ticketId = tostring(t.id),
                    ackedAt = time(),
                    ackedBy = GetPlayerShortName() or (type(UnitName) == "function" and UnitName("player")) or "Admin",
                }, "NORMAL")
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Heartbeat (parallel to GuildSync)
-------------------------------------------------------------------------------

function ticketSync:RebuildHeartbeatIds()
    local now = time()
    self._hbRebuildAt = now
    self._hbIds = {}

    local ids = {}
    for id, t in pairs(self.tickets or {}) do
        if type(id) == "string" and type(t) == "table" then
            if t.status ~= "resolved" then
                if IsAdmin() then
                    if t.ackedAt or not self:IsExpiredUnacked(t) then
                        ids[#ids + 1] = id
                    end
                else
                    if not t.ackedAt and not self:IsExpiredUnacked(t) then
                        ids[#ids + 1] = id
                    end
                end
            end
        end
    end

    table.sort(ids)
    self._hbIds = ids
end

function ticketSync:PruneTickets()
    if not self.tickets then return end
    local now = time()
    if (now - (self._lastPruneAt or 0)) < 30 then
        return
    end
    self._lastPruneAt = now

    local changed = false
    local admin = IsAdmin()

    for id, t in pairs(self.tickets) do
        if type(t) ~= "table" then
            self.tickets[id] = nil
            changed = true
        else
            -- Always drop fully-resolved tickets for non-admins
            if not admin and t.status == "resolved" then
                self.tickets[id] = nil
                changed = true
            elseif (not t.ackedAt) and self:IsExpiredUnacked(t) then
                -- Expired and never acknowledged: purge for everyone (admins shouldn't relay these either).
                self.tickets[id] = nil
                changed = true
            end
        end
    end

    if changed then
        self:SaveCachedTickets()
        -- Force heartbeat candidate rebuild after pruning
        self._hbRebuildAt = 0
    end
end

function ticketSync:SendHeartbeatSlice()
    if not IsInGuildSafe() then return end
    local comms = Private.CommsUtils
    if not comms then return end

    local now = time()
    self:PruneTickets()
    if not self._hbRebuildAt or (now - self._hbRebuildAt) >= 60 then
        self:RebuildHeartbeatIds()
    end

    local ids = self._hbIds or {}
    if #ids == 0 then
        return
    end

    self.hbIndex = (tonumber(self.hbIndex) or 0) + 1
    if self.hbIndex > #ids then
        self.hbIndex = 1
    end

    local id = ids[self.hbIndex]
    local t = id and self.tickets[id] or nil
    if not t then return end

    self._hbCounter = (self._hbCounter or 0) + 1
    local payload = {
        subPrefix = MSG_TYPE.HEARTBEAT,
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        hbId = tostring(now) .. "-" .. tostring(self._hbCounter),
        tickets = { t },
        timestamp = now,
    }

    local encoded = comms:Encode(payload)
    if not encoded or #encoded > 255 then
        -- Shrink reason to guarantee delivery
        local reason = tostring(t.reason or "")
        local max = math.min(#reason, 140)
        while max >= 20 do
            t.reason = reason:sub(1, max)
            payload.tickets = { t }
            encoded = comms:Encode(payload)
            if encoded and #encoded <= 255 then
                break
            end
            max = max - 10
        end
        if not encoded or #encoded > 255 then
            return
        end
    end

    comms:SendEncodedMessage(MSG_TYPE.HEARTBEAT, encoded, "GUILD", nil, "BULK")
end

function ticketSync:StartHeartbeat()
    if self.ticker and self.ticker.Cancel then
        self.ticker:Cancel()
    end
    self.ticker = C_Timer.NewTicker(self.TICK_SECONDS or 5, function()
        -- Stop if we are no longer in a guild.
        if not IsInGuildSafe() then
            self:StopHeartbeat()
            return
        end
        self:SendHeartbeatSlice()
    end)
end

function ticketSync:StopHeartbeat()
    if self.ticker and self.ticker.Cancel then
        self.ticker:Cancel()
    end
    self.ticker = nil
end

function ticketSync:RequestTickets()
    if not IsAdmin() then return end
    if not IsInGuildSafe() then return end

    local now = time()
    if (now - (self.lastRequestAt or 0)) < (self.REQUEST_COOLDOWN or 60) then
        return
    end
    self.lastRequestAt = now

    local requestId = tostring(now) .. "-" .. tostring(math.random(100000, 999999))
    self:SendGuildMessage(MSG_TYPE.REQ, {
        requester = GetPlayerShortName() or (type(UnitName) == "function" and UnitName("player")) or "Admin",
        requestId = requestId,
    }, "NORMAL")
end

function ticketSync:OnPlayerLogin()
    if not IsInGuildSafe() then
        self:StopHeartbeat()
        return
    end

    self:RebuildHeartbeatIds()
    self:StartHeartbeat()

    if IsAdmin() then
        self:RequestTickets()
    end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

---@param achievementId number
---@param reason string
---@return AchievementBugTicket|nil
function ticketSync:CreateTicket(achievementId, reason)
    if not IsInGuildSafe() then return nil end

    local id = self:GenerateTicketId()
    local reporter = GetPlayerShortName() or "Player"
    local now = time()

    local ticket = {
        id = id,
        achievementId = tonumber(achievementId) or 0,
        reason = ClampReason(reason),
        reporter = reporter,
        createdAt = now,
        status = "open",
        ackedAt = nil,
        ackedBy = nil,
        resolvedAt = nil,
        resolvedBy = nil,
    }

    self:EnsureTicketsBound()
    self.tickets[id] = ticket
    self:SaveCachedTickets()
    return ticket
end

---@param ticket AchievementBugTicket
function ticketSync:BroadcastTicketCreate(ticket)
    if not ticket or type(ticket.id) ~= "string" then return end
    self:SendGuildMessage(MSG_TYPE.CREATE, { ticket = ticket }, "NORMAL")
end

---@param ticketId string
---@return boolean success
function ticketSync:ResolveTicket(ticketId)
    if not IsAdmin() then return false end
    ticketId = tostring(ticketId or "")
    if ticketId == "" then return false end
    local t = self.tickets[ticketId]
    if not t then return false end

    t.status = "resolved"
    t.resolvedAt = time()
    t.resolvedBy = GetPlayerShortName() or (type(UnitName) == "function" and UnitName("player")) or "Admin"
    self:SaveCachedTickets()

    self:SendGuildMessage(MSG_TYPE.RESOLVE, {
        ticketId = ticketId,
        resolvedAt = t.resolvedAt,
        resolvedBy = t.resolvedBy,
    }, "NORMAL")

    return true
end

function ticketSync:WipeAllTickets()
    self.tickets = {}
    self.hbIndex = 0
    self:SaveCachedTickets()
end

function ticketSync:GetTickets()
    self:EnsureTicketsBound()
    return self.tickets or {}
end

function ticketSync:IsAdmin()
    return IsAdmin()
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------

function ticketSync:Init()
    self:LoadCachedTickets()
    self:RegisterMessageHandlers()

    -- Cleanup for chunk assembly
    C_Timer.NewTicker(15, function()
        self:CleanupPendingChunks()
    end)

    -- Start heartbeat after login settles.
    C_Timer.After(5, function()
        self:OnPlayerLogin()
    end)
end

