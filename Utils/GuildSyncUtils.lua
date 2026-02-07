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
---@field version string Addon version, "Unknown" if dev build, or "N/A" if no addon
---@field lastSeen number Unix timestamp of last seen
---@field completions table<number, number> achievementId -> timestamp
---@field completionVersions table<number, string>|nil achievementId -> addon version at completion (for correction gating)
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

    ---------------------------------------------------------------------------
    -- Version update nudges (guild-coordinated)
    ---------------------------------------------------------------------------

    ---@type table<string, {timer:any?, requestId:string?, requestedAt:number?, whisperTarget:string?, verifyTimer:any?}>
    pendingVersionChecks = {},
    ---@type table<string, number> shortName -> last time we (or someone) notified
    recentNotified = {},
    ---@type table<string, number> shortName -> last notify timestamp (persisted)
    versionNotifyCooldown = {},
    ---@type number Minimum seconds to delay notify after HELLO
    VERSION_NOTIFY_MIN_DELAY = 5,
    ---@type number Maximum seconds to delay notify after HELLO
    VERSION_NOTIFY_MAX_DELAY = 25,
    ---@type number Per-target cooldown in seconds (once per day)
    VERSION_NOTIFY_COOLDOWN_SECONDS = 24 * 60 * 60,

    ---@type number Last time we printed a self-update reminder
    selfUpdateReminderLastAt = 0,
    ---@type number Minimum seconds between self-update reminders
    SELF_UPDATE_REMINDER_COOLDOWN_SECONDS = 2 * 60 * 60,
}
Private.GuildSyncUtils = guildSync

function guildSync:ShouldShowLogs()
    local addon = Private and Private.Addon
    if not addon or not addon.GetDatabaseValue then
        return false
    end
    return addon:GetDatabaseValue("settings.guildSync.showLogs", true) == true
end

---@param message string
---@param ... any
function guildSync:SyncLog(message, ...)
    if not self:ShouldShowLogs() then return end
    local addon = Private and Private.Addon
    if addon and addon.FPrint then
        addon:FPrint("[GuildSync] " .. (message or ""), ...)
    else
        print("[GuildSync] " .. string.format(message or "", ...))
    end
end

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

--- Recalculate member.totalPoints using corrections and version gating.
---@param member table must have completions (achievementId -> timestamp); completionVersions and version used for gating
function guildSync:RecalculateMemberPoints(member)
    if not member or not member.completions then return end
    local correctionSync = Private.CorrectionSyncUtils
    if not correctionSync or not correctionSync.ShouldCountAchievementPoints then
        local total = 0
        for achievementId, _ in pairs(member.completions) do
            local achievement = Private.AchievementUtils:GetAchievement(achievementId)
            if achievement then total = total + (achievement.points or 0) end
        end
        member.totalPoints = total
        return
    end
    local versions = member.completionVersions or {}
    local fallbackVersion = member.version
    local total = 0
    for achievementId, completedAt in pairs(member.completions) do
        local achievement = Private.AchievementUtils:GetAchievement(achievementId)
        if achievement then
            local ver = versions[achievementId] or fallbackVersion
            if correctionSync:ShouldCountAchievementPoints(achievementId, completedAt, ver) then
                total = total + (achievement.points or 0)
            end
        end
    end
    member.totalPoints = total
end

---@param sender string?
---@return string? shortName
function guildSync:ShortNameFromSender(sender)
    if not sender then return nil end
    local shortName = strsplit("-", sender)
    return shortName
end

-------------------------------------------------------------------------------
-- Version Helpers (SemVer)
-------------------------------------------------------------------------------

---@param v string|nil
---@return number|nil major
---@return number|nil minor
---@return number|nil patch
function guildSync:ParseSemVer(v)
    if type(v) ~= "string" then return nil, nil, nil end
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    if v == "" or v == "Unknown" or v == "N/A" then return nil, nil, nil end
    v = v:gsub("^v", "")

    local major, minor, patch = v:match("^(%d+)%.(%d+)%.(%d+)")
    if major then
        return tonumber(major), tonumber(minor), tonumber(patch)
    end

    major, minor = v:match("^(%d+)%.(%d+)")
    if major then
        return tonumber(major), tonumber(minor), 0
    end

    major = v:match("^(%d+)")
    if major then
        return tonumber(major), 0, 0
    end

    return nil, nil, nil
