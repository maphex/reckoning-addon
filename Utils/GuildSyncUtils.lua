---@class AddonPrivate
local Private = select(2, ...)

local const = Private.constants

-------------------------------------------------------------------------------
-- Guild Sync System
-- Handles syncing achievement data between guild members
-------------------------------------------------------------------------------

---@class GuildMemberData
---@field name string Player name
---@field class string Class name
---@field classId number Class ID
---@field version string Addon version or "N/A"
---@field lastSeen number Unix timestamp of last seen
---@field completions table<number, number> achievementId -> timestamp
---@field totalPoints number Total achievement points

---@class GuildEventData
---@field achievementId number
---@field playerName string
---@field playerClass string
---@field timestamp number Unix timestamp

---@class GuildSyncUtils
local guildSync = {
    ---@type table<string, GuildMemberData> Player name -> data
    memberData = {},
    ---@type GuildEventData[] Recent events sorted by timestamp (newest first)
    recentEvents = {},
    ---@type number Last time we requested a full sync
    lastSyncRequest = 0,
    ---@type number Minimum time between sync requests (5 minutes)
    SYNC_COOLDOWN = 300,
    ---@type number Maximum events to keep
    MAX_EVENTS = 100,
    ---@type number Maximum age for events (30 days)
    MAX_EVENT_AGE = 30 * 24 * 60 * 60,
    ---@type boolean Whether initial sync has been done
    initialSyncDone = false,
    ---@type table Pending data chunks for large messages
    pendingChunks = {},
    ---@type table<string, number> Requester name -> last response time (throttle)
    lastResponseToRequester = {},
    ---@type number Minimum seconds before sending another full response to same requester
    RESPONSE_COOLDOWN = 60,
}
Private.GuildSyncUtils = guildSync

function guildSync:IsProtocolCompatible(data)
    if not data then return false end

    -- Backward-compatible: if protocolVersion is missing, assume current.
    local pv = tonumber(data.protocolVersion) or const.ADDON_COMMS.PROTOCOL_VERSION
    if pv ~= const.ADDON_COMMS.PROTOCOL_VERSION then
        local debugUtils = Private.DebugUtils
        if debugUtils then
            debugUtils:Log(
                "GUILD",
                "Ignored comms message due to protocol mismatch (got=%s, want=%s)",
                tostring(pv),
                tostring(const.ADDON_COMMS.PROTOCOL_VERSION)
            )
        end
        return false
    end
    return true
end

---@param sender string?
---@return string? shortName
function guildSync:ShortNameFromSender(sender)
    if not sender then return nil end
    local shortName = strsplit("-", sender)
    return shortName
end

function guildSync:CleanupPendingChunks()
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

-- Message types for guild sync
local MSG_TYPE = {
    SYNC_REQUEST = "GSYNC_REQ",       -- Request sync from guild
    SYNC_RESPONSE = "GSYNC_RESP",     -- Response with our data
    SYNC_CHUNK = "GSYNC_CHUNK",       -- Chunked response with partial data
    HEARTBEAT = "GSYNC_HB",           -- Periodic incremental sync (small slices)
    COMPLETION = "GSYNC_COMP",        -- Single achievement completion broadcast
    HELLO = "GSYNC_HELLO",            -- Announce presence on login
    ROSTER_REQUEST = "GSYNC_ROSTER",  -- Request roster info
    ROSTER_RESPONSE = "GSYNC_RDATA",  -- Roster data response
}

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function guildSync:Init()
    -- Register message handlers
    self:RegisterMessageHandlers()

    -- Load cached data from SavedVariables
    self:LoadCachedData()

    -- Schedule initial sync after a short delay (let addon fully load)
    C_Timer.After(5, function()
        self:OnPlayerLogin()
    end)

    -- Register for guild roster updates
    Private.Addon:RegisterEvent("GUILD_ROSTER_UPDATE", "GuildSync_RosterUpdate", function()
        self:OnGuildRosterUpdate()
    end)

    -- Register for when we complete an achievement
    Private.CallbackUtils:AddCallback("AchievementCompleted", function(achievementId, achievement)
        self:BroadcastCompletion(achievementId)
    end)
end

