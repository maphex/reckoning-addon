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
}
Private.GuildSyncUtils = guildSync

-- Message types for guild sync
local MSG_TYPE = {
    SYNC_REQUEST = "GSYNC_REQ",       -- Request sync from guild
    SYNC_RESPONSE = "GSYNC_RESP",     -- Response with our data
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

    self.initialSyncDone = true
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

    -- Don't process our own messages
    if data.name == UnitName("player") then return end

    -- Update member data
    self:UpdateMemberInfo(data.name, {
        class = data.class,
        classId = data.classId,
        version = data.version,
        lastSeen = data.timestamp or time(),
    })

    local debugUtils = Private.DebugUtils
    if debugUtils then
        debugUtils:Log("GUILD", "Received hello from %s (v%s)", data.name, data.version or "?")
    end
end

function guildSync:OnSyncRequest(data)
    if not data then return end

    -- Someone requested sync - send them our data
    -- Add a random delay to prevent everyone responding at once
    local delay = math.random(1, 5)
    C_Timer.After(delay, function()
        self:SendSyncResponse(data.requester)
    end)
end

function guildSync:SendSyncResponse(targetPlayer)
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

    -- Build our data packet
    local myData = {
        name = playerName,
        class = className,
        classId = classId,
        version = const.ADDON_VERSION or "1.0.0",
        lastSeen = time(),
        completions = completions,
        totalPoints = totalPoints,
    }

    -- Also include cached data from others (so offline players' data propagates)
    local cachedMembers = {}
    for name, memberData in pairs(self.memberData) do
        if name ~= playerName then
            cachedMembers[name] = memberData
        end
    end

    Private.CommsUtils:SendMessage(MSG_TYPE.SYNC_RESPONSE, {
        myData = myData,
        cachedMembers = cachedMembers,
        timestamp = time(),
    }, "GUILD")

    local debugUtils = Private.DebugUtils
    if debugUtils then
        local compCount = 0
        for _ in pairs(completions) do compCount = compCount + 1 end
        debugUtils:Log("GUILD", "Sent sync response: %d completions, %d points", compCount, totalPoints)
    end
end

function guildSync:OnSyncResponse(data)
    if not data then return end

    local debugUtils = Private.DebugUtils

    -- Process sender's own data
    if data.myData then
        self:MergeMemberData(data.myData)

        -- Add events for their completions
        if data.myData.completions then
            for achievementId, timestamp in pairs(data.myData.completions) do
                self:AddEvent(achievementId, data.myData.name, data.myData.class, timestamp)
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
                    self:AddEvent(achievementId, name, memberData.class, timestamp)
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

function guildSync:OnCompletionReceived(data)
    if not data or not data.achievementId then return end

    -- Don't process our own completions
    if data.playerName == UnitName("player") then return end

    -- Add the event
    self:AddEvent(data.achievementId, data.playerName, data.playerClass, data.timestamp or time())

    -- Update member's completion data
    local member = self.memberData[data.playerName]
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
        debugUtils:Log("GUILD", "%s completed: %s", data.playerName, achievement and achievement.name or "Unknown")
    end
end

function guildSync:OnRosterRequest(data)
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
        timestamp = time(),
    }, "GUILD")
end

function guildSync:OnRosterResponse(data)
    if not data or not data.roster then return end

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
    end

    -- Broadcast to guild
    Private.CommsUtils:SendMessage(MSG_TYPE.COMPLETION, {
        achievementId = achievementId,
        playerName = playerName,
        playerClass = className,
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