end

---@param a string|nil
---@param b string|nil
---@return number|nil cmp -1 if a<b, 0 if a==b, 1 if a>b, nil if not comparable
function guildSync:CompareSemVer(a, b)
    local a1, a2, a3 = self:ParseSemVer(a)
    local b1, b2, b3 = self:ParseSemVer(b)
    if not a1 or not b1 then return nil end

    if a1 ~= b1 then return (a1 > b1) and 1 or -1 end
    if a2 ~= b2 then return (a2 > b2) and 1 or -1 end
    if a3 ~= b3 then return (a3 > b3) and 1 or -1 end
    return 0
end

---@param otherVersion string|nil
---@return boolean|nil newer True if our version > otherVersion, nil if not comparable
function guildSync:IsMyVersionNewerThan(otherVersion)
    local mine = const and const.ADDON_VERSION or nil
    if type(otherVersion) == "string" and otherVersion ~= "" and otherVersion ~= "Unknown" and otherVersion ~= "N/A" then
        local m1 = self:ParseSemVer(mine)
        local o1 = self:ParseSemVer(otherVersion)
        -- If our version is SemVer but theirs is not, treat as outdated.
        if m1 and not o1 then
            return true
        end
    end

    local cmp = self:CompareSemVer(mine, otherVersion)
    if cmp == nil then return nil end
    return cmp == 1
end

---@param otherVersion string|nil
---@return boolean|nil newer True if otherVersion > ours, nil if not comparable
function guildSync:IsOtherVersionNewerThanMine(otherVersion)
    local mine = const and const.ADDON_VERSION or nil
    local cmp = self:CompareSemVer(otherVersion, mine)
    if cmp == nil then return nil end
    return cmp == 1
end

---@param otherVersion string|nil
---@param senderShort string|nil
function guildSync:MaybePrintSelfUpdateReminder(otherVersion, senderShort)
    local newer = self:IsOtherVersionNewerThanMine(otherVersion)
    if newer ~= true then return end

    local now = time()
    local last = tonumber(self.selfUpdateReminderLastAt) or 0
    local cooldown = self.SELF_UPDATE_REMINDER_COOLDOWN_SECONDS or (2 * 60 * 60)
    if (now - last) < cooldown then
        return
    end

    self.selfUpdateReminderLastAt = now
    self:SaveCachedData()

    local addon = Private.Addon
    if not addon or not addon.Print then return end

    local mine = const and const.ADDON_VERSION or "?"
    local theirs = otherVersion or "?"
    local who = senderShort or "a guild member"
    addon:Print(string.format(
        "Update available: you are on %s, %s is on %s. Update: https://www.curseforge.com/wow/addons/reckoning",
        tostring(mine),
        tostring(who),
        tostring(theirs)
    ))
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
    VERREQ = "GSYNC_VERREQ",          -- Version verify request (WHISPER)
    VERRESP = "GSYNC_VERRESP",        -- Version verify response (WHISPER)
    VERNOTIFIED = "GSYNC_VERNFY",     -- Someone already notified (GUILD)
    VERREMIND = "GSYNC_VERRMD",       -- Targeted reminder (GUILD; receiver prints locally)
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

    comms:AddCallback(MSG_TYPE.VERREQ, function(data)
        self:OnVersionRequest(data)
    end)

    comms:AddCallback(MSG_TYPE.VERRESP, function(data)
        self:OnVersionResponse(data)
    end)

    comms:AddCallback(MSG_TYPE.VERNOTIFIED, function(data)
        self:OnVersionNotified(data)
    end)

    comms:AddCallback(MSG_TYPE.VERREMIND, function(data)
        self:OnVersionRemind(data)
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
        self.versionNotifyCooldown = db.guildCache.versionNotifyCooldown or {}
        self.selfUpdateReminderLastAt = tonumber(db.guildCache.selfUpdateReminderLastAt) or 0

        -- Clean old events
        self:CleanOldEvents()

        -- Fix all cached "Unknown" versions (not just local player)
        -- This ensures roster displays fresh version data after release builds
        for playerName, member in pairs(self.memberData) do
            if member.version == "Unknown" then
                if playerName == UnitName("player") then
                    -- Update local player to current version
                    member.version = const.ADDON_VERSION or "Unknown"
                else
                    -- Mark other players as unknown until they sync fresh data
                    member.version = "Unknown"
                end
            end
        end

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

    -- IMPORTANT: do not clobber other guildCache fields (tickets, corrections, etc.)
    local cache = addon.Database.guildCache or {}
    cache.members = self.memberData
    cache.events = self.recentEvents
    cache.versionNotifyCooldown = self.versionNotifyCooldown
    cache.selfUpdateReminderLastAt = self.selfUpdateReminderLastAt
    cache.savedAt = time()
    addon.Database.guildCache = cache
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
            version = const.ADDON_VERSION or "Unknown",
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
        version = const.ADDON_VERSION or "Unknown",
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        timestamp = time(),
    }, "GUILD")

    self:SyncLog("HELLO sent (v=%s)", tostring(const.ADDON_VERSION or "?"))