function guildSync:RegisterMessageHandlers()
    local comms = Private.CommsUtils

    comms:AddCallback(MSG_TYPE.SYNC_REQUEST, function(data)
        self:OnSyncRequest(data)
    end)

    comms:AddCallback(MSG_TYPE.SYNC_RESPONSE, function(data)
        self:OnSyncResponse(data)
    end)

    comms:AddCallback(MSG_TYPE.SYNC_CHUNK, function(data)
        self:OnSyncChunk(data)
    end)

    comms:AddCallback(MSG_TYPE.HEARTBEAT, function(data)
        self:OnHeartbeat(data)
    end)

    comms:AddCallback(MSG_TYPE.COMPLETION, function(data)
        self:OnCompletionReceived(data)
    end)

    comms:AddCallback(MSG_TYPE.HELLO, function(data)
        self:OnHelloReceived(data)
    end)

    comms:AddCallback(MSG_TYPE.ROSTER_REQUEST, function(data)
        self:OnRosterRequest(data)
    end)

    comms:AddCallback(MSG_TYPE.ROSTER_RESPONSE, function(data)
        self:OnRosterResponse(data)
    end)
end

-------------------------------------------------------------------------------
-- Data Persistence
-------------------------------------------------------------------------------

function guildSync:LoadCachedData()
    local addon = Private.Addon
    if not addon or not addon.Database then return end

    local db = addon.Database
    if db.guildCache then
        self.memberData = db.guildCache.members or {}
        self.recentEvents = db.guildCache.events or {}

        -- Clean old events
        self:CleanOldEvents()

        local debugUtils = Private.DebugUtils
        if debugUtils then
            local memberCount = 0
            for _ in pairs(self.memberData) do memberCount = memberCount + 1 end
            debugUtils:Log("GUILD", "Loaded %d cached members, %d events", memberCount, #self.recentEvents)
        end
    end
end

function guildSync:SaveCachedData()
    local addon = Private.Addon
    if not addon or not addon.Database then return end

    addon.Database.guildCache = {
        members = self.memberData,
        events = self.recentEvents,
        savedAt = time(),
    }
end

function guildSync:CleanOldEvents()
    local now = time()
    local cutoff = now - self.MAX_EVENT_AGE
    local newEvents = {}

    for _, event in ipairs(self.recentEvents) do
        if event.timestamp > cutoff then
            table.insert(newEvents, event)
        end
    end

    -- Also limit to MAX_EVENTS
    if #newEvents > self.MAX_EVENTS then
        local trimmed = {}
        for i = 1, self.MAX_EVENTS do
            trimmed[i] = newEvents[i]
        end
        newEvents = trimmed
    end

    self.recentEvents = newEvents
end

-------------------------------------------------------------------------------
-- Login / Sync Logic
-------------------------------------------------------------------------------

function guildSync:OnPlayerLogin()
    if not IsInGuild() then return end

    -- Announce our presence
    self:SendHello()

    -- Request full sync after a short delay
    C_Timer.After(2, function()
        self:RequestFullSync()
    end)

    self:StartHeartbeat()
    self.initialSyncDone = true
end

function guildSync:StartHeartbeat()
    if self.heartbeatTicker then return end

    self._heartbeatLastSent = 0
    self._heartbeatCounter = 0
    self._heartbeatIds = nil
    self._heartbeatIndex = 1
    self._heartbeatLastRebuild = 0

    local TICK = 5
    local MAX_INTERVAL = 80

    self.heartbeatTicker = C_Timer.NewTicker(TICK, function()
        if not IsInGuild() then return end

        local now = time()
        local onlineCount = 1

        if (now - (self._pendingChunkCleanupLast or 0)) >= 15 then
            self._pendingChunkCleanupLast = now
            self:CleanupPendingChunks()
        end

        -- Compute online count only when we're about to consider sending.
        -- This keeps per-tick work light while still adapting like the reference.
        if now - (self._heartbeatLastOnlineCalc or 0) >= 30 then
            self._heartbeatLastOnlineCalc = now
            onlineCount = 0
            local numMembers = GetNumGuildMembers()
            for i = 1, numMembers do
                local _, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
                if isOnline then
                    onlineCount = onlineCount + 1
                end
            end
            self._heartbeatOnlineCount = onlineCount
        else
            onlineCount = self._heartbeatOnlineCount or 1
        end

        local interval = onlineCount
        if interval < TICK then
            interval = TICK
        elseif interval > MAX_INTERVAL then
            interval = MAX_INTERVAL
        end

        if now - (self._heartbeatLastSent or 0) < interval then
            return
        end

        self._heartbeatLastSent = now
        self:SendHeartbeatSlice()
    end)
end

function guildSync:RebuildHeartbeatData()
    local engine = Private.AchievementEngine
    if not engine then return end

    local completions = engine:GetAllCompletedWithTimestamps() or {}
    local ids = {}
    for achievementId in pairs(completions) do
        table.insert(ids, achievementId)
    end
    table.sort(ids)

    self._heartbeatCompletions = completions
    self._heartbeatIds = ids
    self._heartbeatIndex = 1
    self._heartbeatLastRebuild = time()
end

function guildSync:SendHeartbeatSlice()
    local comms = Private.CommsUtils
    if not comms then return end

    local engine = Private.AchievementEngine
    if not engine then return end

    local now = time()
    if (not self._heartbeatIds) or (now - (self._heartbeatLastRebuild or 0) >= 60) then
        self:RebuildHeartbeatData()
    end

    local ids = self._heartbeatIds
    local completions = self._heartbeatCompletions or {}
    if not ids or #ids == 0 then
        return
    end

    local playerName = UnitName("player")
    local _, className, classId = UnitClass("player")

    local SLICE = 3
    local slice = {}
    local startIndex = self._heartbeatIndex or 1

    for _ = 1, SLICE do
        if startIndex > #ids then
            startIndex = 1
        end
        local id = ids[startIndex]
        slice[id] = completions[id]
        startIndex = startIndex + 1
    end

    self._heartbeatIndex = startIndex
    self._heartbeatCounter = (self._heartbeatCounter or 0) + 1

    local payload = {
        subPrefix = MSG_TYPE.HEARTBEAT,
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        hbId = tostring(now) .. "-" .. tostring(self._heartbeatCounter),
        myData = {
            name = playerName,
            class = className,
            classId = classId,
            version = const.ADDON_VERSION or "1.0.0",
            lastSeen = now,
            completions = slice,
        },
        timestamp = now,
    }

    local encoded = comms:Encode(payload)
    if not encoded or #encoded > 255 then
        -- If this somehow doesn't fit, shrink to 1 completion to guarantee delivery.
        local id = ids[self._heartbeatIndex and (self._heartbeatIndex - 1) or 1] or ids[1]
        if not id then return end
        payload.myData.completions = { [id] = completions[id] }
        encoded = comms:Encode(payload)
        if not encoded or #encoded > 255 then
            return
        end
    end

    comms:SendEncodedMessage(MSG_TYPE.HEARTBEAT, encoded, "GUILD", nil, "BULK")
end

function guildSync:SendHello()
    if not IsInGuild() then return end

    local playerName = UnitName("player")
    local _, className, classId = UnitClass("player")

    Private.CommsUtils:SendMessage(MSG_TYPE.HELLO, {
        name = playerName,
        class = className,
        classId = classId,
        version = const.ADDON_VERSION or "1.0.0",
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        timestamp = time(),
    }, "GUILD")
end

function guildSync:RequestFullSync()
    if not IsInGuild() then return end

    local now = time()
    if now - self.lastSyncRequest < self.SYNC_COOLDOWN then
        return -- Don't spam requests
    end

    self.lastSyncRequest = now

    Private.CommsUtils:SendMessage(MSG_TYPE.SYNC_REQUEST, {
        requester = UnitName("player"),
        requestId = tostring(now) .. "-" .. tostring(math.random(100000, 999999)),
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        timestamp = now,
    }, "GUILD")

    local debugUtils = Private.DebugUtils
    if debugUtils then
        debugUtils:Log("GUILD", "Requested full sync from guild")
    end
end

-------------------------------------------------------------------------------
-- Message Handlers
-------------------------------------------------------------------------------

function guildSync:OnHelloReceived(data)
    if not data or not data.name then return end

    if not self:IsProtocolCompatible(data) then return end

    local senderShort = self:ShortNameFromSender(data.sender) or data.name

    -- Don't process our own messages
    if senderShort == UnitName("player") then return end

    -- Update member data
    self:UpdateMemberInfo(senderShort, {
        class = data.class,
        classId = data.classId,
        version = data.version,
        lastSeen = data.timestamp or time(),
    })

    local debugUtils = Private.DebugUtils
    if debugUtils then
        debugUtils:Log("GUILD", "Received hello from %s (v%s)", senderShort, data.version or "?")
    end
end

function guildSync:OnSyncRequest(data)
    if not data then return end

    if not self:IsProtocolCompatible(data) then return end

    local requester = data.sender or data.requester
    if not requester then return end

    local requestId = data.requestId or (tostring(data.timestamp or time()) .. "-" .. tostring(math.random(100000, 999999)))

    -- Throttle: don't send full response to same requester within cooldown
    local now = time()
    if self.lastResponseToRequester[requester] and (now - self.lastResponseToRequester[requester]) < self.RESPONSE_COOLDOWN then
        return
    end
    self.lastResponseToRequester[requester] = now

    -- Send our data (random delay to prevent everyone responding at once)
    local delay = math.random(1, 5)
    C_Timer.After(delay, function()
        self:SendSyncResponse(requester, requestId)
    end)
end

function guildSync:SendSyncResponse(targetPlayer, requestId)
    if not IsInGuild() then return end

    local engine = Private.AchievementEngine
    if not engine then return end

    local playerName = UnitName("player")
    local _, className, classId = UnitClass("player")

    -- Get our completions
    local completions = engine:GetAllCompletedWithTimestamps()

    -- Calculate total points
    local totalPoints = 0
    for achievementId, _ in pairs(completions) do
        local achievement = Private.AchievementUtils:GetAchievement(achievementId)
        if achievement then
            totalPoints = totalPoints + (achievement.points or 0)
        end
    end

    -- Build our data packet (only our own completions - no cache re-broadcast for scalability)
    local myData = {
        name = playerName,
        class = className,
        classId = classId,
        version = const.ADDON_VERSION or "1.0.0",
        lastSeen = time(),
        completions = completions,
        totalPoints = totalPoints,
    }

    -- First attempt: try to send as a single message. If it doesn't fit, fall back to chunked sync.
    local comms = Private.CommsUtils
    local singlePayload = {
        subPrefix = MSG_TYPE.SYNC_RESPONSE,
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        requestId = requestId,
        myData = myData,
        timestamp = time(),
    }
    local encoded = comms:Encode(singlePayload)
    if encoded and #encoded <= 255 then
        comms:SendEncodedMessage(MSG_TYPE.SYNC_RESPONSE, encoded, "GUILD", nil, "NORMAL")
    else
        self:SendSyncResponseChunked(myData, requestId)
    end

    local debugUtils = Private.DebugUtils
    if debugUtils then
        local compCount = 0
        for _ in pairs(completions) do compCount = compCount + 1 end
        debugUtils:Log("GUILD", "Sent sync response: %d completions, %d points", compCount, totalPoints)
    end
end

function guildSync:SendSyncResponseChunked(myData, requestId)
    local comms = Private.CommsUtils
    if not comms then return end

    local completions = myData.completions or {}

    local ids = {}
    for achievementId in pairs(completions) do
        table.insert(ids, achievementId)
    end
    table.sort(ids)

    local total = #ids
    local seq = 1
    local idx = 1
    local targetChannel = "GUILD"

    -- Start with a reasonable batch size and shrink if encoding exceeds message limit.
    local batchSize = 60

    while idx <= total do
        local take = math.min(batchSize, total - idx + 1)
        local payload, encoded

        while take > 0 do
            local slice = {}
            for i = idx, (idx + take - 1) do
                local id = ids[i]
                slice[id] = completions[id]
            end

            payload = {
                subPrefix = MSG_TYPE.SYNC_CHUNK,
                protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
                requestId = requestId,
                seq = seq,
                isLast = (idx + take - 1) >= total,
                myData = {
                    name = myData.name,
                    class = myData.class,
                    classId = myData.classId,
                    version = myData.version,
                    lastSeen = myData.lastSeen,
                    completions = slice,
                    totalPoints = myData.totalPoints,
                    totalCompletions = total,
                },
                timestamp = time(),
            }

            encoded = comms:Encode(payload)
            if encoded and #encoded <= 255 then
                break
            end

            take = take - 1
        end

        if not encoded then
            return
        end

        -- If we couldn't even fit a single entry, bail to avoid an infinite loop.
        if take <= 0 then
            local debugUtils = Private.DebugUtils
            if debugUtils then
                debugUtils:Log("GUILD", "Failed to send sync chunk: message too large even for one completion")
            end
            return
        end

        comms:SendEncodedMessage(MSG_TYPE.SYNC_CHUNK, encoded, targetChannel, nil, "BULK")

        idx = idx + take
        seq = seq + 1
    end

    -- Edge case: no completions (send a single empty chunk so receivers still learn about us)
    if total == 0 then
        local payload = {
            subPrefix = MSG_TYPE.SYNC_CHUNK,
            protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
            requestId = requestId,
            seq = 1,
            isLast = true,
            myData = {
                name = myData.name,
                class = myData.class,
                classId = myData.classId,
                version = myData.version,
                lastSeen = myData.lastSeen,
                completions = {},
                totalPoints = myData.totalPoints,
                totalCompletions = 0,
            },
            timestamp = time(),
        }
        local encoded = comms:Encode(payload)
        if encoded and #encoded <= 255 then
            comms:SendEncodedMessage(MSG_TYPE.SYNC_CHUNK, encoded, targetChannel, nil, "BULK")
        end
    end
end

function guildSync:OnSyncResponse(data)
    if not data then return end
    if not self:IsProtocolCompatible(data) then return end

    local debugUtils = Private.DebugUtils
    local now = time()
    local cutoff = now - self.MAX_EVENT_AGE

    -- Process sender's own data
    if data.myData then
        local senderShort = self:ShortNameFromSender(data.sender) or data.myData.name
        data.myData.name = senderShort
        self:MergeMemberData(data.myData)

        -- Add events for their completions
        if data.myData.completions then
            for achievementId, timestamp in pairs(data.myData.completions) do
                if timestamp and timestamp > cutoff then
                    self:AddEvent(achievementId, data.myData.name, data.myData.class, timestamp)
                end
            end
        end
    end

    -- Process cached data from others
    if data.cachedMembers then
        for name, memberData in pairs(data.cachedMembers) do
            self:MergeMemberData(memberData)

            -- Add events for their completions
            if memberData.completions then
                for achievementId, timestamp in pairs(memberData.completions) do
                    if timestamp and timestamp > cutoff then
                        self:AddEvent(achievementId, name, memberData.class, timestamp)
                    end
                end
            end
        end
    end

    -- Save and update UI
    self:SaveCachedData()
    self:NotifyUIUpdate()

    if debugUtils then
        debugUtils:Log("GUILD", "Processed sync response from %s", data.sender or "unknown")
    end
end

function guildSync:OnSyncChunk(data)
    if not data or not data.myData then return end
    if not self:IsProtocolCompatible(data) then return end

    local sender = data.sender
    if not sender then return end

    local senderShort = self:ShortNameFromSender(sender) or data.myData.name
    data.myData.name = senderShort

    local requestId = data.requestId or "legacy"
    local seq = tonumber(data.seq or 0) or 0
    if seq <= 0 then return end

    self.pendingChunks[sender] = self.pendingChunks[sender] or {}
    local state = self.pendingChunks[sender][requestId]
    if not state then
        state = {
            startedAt = time(),
            lastUpdate = time(),
            received = {},
            lastSeq = nil,
            lastPersist = 0,
        }
        self.pendingChunks[sender][requestId] = state
    end

    -- Deduplicate chunk sequences
    if state.received[seq] then
        return
    end
    state.received[seq] = true
    state.lastUpdate = time()

    if data.isLast then
        state.lastSeq = seq
    end

    -- Merge the partial member data
    self:MergeMemberData(data.myData)

    -- Add only recent completion events (avoid flooding recentEvents with full history)
    if data.myData.completions then
        local now = time()
        local cutoff = now - self.MAX_EVENT_AGE
        for achievementId, timestamp in pairs(data.myData.completions) do
            if timestamp and timestamp > cutoff then
                self:AddEvent(achievementId, data.myData.name, data.myData.class, timestamp)
            end
        end
    end

    -- Persist/refresh occasionally so partial chunk delivery still updates UI.
    local now = time()
    if (now - (state.lastPersist or 0)) >= 2 then
        state.lastPersist = now
        self:SaveCachedData()
        self:NotifyUIUpdate()
    end

    -- If we have the last seq and all chunks up to it, finalize and persist.
    if state.lastSeq then
        for i = 1, state.lastSeq do
            if not state.received[i] then
                return
            end
        end

        self.pendingChunks[sender][requestId] = nil
        if not next(self.pendingChunks[sender]) then
            self.pendingChunks[sender] = nil
        end

        self:SaveCachedData()
        self:NotifyUIUpdate()
    end
end

function guildSync:OnCompletionReceived(data)
    if not data or not data.achievementId then return end
    if not self:IsProtocolCompatible(data) then return end

    -- Don't process our own completions
    local senderShort = self:ShortNameFromSender(data.sender) or data.playerName
    if senderShort == UnitName("player") then return end

    -- Add the event
    self:AddEvent(data.achievementId, senderShort, data.playerClass, data.timestamp or time())

    -- Update member's completion data
    local member = self.memberData[senderShort]
    if member then
        member.completions = member.completions or {}
        member.completions[data.achievementId] = data.timestamp or time()
        member.lastSeen = time()

        -- Recalculate points
        local totalPoints = 0
        for achievementId, _ in pairs(member.completions) do
            local achievement = Private.AchievementUtils:GetAchievement(achievementId)
            if achievement then
                totalPoints = totalPoints + (achievement.points or 0)
            end
        end
        member.totalPoints = totalPoints
    end

    -- Save and update UI
    self:SaveCachedData()
    self:NotifyUIUpdate()

    local debugUtils = Private.DebugUtils
    if debugUtils then
        local achievement = Private.AchievementUtils:GetAchievement(data.achievementId)
        debugUtils:Log("GUILD", "%s completed: %s", senderShort, achievement and achievement.name or "Unknown")
    end
end

function guildSync:OnHeartbeat(data)
    if not data or not data.myData or not data.myData.completions then return end
    if not self:IsProtocolCompatible(data) then return end

    -- Don't process our own heartbeats
    local senderShort = self:ShortNameFromSender(data.sender) or data.myData.name
    if senderShort == UnitName("player") then return end

    data.myData.name = senderShort

    self:MergeMemberData(data.myData)

    -- Heartbeats are incremental; treat completions as recent-ish signals only.
    local now = time()
    local cutoff = now - self.MAX_EVENT_AGE
    for achievementId, timestamp in pairs(data.myData.completions) do
        if timestamp and timestamp > cutoff then
            self:AddEvent(achievementId, data.myData.name, data.myData.class, timestamp)
        end
    end

    self:SaveCachedData()
    self:NotifyUIUpdate()
end

function guildSync:OnRosterRequest(data)
    if data and (not self:IsProtocolCompatible(data)) then return end

    -- Someone wants roster info - send what we have
    local delay = math.random(1, 3)
    C_Timer.After(delay, function()
        self:SendRosterResponse()
    end)
end

function guildSync:SendRosterResponse()
    if not IsInGuild() then return end

    local rosterData = {}
    for name, member in pairs(self.memberData) do
        rosterData[name] = {
            class = member.class,
            classId = member.classId,
            version = member.version,
            lastSeen = member.lastSeen,
            totalPoints = member.totalPoints or 0,
        }
    end

    Private.CommsUtils:SendMessage(MSG_TYPE.ROSTER_RESPONSE, {
        roster = rosterData,
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        timestamp = time(),
    }, "GUILD")
end

function guildSync:OnRosterResponse(data)
    if not data or not data.roster then return end
    if not self:IsProtocolCompatible(data) then return end

    for name, info in pairs(data.roster) do
        self:UpdateMemberInfo(name, info)
    end

    self:SaveCachedData()
    self:NotifyUIUpdate()
end

-------------------------------------------------------------------------------
-- Data Merging
-------------------------------------------------------------------------------

function guildSync:MergeMemberData(newData)
    if not newData or not newData.name then return end

    local name = newData.name
    local existing = self.memberData[name]

    if not existing then
        -- New member
        self.memberData[name] = {
            name = name,
            class = newData.class,
            classId = newData.classId,
            version = newData.version,
            lastSeen = newData.lastSeen or time(),
            completions = newData.completions or {},
            totalPoints = newData.totalPoints or 0,
        }
    else
        -- Merge with existing - prefer newer data
        if (newData.lastSeen or 0) >= (existing.lastSeen or 0) then
            existing.class = newData.class or existing.class
            existing.classId = newData.classId or existing.classId
            existing.version = newData.version or existing.version
            existing.lastSeen = newData.lastSeen or existing.lastSeen
            existing.totalPoints = newData.totalPoints or existing.totalPoints
        end

        -- Merge completions - keep newest timestamp for each achievement
        if newData.completions then
            existing.completions = existing.completions or {}
            for achievementId, timestamp in pairs(newData.completions) do
                local existingTimestamp = existing.completions[achievementId]
                if not existingTimestamp or timestamp > existingTimestamp then
                    existing.completions[achievementId] = timestamp
                end
            end
        end
    end
end

function guildSync:UpdateMemberInfo(name, info)
    if not name then return end

    local existing = self.memberData[name]
    if not existing then
        self.memberData[name] = {
            name = name,
            class = info.class,
            classId = info.classId,
            version = info.version,
            lastSeen = info.lastSeen or time(),
            completions = {},
            totalPoints = info.totalPoints or 0,
        }
    else
        -- Update if newer
        if (info.lastSeen or 0) >= (existing.lastSeen or 0) then
            existing.class = info.class or existing.class
            existing.classId = info.classId or existing.classId
            existing.version = info.version or existing.version
            existing.lastSeen = info.lastSeen or existing.lastSeen
            if info.totalPoints then
                existing.totalPoints = info.totalPoints
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Event Management
-------------------------------------------------------------------------------

function guildSync:AddEvent(achievementId, playerName, playerClass, timestamp)
    if not achievementId or not playerName then return end

    -- Check if we already have this exact event
    for _, event in ipairs(self.recentEvents) do
        if event.achievementId == achievementId and
           event.playerName == playerName and
           event.timestamp == timestamp then
            return -- Already exists
        end
    end

    -- Add the event
    table.insert(self.recentEvents, {
        achievementId = achievementId,
        playerName = playerName,
        playerClass = playerClass or "Unknown",
        timestamp = timestamp or time(),
    })

    -- Sort by timestamp (newest first)
    table.sort(self.recentEvents, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

    -- Trim to max events
    while #self.recentEvents > self.MAX_EVENTS do
        table.remove(self.recentEvents)
    end
end

function guildSync:BroadcastCompletion(achievementId)
    if not IsInGuild() then return end

    local playerName = UnitName("player")
    local _, className = UnitClass("player")
    local timestamp = time()

    -- Add to our own events
    self:AddEvent(achievementId, playerName, className, timestamp)

    -- Update our own member data
    local engine = Private.AchievementEngine
    if engine then
        local completions = engine:GetAllCompletedWithTimestamps()
        local totalPoints = 0
        for id, _ in pairs(completions) do
            local achievement = Private.AchievementUtils:GetAchievement(id)
            if achievement then
                totalPoints = totalPoints + (achievement.points or 0)
            end
        end

        self:UpdateMemberInfo(playerName, {
            class = className,
            version = const.ADDON_VERSION or "1.0.0",
            lastSeen = timestamp,
            totalPoints = totalPoints,
        })

        -- Store completions
        if self.memberData[playerName] then
            self.memberData[playerName].completions = completions
        end

        -- Ensure heartbeat data is rebuilt soon (we have new completion state).
        self._heartbeatLastRebuild = 0
    end

    -- Broadcast to guild
    Private.CommsUtils:SendMessage(MSG_TYPE.COMPLETION, {
        achievementId = achievementId,
        playerName = playerName,
        playerClass = className,
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        timestamp = timestamp,
    }, "GUILD")

    -- Save
    self:SaveCachedData()
    self:NotifyUIUpdate()

    local debugUtils = Private.DebugUtils
    if debugUtils then
        local achievement = Private.AchievementUtils:GetAchievement(achievementId)
        debugUtils:Log("GUILD", "Broadcast completion: %s", achievement and achievement.name or "Unknown")
    end
end

-------------------------------------------------------------------------------
-- Guild Roster Integration
-------------------------------------------------------------------------------

function guildSync:OnGuildRosterUpdate()
    if not IsInGuild() then return end

    -- Update our data with guild roster info for members we don't have
    local numMembers = GetNumGuildMembers()
    for i = 1, numMembers do
        local name, rank, rankIndex, level, class, zone, note, officerNote, online, status, classFileName, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid = GetGuildRosterInfo(i)

        if name then
            -- Remove realm suffix if present for consistency
            local shortName = strsplit("-", name)

            local existing = self.memberData[shortName]
            if not existing then
                -- Add basic info for members we don't have data for
                self.memberData[shortName] = {
                    name = shortName,
                    class = class,
                    classId = 0,
                    version = "N/A",  -- They don't have the addon
                    lastSeen = online and time() or 0,
                    completions = {},
                    totalPoints = 0,
                }
            elseif online then
                -- Update last seen if online
                existing.lastSeen = time()
            end
        end
    end
end

-------------------------------------------------------------------------------
-- UI Data Accessors
-------------------------------------------------------------------------------

---Get sorted list of recent events for the Events tab
---@param limit? number Maximum events to return
---@return GuildEventData[]
function guildSync:GetRecentEvents(limit)
    limit = limit or 50
    local events = {}

    for i = 1, math.min(#self.recentEvents, limit) do
        events[i] = self.recentEvents[i]
    end

    return events
end

---Get current online status for guild members
---@return table<string, boolean> Map of player names to online status
function guildSync:GetOnlineMembers()
    local online = {}

    if not IsInGuild() then return online end

    local numMembers = GetNumGuildMembers()
    for i = 1, numMembers do
        local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if name and isOnline then
            local shortName = strsplit("-", name)
            online[shortName] = true
        end
    end

    return online
end

---Get sorted roster data for the Roster tab
---@param sortColumn? string "name", "class", "version", "lastSeen", "points"
---@param ascending? boolean
---@return GuildMemberData[]
function guildSync:GetRosterData(sortColumn, ascending)
    sortColumn = sortColumn or "name"
    if ascending == nil then ascending = true end

    -- Get current online status
    local onlineMembers = self:GetOnlineMembers()

    -- Convert to array and add online status
    local roster = {}
    for name, member in pairs(self.memberData) do
        local entry = {
            name = member.name,
            class = member.class,
            version = member.version,
            lastSeen = member.lastSeen,
            completions = member.completions,
            totalPoints = member.totalPoints,
            isOnline = onlineMembers[name] or false,
        }
        table.insert(roster, entry)
    end

    -- Sort
    table.sort(roster, function(a, b)
        local aVal, bVal

        if sortColumn == "name" then
            aVal, bVal = (a.name or ""):lower(), (b.name or ""):lower()
        elseif sortColumn == "class" then
            aVal, bVal = (a.class or ""):lower(), (b.class or ""):lower()
        elseif sortColumn == "version" then
            aVal, bVal = a.version or "N/A", b.version or "N/A"
        elseif sortColumn == "lastSeen" then
            -- Online members should sort first/last based on direction
            -- Use current time for online members so they appear as "most recent"
            local now = time()
            aVal = a.isOnline and now or (a.lastSeen or 0)
            bVal = b.isOnline and now or (b.lastSeen or 0)
        elseif sortColumn == "points" then
            aVal, bVal = a.totalPoints or 0, b.totalPoints or 0
        else
            aVal, bVal = (a.name or ""):lower(), (b.name or ""):lower()
        end

        if ascending then
            return aVal < bVal
        else
            return aVal > bVal
        end
    end)

    return roster
end

---Get member count statistics
---@return number total, number withAddon, number online
function guildSync:GetMemberStats()
    local total = 0
    local withAddon = 0
    local online = 0

    -- Get actual online status from guild roster
    local onlineMembers = self:GetOnlineMembers()

    for name, member in pairs(self.memberData) do
        total = total + 1
        if member.version and member.version ~= "N/A" then
            withAddon = withAddon + 1
        end
        if onlineMembers[name] then
            online = online + 1
        end
    end

    return total, withAddon, online
end

---Format timestamp for display
---@param timestamp number Unix timestamp
---@return string
function guildSync:FormatTimestamp(timestamp)
    if not timestamp or timestamp == 0 then
        return "Never"
    end

    local now = time()
    local diff = now - timestamp

    if diff < 60 then
        return "Just now"
    elseif diff < 3600 then
        local mins = math.floor(diff / 60)
        return mins .. " min" .. (mins == 1 and "" or "s") .. " ago"
    elseif diff < 86400 then
        local hours = math.floor(diff / 3600)
        return hours .. " hour" .. (hours == 1 and "" or "s") .. " ago"
    elseif diff < 604800 then
        local days = math.floor(diff / 86400)
        return days .. " day" .. (days == 1 and "" or "s") .. " ago"
    else
        return date("%m/%d/%Y", timestamp)
    end
end

---Format timestamp for tooltip (exact date/time)
---@param timestamp number Unix timestamp
---@return string
function guildSync:FormatExactTimestamp(timestamp)
    if not timestamp or timestamp == 0 then
        return "Unknown"
    end
    return date("%m/%d/%Y %I:%M %p", timestamp)
end

-------------------------------------------------------------------------------
-- UI Notification
-------------------------------------------------------------------------------

function guildSync:NotifyUIUpdate()
    -- Fire a callback so UI can refresh
    if Private.CallbackUtils then
        local callbacks = Private.CallbackUtils:GetCallbacks("GuildDataUpdated")
        for _, cb in ipairs(callbacks) do
            cb:Trigger()
        end
    end
end

---Trigger a manual sync (for UI button)
---@return boolean success
---@return string message
function guildSync:TriggerManualSync()
    if not IsInGuild() then
        return false, "You must be in a guild to sync"
    end

    local numMembers = GetNumGuildMembers()
    if numMembers <= 1 then
        return false, "No other guild members found"
    end

    self.lastSyncRequest = 0  -- Reset cooldown
    self:RequestFullSync()

    return true, "Sync request sent to guild members"
end