end

function guildSync:RequestFullSync()
    if not IsInGuild() then return end

    local now = time()
    if now - self.lastSyncRequest < self.SYNC_COOLDOWN then
        return -- Don't spam requests
    end

    self.lastSyncRequest = now

    local requestId = tostring(now) .. "-" .. tostring(math.random(100000, 999999))
    Private.CommsUtils:SendMessage(MSG_TYPE.SYNC_REQUEST, {
        requester = UnitName("player"),
        requestId = requestId,
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        timestamp = now,
    }, "GUILD")

    self:SyncLog("SYNC_REQUEST sent (requestId=%s)", requestId)

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

    self:SyncLog("HELLO received from %s (v=%s)", senderShort, tostring(data.version or "?"))

    -- If they're outdated, schedule a verified update whisper (guild-deduped)
    self:MaybeScheduleVersionUpdateNudge(senderShort, data.sender, data.version)
end

-------------------------------------------------------------------------------
-- Version Update Nudges (verified + guild-deduped)
-------------------------------------------------------------------------------

---@param shortName string
function guildSync:CancelPendingVersionCheck(shortName)
    local state = self.pendingVersionChecks and self.pendingVersionChecks[shortName]
    if not state then return end

    if state.timer and state.timer.Cancel then
        state.timer:Cancel()
    end
    if state.verifyTimer and state.verifyTimer.Cancel then
        state.verifyTimer:Cancel()
    end
    self.pendingVersionChecks[shortName] = nil
end

---@param shortName string
---@param now number
---@return boolean
function guildSync:IsNotifySuppressed(shortName, now)
    if not shortName or shortName == "" then return true end
    now = now or time()

    local last = self.recentNotified and self.recentNotified[shortName] or nil
    if not last then
        last = self.versionNotifyCooldown and self.versionNotifyCooldown[shortName] or nil
    end

    if not last then return false end
    return (now - last) < (self.VERSION_NOTIFY_COOLDOWN_SECONDS or (24 * 60 * 60))
end

---@param shortName string
---@param notifiedAt number
function guildSync:MarkNotified(shortName, notifiedAt)
    if not shortName or shortName == "" then return end
    local t = notifiedAt or time()
    self.recentNotified[shortName] = t
    self.versionNotifyCooldown[shortName] = t
end

---@param shortName string
---@param whisperTarget string|nil
---@param theirVersion string|nil
function guildSync:MaybeScheduleVersionUpdateNudge(shortName, whisperTarget, theirVersion)
    if not shortName or shortName == "" then return end

    local newer = self:IsMyVersionNewerThan(theirVersion)
    if newer ~= true then
        self:SyncLog("VersionNudge: not scheduling for %s (theirVersion=%s, newer=%s)", tostring(shortName), tostring(theirVersion), tostring(newer))
        return
    end

    local now = time()
    if self:IsNotifySuppressed(shortName, now) then
        self:SyncLog("VersionNudge: suppressed for %s (cooldown active)", tostring(shortName))
        return
    end

    -- If a check is already scheduled, don't schedule another.
    if self.pendingVersionChecks[shortName] then
        self:SyncLog("VersionNudge: already pending for %s", tostring(shortName))
        return
    end

    local delayMin = self.VERSION_NOTIFY_MIN_DELAY or 5
    local delayMax = self.VERSION_NOTIFY_MAX_DELAY or 25
    if delayMax < delayMin then delayMax = delayMin end
    local delay = math.random(delayMin, delayMax)

    local timer = C_Timer.NewTimer(delay, function()
        self:StartVersionVerify(shortName, whisperTarget)
    end)

    self:SyncLog("VersionNudge: scheduled verify for %s in %ds (theirVersion=%s)", tostring(shortName), tonumber(delay) or 0, tostring(theirVersion))
    self.pendingVersionChecks[shortName] = {
        timer = timer,
        requestId = nil,
        requestedAt = nil,
        whisperTarget = whisperTarget or shortName,
        verifyTimer = nil,
    }
end

---@param shortName string
---@param whisperTarget string|nil
function guildSync:StartVersionVerify(shortName, whisperTarget)
    if not shortName or shortName == "" then return end

    local now = time()
    if self:IsNotifySuppressed(shortName, now) then
        self:SyncLog("VersionNudge: verify aborted for %s (suppressed)", tostring(shortName))
        self:CancelPendingVersionCheck(shortName)
        return
    end

    local member = self.memberData and self.memberData[shortName] or nil
    local theirVersion = member and member.version or nil
    local newer = self:IsMyVersionNewerThan(theirVersion)
    if newer ~= true then
        self:SyncLog("VersionNudge: verify aborted for %s (theirVersion=%s, newer=%s)", tostring(shortName), tostring(theirVersion), tostring(newer))
        self:CancelPendingVersionCheck(shortName)
        return
    end

    local comms = Private.CommsUtils
    if not comms then
        self:CancelPendingVersionCheck(shortName)
        return
    end

    local state = self.pendingVersionChecks[shortName] or {}
    local target = whisperTarget or state.whisperTarget or shortName
    local requestId = tostring(now) .. "-" .. tostring(math.random(100000, 999999))

    state.requestId = requestId
    state.requestedAt = now
    state.whisperTarget = target

    -- Send a direct version verify request before whispering (prevents false positives)
    comms:SendMessage(MSG_TYPE.VERREQ, {
        requestId = requestId,
        requester = UnitName("player"),
        requesterVersion = const.ADDON_VERSION or "Unknown",
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        timestamp = now,
    }, "WHISPER", target)
    self:SyncLog("VersionNudge: sent VERREQ to %s (short=%s requestId=%s)", tostring(target), tostring(shortName), tostring(requestId))

    -- Timeout cleanup if they never respond (no addon / blocked comms)
    state.verifyTimer = C_Timer.NewTimer(8, function()
        local s = self.pendingVersionChecks[shortName]
        if s and s.requestId == requestId then
            self:SyncLog("VersionNudge: VERRESP timeout for %s (requestId=%s)", tostring(shortName), tostring(requestId))
            self.pendingVersionChecks[shortName] = nil
        end
    end)

    self.pendingVersionChecks[shortName] = state
end

function guildSync:OnVersionRequest(data)
    if not data then return end
    if not self:IsProtocolCompatible(data) then return end

    local comms = Private.CommsUtils
    if not comms then return end

    local sender = data.sender
    if not sender or sender == "" then return end

    self:SyncLog("VersionNudge: received VERREQ from %s (requestId=%s)", tostring(sender), tostring(data.requestId))
    comms:SendMessage(MSG_TYPE.VERRESP, {
        requestId = data.requestId,
        version = const.ADDON_VERSION or "Unknown",
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        timestamp = time(),
    }, "WHISPER", sender)
end

function guildSync:OnVersionResponse(data)
    if not data then return end
    if not self:IsProtocolCompatible(data) then return end

    local senderShort = self:ShortNameFromSender(data.sender) or nil
    if not senderShort or senderShort == "" then return end

    local state = self.pendingVersionChecks[senderShort]
    if not state or not state.requestId then return end
    if data.requestId and data.requestId ~= state.requestId then return end

    self:SyncLog("VersionNudge: received VERRESP from %s (v=%s requestId=%s)", tostring(senderShort), tostring(data.version), tostring(data.requestId))

    local now = time()
    if self:IsNotifySuppressed(senderShort, now) then
        self:CancelPendingVersionCheck(senderShort)
        return
    end

    -- Verify again using the responder's own version (avoid HELLO false positives)
    local newer = self:IsMyVersionNewerThan(data.version)
    if newer ~= true then
        self:SyncLog("VersionNudge: not whispering %s (theirVersion=%s newer=%s)", tostring(senderShort), tostring(data.version), tostring(newer))
        self:CancelPendingVersionCheck(senderShort)
        return
    end

    local comms = Private.CommsUtils
    if not comms then
        self:CancelPendingVersionCheck(senderShort)
        return
    end

    local myVersion = const.ADDON_VERSION or "Unknown"
    local theirVersion = data.version or "?"
    local me = UnitName("player") or ""

    -- Guild-wide targeted reminder. Receiver will apply 24h cooldown and print locally as a "fake whisper".
    comms:SendMessage(MSG_TYPE.VERREMIND, {
        targetName = senderShort,
        by = me,
        myVersion = myVersion,
        theirVersion = theirVersion,
        requestId = state.requestId,
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        timestamp = now,
    }, "GUILD")
    self:SyncLog("VersionNudge: sent VERREMIND for %s (by=%s their=%s mine=%s)", tostring(senderShort), tostring(me), tostring(theirVersion), tostring(myVersion))

    self:CancelPendingVersionCheck(senderShort)
end

function guildSync:OnVersionNotified(data)
    if not data or not data.targetName then return end
    if not self:IsProtocolCompatible(data) then return end

    local targetShort = data.targetName
    local notifiedAt = tonumber(data.notifiedAt) or time()

    self:MarkNotified(targetShort, notifiedAt)
    self:CancelPendingVersionCheck(targetShort)
    self:SaveCachedData()
end

function guildSync:OnVersionRemind(data)
    if not data or not data.targetName then return end
    if not self:IsProtocolCompatible(data) then return end
    if not IsInGuild() then return end

    local me = UnitName("player")
    if not me or me == "" then return end

    if tostring(data.targetName) ~= tostring(me) then
        return
    end

    local now = time()
    if self:IsNotifySuppressed(me, now) then
        return
    end

    local by = tostring(data.by or (self:ShortNameFromSender(data.sender) or data.sender) or "Someone")
    local myVersion = tostring(data.myVersion or "?")
    local theirVersion = tostring(data.theirVersion or "?")

    self:MarkNotified(me, now)
    self:SaveCachedData()

    -- Broadcast suppression so the guild stops prompting for 24h.
    local comms = Private.CommsUtils
    if comms then
        comms:SendMessage(MSG_TYPE.VERNOTIFIED, {
            targetName = me,
            notifiedAt = now,
            by = by,
            myVersion = myVersion,
            theirVersion = theirVersion,
            protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
            timestamp = now,
        }, "GUILD")
    end

    -- Print a "fake whisper" locally (pink whisper color).
    local msg = string.format(
        "Hey, just a heads up — your Reckoning addon looks outdated (you: %s, latest: %s). Update: https://www.curseforge.com/wow/addons/reckoning",
        theirVersion,
        myVersion
    )
    local prefix = string.format("[%s] whispers: ", by)
    local color = (type(ChatTypeInfo) == "table" and ChatTypeInfo.WHISPER) or nil
    local r = (color and color.r) or 1
    local g = (color and color.g) or 0.5
    local b = (color and color.b) or 1

    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage(prefix .. msg, r, g, b)
    else
        print(prefix .. msg)
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
    self:SyncLog("SYNC_REQUEST received from %s (requestId=%s). Responding in %ds", tostring(requester), tostring(requestId), delay)
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
    local addon = Private.Addon
    local db = addon and addon.Database
    local correctionSync = Private.CorrectionSyncUtils

    -- Calculate total points (correction- and version-aware)
    local totalPoints = 0
    if correctionSync and correctionSync.ShouldCountAchievementPoints then
        local completed = (db and db.completed) or {}
        for achievementId, completedAt in pairs(completions) do
            local achievement = Private.AchievementUtils:GetAchievement(achievementId)
            if achievement then
                local rec = completed[achievementId]
                local ver = rec and rec.addonVersion and tostring(rec.addonVersion) or nil
                if correctionSync:ShouldCountAchievementPoints(achievementId, completedAt, ver) then
                    totalPoints = totalPoints + (achievement.points or 0)
                end
            end
        end
    else
        for achievementId, _ in pairs(completions) do
            local achievement = Private.AchievementUtils:GetAchievement(achievementId)
            if achievement then totalPoints = totalPoints + (achievement.points or 0) end
        end
    end

    -- Build our data packet (only our own completions - no cache re-broadcast for scalability)
    local myData = {
        name = playerName,
        class = className,
        classId = classId,
        version = const.ADDON_VERSION or "Unknown",
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
        self:SyncLog("SYNC_RESPONSE sent (single) completions=%d points=%d requestId=%s", (function()
            local c = 0
            for _ in pairs(completions or {}) do c = c + 1 end
            return c
        end)(), tonumber(totalPoints or 0) or 0, tostring(requestId or ""))
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
    local chunksSent = 0

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
        chunksSent = chunksSent + 1

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
            chunksSent = chunksSent + 1
        end
    end

    self:SyncLog(
        "SYNC_RESPONSE sent (chunked) completions=%d chunks=%d requestId=%s",
        tonumber(total or 0) or 0,
        tonumber(chunksSent or 0) or 0,
        tostring(requestId or "")
    )
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

    local comps = data.myData and data.myData.completions
    local compCount = 0
    if type(comps) == "table" then
        for _ in pairs(comps) do compCount = compCount + 1 end
    end
    local who = (data.myData and data.myData.name) or (self:ShortNameFromSender(data.sender)) or "unknown"
    self:SyncLog("SYNC_RESPONSE received from %s (single) completions=%d", tostring(who), tonumber(compCount or 0) or 0)
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

    local sliceCount = 0
    if data.myData and type(data.myData.completions) == "table" then
        for _ in pairs(data.myData.completions) do sliceCount = sliceCount + 1 end
    end
    self:SyncLog(
        "SYNC_CHUNK received from %s requestId=%s seq=%d%s slice=%d",
        tostring(senderShort),
        tostring(requestId),
        tonumber(seq) or 0,
        data.isLast and " (last)" or "",
        tonumber(sliceCount) or 0
    )

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

        self:SyncLog("SYNC_CHUNK completed from %s requestId=%s totalChunks=%d", tostring(senderShort), tostring(requestId), tonumber(state.lastSeq) or 0)
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
        member.completionVersions = member.completionVersions or {}
        member.completionVersions[data.achievementId] = (data.version and tostring(data.version)) or member.version
        member.lastSeen = time()

        self:RecalculateMemberPoints(member)
    end

    -- Save and update UI
    self:SaveCachedData()
    self:NotifyUIUpdate()

    local debugUtils = Private.DebugUtils
    if debugUtils then
        local achievement = Private.AchievementUtils:GetAchievement(data.achievementId)
        debugUtils:Log("GUILD", "%s completed: %s", senderShort, achievement and achievement.name or "Unknown")
    end

    self:SyncLog("COMPLETION received: %s achievementId=%s", tostring(senderShort), tostring(data.achievementId))
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

    -- Heartbeats can be noisy; only log occasionally per sender.
    self._showLogsLastHeartbeat = self._showLogsLastHeartbeat or {}
    local last = self._showLogsLastHeartbeat[senderShort] or 0
    if (now - last) >= 10 then
        self._showLogsLastHeartbeat[senderShort] = now
        local sliceCount = 0
        for _ in pairs(data.myData.completions or {}) do sliceCount = sliceCount + 1 end
        self:SyncLog("HEARTBEAT received from %s slice=%d", tostring(senderShort), tonumber(sliceCount) or 0)
    end
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
        -- New member: use newData.version as completion version for all (sync/heartbeat don't send per-completion version)
        local completions = newData.completions or {}
        local completionVersions = {}
        for achievementId, _ in pairs(completions) do
            completionVersions[achievementId] = newData.version
        end
        local newMember = {
            name = name,
            class = newData.class,
            classId = newData.classId,
            version = newData.version,
            lastSeen = newData.lastSeen or time(),
            completions = completions,
            completionVersions = completionVersions,
            totalPoints = 0,
        }
        self.memberData[name] = newMember
        self:RecalculateMemberPoints(newMember)
    else
        -- Merge with existing - prefer newer data
        if (newData.lastSeen or 0) >= (existing.lastSeen or 0) then
            existing.class = newData.class or existing.class
            existing.classId = newData.classId or existing.classId
            existing.version = newData.version or existing.version
            existing.lastSeen = newData.lastSeen or existing.lastSeen
        end

        -- Merge completions - keep newest timestamp; use newData.version for merged entries when we don't have exact version
        if newData.completions then
            existing.completions = existing.completions or {}
            existing.completionVersions = existing.completionVersions or {}
            for achievementId, timestamp in pairs(newData.completions) do
                local existingTimestamp = existing.completions[achievementId]
                if not existingTimestamp or timestamp > existingTimestamp then
                    existing.completions[achievementId] = timestamp
                    existing.completionVersions[achievementId] = existing.completionVersions[achievementId] or newData.version or existing.version
                end
            end
            self:RecalculateMemberPoints(existing)
        end
    end

    -- If we see someone with a newer version than ours, remind (throttled)
    if name ~= UnitName("player") then
        self:MaybePrintSelfUpdateReminder(newData.version or (existing and existing.version), name)
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

    -- If we see someone with a newer version than ours, remind (throttled)
    if name ~= UnitName("player") then
        self:MaybePrintSelfUpdateReminder(info and info.version, name)
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

    -- Update our own member data (completions + completionVersions from db for correction gating)
    local engine = Private.AchievementEngine
    if engine then
        local completions = engine:GetAllCompletedWithTimestamps()
        local addon = Private.Addon
        local db = addon and addon.Database
        local completed = (db and db.completed) or {}
        local completionVersions = {}
        for id, _ in pairs(completions) do
            local rec = completed[id]
            completionVersions[id] = (rec and rec.addonVersion and tostring(rec.addonVersion)) or const.ADDON_VERSION
        end

        local member = self.memberData[playerName]
        if not member then
            self.memberData[playerName] = {
                name = playerName,
                class = className,
                classId = 0,
                version = const.ADDON_VERSION or "Unknown",
                lastSeen = timestamp,
                completions = completions,
                completionVersions = completionVersions,
                totalPoints = 0,
            }
            member = self.memberData[playerName]
        else
            member.completions = completions
            member.completionVersions = completionVersions
            member.version = const.ADDON_VERSION or "Unknown"
            member.lastSeen = timestamp
        end
        self:RecalculateMemberPoints(member)

        -- Ensure heartbeat data is rebuilt soon (we have new completion state).
        self._heartbeatLastRebuild = 0
    end

    -- Broadcast to guild (include version for correction/version gating)
    Private.CommsUtils:SendMessage(MSG_TYPE.COMPLETION, {
        achievementId = achievementId,
        playerName = playerName,
        playerClass = className,
        protocolVersion = const.ADDON_COMMS.PROTOCOL_VERSION,
        timestamp = timestamp,
        version = const.ADDON_VERSION or "Unknown",
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
            aVal, bVal = a.version or "Unknown", b.version or "Unknown"
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
        if member.version and member.version ~= "Unknown" then
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

---Stop the heartbeat ticker (e.g. when leaving guild). Safe to call when not running.
function guildSync:StopHeartbeat()
    if self.heartbeatTicker and self.heartbeatTicker.Cancel then
        self.heartbeatTicker:Cancel()
    end
    self.heartbeatTicker = nil
end

---Clear in-memory guild sync state and persist empty cache. Call when leaving or switching guild.
function guildSync:WipeGuildSyncState()
    self.memberData = {}
    self.recentEvents = {}
    self.recentNotified = {}
    self.versionNotifyCooldown = {}
    self.pendingChunks = {}
    self.lastResponseToRequester = {}
    self.initialSyncDone = false

    for shortName in pairs(self.pendingVersionChecks or {}) do
        self:CancelPendingVersionCheck(shortName)
    end
    self.pendingVersionChecks = {}

    self:SaveCachedData()
    self:NotifyUIUpdate()
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
