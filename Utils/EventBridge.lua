---@class AddonPrivate
local Private = select(2, ...)

local Enums = Private.Enums

-------------------------------------------------------------------------------
-- Bridge Event Types (matches docs/events)
-------------------------------------------------------------------------------

---@alias BridgeEvent
---| "DUNGEON_BOSS_KILLED"
---| "DUNGEON_CLEARED"
---| "DUNGEON_ENCOUNTER_START"
---| "DUNGEON_MECHANIC_FAILED"
---| "INSTANCE_ENTERED"
---| "PVP_KILL"
---| "PVP_KILLING_BLOW"
---| "BATTLEGROUND_MATCH_END"
---| "BATTLEGROUND_MATCH_START"
---| "ARENA_MATCH_END"
---| "ARENA_RATING_MILESTONE"
---| "PVP_OBJECTIVE_CAPTURED"
---| "PVP_TOKEN_EARNED"
---| "ITEM_CRAFTED"
---| "RESOURCE_GATHERED"
---| "SKILL_UP"
---| "ITEM_DISENCHANTED"
---| "FISH_CAUGHT"
---| "QUEST_COMPLETED"
---| "REPUTATION_GAINED"
---| "RING_ENCHANTED"
---| "BADGE_EARNED"
---| "KEY_OBTAINED"
---| "EPIC_GEAR_EQUIPPED"
---| "EMOTE_SENT"
---| "LOOT_ROLL_WON"
---| "ZONE_EXPLORED"
---| "GOLD_MILESTONE"
---| "LEVEL_UP"
---| "CREATURE_KILLED"
---| "FALL_SURVIVED"
---| "PRIMAL_LOOTED"
---| "ITEM_LOOTED"
---| "TREASURE_CHEST_LOOTED"
---| "PLAYER_DIED"
---| "WEEKLY_RESET"
---| "ACHIEVEMENT_COMPLETED"
---| "RUNNING_2_MINUTES"

-------------------------------------------------------------------------------
-- Boss Tracking Data (TBC bosses by instance)
-------------------------------------------------------------------------------

-- Lookup table for boss NPCs by instance
-- Format: [npcId] = { name = "Boss Name", instance = "Instance Name", isFinalBoss = bool }
local BOSS_DATA = {
    -- Shadow Labyrinth
    [18731] = { name = "Ambassador Hellmaw", instance = "Shadow Labyrinth", isFinalBoss = false },
    [18667] = { name = "Blackheart the Inciter", instance = "Shadow Labyrinth", isFinalBoss = false },
    [18732] = { name = "Grandmaster Vorpil", instance = "Shadow Labyrinth", isFinalBoss = false },
    [18708] = { name = "Murmur", instance = "Shadow Labyrinth", isFinalBoss = true },

    -- The Underbog
    [17770] = { name = "Hungarfen", instance = "The Underbog", isFinalBoss = false },
    [18105] = { name = "Ghaz'an", instance = "The Underbog", isFinalBoss = false },
    [17826] = { name = "Swamplord Musel'ek", instance = "The Underbog", isFinalBoss = false },
    [17882] = { name = "The Black Stalker", instance = "The Underbog", isFinalBoss = true },

    -- Karazhan
    [15550] = { name = "Attumen the Huntsman", instance = "Karazhan", isFinalBoss = false },
    [16457] = { name = "Moroes", instance = "Karazhan", isFinalBoss = false },
    [16812] = { name = "Maiden of Virtue", instance = "Karazhan", isFinalBoss = false },
    [17521] = { name = "The Big Bad Wolf", instance = "Karazhan", isFinalBoss = false },
    [18168] = { name = "The Crone", instance = "Karazhan", isFinalBoss = false },
    [17561] = { name = "Julianne", instance = "Karazhan", isFinalBoss = false },
    [16816] = { name = "Chess Event", instance = "Karazhan", isFinalBoss = false },
    [16179] = { name = "Hyakiss the Lurker", instance = "Karazhan", isFinalBoss = false },
    [15691] = { name = "The Curator", instance = "Karazhan", isFinalBoss = false },
    [15688] = { name = "Terestian Illhoof", instance = "Karazhan", isFinalBoss = false },
    [16524] = { name = "Shade of Aran", instance = "Karazhan", isFinalBoss = false },
    [15689] = { name = "Netherspite", instance = "Karazhan", isFinalBoss = false },
    [15690] = { name = "Prince Malchezaar", instance = "Karazhan", isFinalBoss = true },
    [17225] = { name = "Nightbane", instance = "Karazhan", isFinalBoss = false },

    -- Gruul's Lair
    [18831] = { name = "High King Maulgar", instance = "Gruul's Lair", isFinalBoss = false },
    [19044] = { name = "Gruul the Dragonkiller", instance = "Gruul's Lair", isFinalBoss = true },

    -- Magtheridon's Lair
    [17257] = { name = "Magtheridon", instance = "Magtheridon's Lair", isFinalBoss = true },

    -- Serpentshrine Cavern
    [21216] = { name = "Hydross the Unstable", instance = "Serpentshrine Cavern", isFinalBoss = false },
    [21217] = { name = "The Lurker Below", instance = "Serpentshrine Cavern", isFinalBoss = false },
    [21215] = { name = "Leotheras the Blind", instance = "Serpentshrine Cavern", isFinalBoss = false },
    [21214] = { name = "Fathom-Lord Karathress", instance = "Serpentshrine Cavern", isFinalBoss = false },
    [21213] = { name = "Morogrim Tidewalker", instance = "Serpentshrine Cavern", isFinalBoss = false },
    [21212] = { name = "Lady Vashj", instance = "Serpentshrine Cavern", isFinalBoss = true },

    -- Tempest Keep: The Eye
    [19514] = { name = "Al'ar", instance = "Tempest Keep", isFinalBoss = false },
    [19516] = { name = "Void Reaver", instance = "Tempest Keep", isFinalBoss = false },
    [18805] = { name = "High Astromancer Solarian", instance = "Tempest Keep", isFinalBoss = false },
    [19622] = { name = "Kael'thas Sunstrider", instance = "Tempest Keep", isFinalBoss = true },

    -- Hyjal Summit
    [17767] = { name = "Rage Winterchill", instance = "Hyjal Summit", isFinalBoss = false },
    [17808] = { name = "Anetheron", instance = "Hyjal Summit", isFinalBoss = false },
    [17888] = { name = "Kaz'rogal", instance = "Hyjal Summit", isFinalBoss = false },
    [17842] = { name = "Azgalor", instance = "Hyjal Summit", isFinalBoss = false },
    [17968] = { name = "Archimonde", instance = "Hyjal Summit", isFinalBoss = true },

    -- Black Temple
    [22887] = { name = "High Warlord Naj'entus", instance = "Black Temple", isFinalBoss = false },
    [22898] = { name = "Supremus", instance = "Black Temple", isFinalBoss = false },
    [22841] = { name = "Shade of Akama", instance = "Black Temple", isFinalBoss = false },
    [22871] = { name = "Teron Gorefiend", instance = "Black Temple", isFinalBoss = false },
    [22948] = { name = "Gurtogg Bloodboil", instance = "Black Temple", isFinalBoss = false },
    [23418] = { name = "Reliquary of Souls", instance = "Black Temple", isFinalBoss = false },
    [22947] = { name = "Mother Shahraz", instance = "Black Temple", isFinalBoss = false },
    [22949] = { name = "The Illidari Council", instance = "Black Temple", isFinalBoss = false },
    [22917] = { name = "Illidan Stormrage", instance = "Black Temple", isFinalBoss = true },

    -- Sunwell Plateau
    [24891] = { name = "Kalecgos", instance = "Sunwell Plateau", isFinalBoss = false },
    [24882] = { name = "Brutallus", instance = "Sunwell Plateau", isFinalBoss = false },
    [25038] = { name = "Felmyst", instance = "Sunwell Plateau", isFinalBoss = false },
    [25166] = { name = "The Eredar Twins", instance = "Sunwell Plateau", isFinalBoss = false },
    [25741] = { name = "M'uru", instance = "Sunwell Plateau", isFinalBoss = false },
    [25315] = { name = "Kil'jaeden", instance = "Sunwell Plateau", isFinalBoss = true },

    -- Zul'Aman
    [23574] = { name = "Akil'zon", instance = "Zul'Aman", isFinalBoss = false },
    [23576] = { name = "Nalorakk", instance = "Zul'Aman", isFinalBoss = false },
    [23578] = { name = "Jan'alai", instance = "Zul'Aman", isFinalBoss = false },
    [23577] = { name = "Halazzi", instance = "Zul'Aman", isFinalBoss = false },
    [24239] = { name = "Hex Lord Malacrass", instance = "Zul'Aman", isFinalBoss = false },
    [23863] = { name = "Zul'jin", instance = "Zul'Aman", isFinalBoss = true },

    -- Hellfire Citadel: Hellfire Ramparts
    [17306] = { name = "Watchkeeper Gargolmar", instance = "Hellfire Ramparts", isFinalBoss = false },
    [17308] = { name = "Omor the Unscarred", instance = "Hellfire Ramparts", isFinalBoss = false },
    [17537] = { name = "Vazruden", instance = "Hellfire Ramparts", isFinalBoss = true },

    -- Hellfire Citadel: Blood Furnace
    [17381] = { name = "The Maker", instance = "The Blood Furnace", isFinalBoss = false },
    [17380] = { name = "Broggok", instance = "The Blood Furnace", isFinalBoss = false },
    [17377] = { name = "Keli'dan the Breaker", instance = "The Blood Furnace", isFinalBoss = true },

    -- Hellfire Citadel: Shattered Halls
    [16807] = { name = "Grand Warlock Nethekurse", instance = "The Shattered Halls", isFinalBoss = false },
    [20923] = { name = "Blood Guard Porung", instance = "The Shattered Halls", isFinalBoss = false },
    [16809] = { name = "Warbringer O'mrogg", instance = "The Shattered Halls", isFinalBoss = false },
    [16808] = { name = "Warchief Kargath Bladefist", instance = "The Shattered Halls", isFinalBoss = true },

    -- Coilfang Reservoir: Slave Pens
    [17941] = { name = "Mennu the Betrayer", instance = "The Slave Pens", isFinalBoss = false },
    [17991] = { name = "Rokmar the Crackler", instance = "The Slave Pens", isFinalBoss = false },
    [17942] = { name = "Quagmirran", instance = "The Slave Pens", isFinalBoss = true },

    -- Coilfang Reservoir: Steamvault
    [17797] = { name = "Hydromancer Thespia", instance = "The Steamvault", isFinalBoss = false },
    [17796] = { name = "Mekgineer Steamrigger", instance = "The Steamvault", isFinalBoss = false },
    [17798] = { name = "Warlord Kalithresh", instance = "The Steamvault", isFinalBoss = true },

    -- Auchindoun: Mana-Tombs
    [18341] = { name = "Pandemonius", instance = "Mana-Tombs", isFinalBoss = false },
    [18343] = { name = "Tavarok", instance = "Mana-Tombs", isFinalBoss = false },
    [18344] = { name = "Nexus-Prince Shaffar", instance = "Mana-Tombs", isFinalBoss = true },

    -- Auchindoun: Auchenai Crypts
    [18371] = { name = "Shirrak the Dead Watcher", instance = "Auchenai Crypts", isFinalBoss = false },
    [18373] = { name = "Exarch Maladaar", instance = "Auchenai Crypts", isFinalBoss = true },

    -- Auchindoun: Sethekk Halls
    [18472] = { name = "Darkweaver Syth", instance = "Sethekk Halls", isFinalBoss = false },
    [18473] = { name = "Talon King Ikiss", instance = "Sethekk Halls", isFinalBoss = true },
    [23035] = { name = "Anzu", instance = "Sethekk Halls", isFinalBoss = false },

    -- Tempest Keep: Mechanar
    [19218] = { name = "Mechano-Lord Capacitus", instance = "The Mechanar", isFinalBoss = false },
    [19219] = { name = "Nethermancer Sepethrea", instance = "The Mechanar", isFinalBoss = false },
    [19220] = { name = "Pathaleon the Calculator", instance = "The Mechanar", isFinalBoss = true },

    -- Tempest Keep: Botanica
    [17976] = { name = "Commander Sarannis", instance = "The Botanica", isFinalBoss = false },
    [17975] = { name = "High Botanist Freywinn", instance = "The Botanica", isFinalBoss = false },
    [17978] = { name = "Thorngrin the Tender", instance = "The Botanica", isFinalBoss = false },
    [17980] = { name = "Laj", instance = "The Botanica", isFinalBoss = false },
    [17977] = { name = "Warp Splinter", instance = "The Botanica", isFinalBoss = true },

    -- Tempest Keep: Arcatraz
    [20870] = { name = "Zereketh the Unbound", instance = "The Arcatraz", isFinalBoss = false },
    [20885] = { name = "Dalliah the Doomsayer", instance = "The Arcatraz", isFinalBoss = false },
    [20886] = { name = "Wrath-Scryer Soccothrates", instance = "The Arcatraz", isFinalBoss = false },
    [20912] = { name = "Harbinger Skyriss", instance = "The Arcatraz", isFinalBoss = true },

    -- Caverns of Time: Old Hillsbrad
    [17848] = { name = "Lieutenant Drake", instance = "Old Hillsbrad Foothills", isFinalBoss = false },
    [17862] = { name = "Captain Skarloc", instance = "Old Hillsbrad Foothills", isFinalBoss = false },
    [18096] = { name = "Epoch Hunter", instance = "Old Hillsbrad Foothills", isFinalBoss = true },

    -- Caverns of Time: Black Morass
    [17879] = { name = "Chrono Lord Deja", instance = "The Black Morass", isFinalBoss = false },
    [17880] = { name = "Temporus", instance = "The Black Morass", isFinalBoss = false },
    [17881] = { name = "Aeonus", instance = "The Black Morass", isFinalBoss = true },

    -- Magisters' Terrace
    [24723] = { name = "Selin Fireheart", instance = "Magisters' Terrace", isFinalBoss = false },
    [24744] = { name = "Vexallus", instance = "Magisters' Terrace", isFinalBoss = false },
    [24560] = { name = "Priestess Delrissa", instance = "Magisters' Terrace", isFinalBoss = false },
    [24664] = { name = "Kael'thas Sunstrider", instance = "Magisters' Terrace", isFinalBoss = true },
}

-- Lookup by boss name for convenience
local BOSS_BY_NAME = {}
for npcId, data in pairs(BOSS_DATA) do
    BOSS_BY_NAME[data.name] = { npcId = npcId, instance = data.instance, isFinalBoss = data.isFinalBoss }
end

-------------------------------------------------------------------------------
-- EventBridge Class
-------------------------------------------------------------------------------

---@class EventBridge
local eventBridge = {
    ---@type CallbackUtils
    cbUtils = {},
    ---@type table<string, boolean>
    registeredWowEvents = {},
    ---@type table
    dungeonState = {},
    ---@type table
    pvpState = {},
    ---@type table<number, boolean>
    killedBosses = {}, -- Track killed bosses this instance run
}
Private.EventBridge = eventBridge

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function eventBridge:Init()
    self.cbUtils = Private.CallbackUtils

    -- Create event frame
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        self:OnWowEvent(event, ...)
    end)
    self.eventFrame:SetScript("OnUpdate", function(_, elapsed)
        self:HandleFallUpdate(elapsed)
        self:HandleRunningUpdate(elapsed)
    end)

    -- Register TBC-compatible WoW events
    self:RegisterWowEvent("PLAYER_ENTERING_WORLD")
    self:RegisterWowEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterWowEvent("ZONE_CHANGED")
    self:RegisterWowEvent("ZONE_CHANGED_INDOORS")
    self:RegisterWowEvent("MAP_EXPLORATION_UPDATED")
    self:RegisterWowEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterWowEvent("PLAYER_LEVEL_UP")
    self:RegisterWowEvent("PLAYER_MONEY")
    self:RegisterWowEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
    self:RegisterWowEvent("CHAT_MSG_LOOT")
    self:RegisterWowEvent("QUEST_TURNED_IN")
    self:RegisterWowEvent("UPDATE_FACTION")
    self:RegisterWowEvent("PLAYER_EQUIPMENT_CHANGED")
    self:RegisterWowEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:RegisterWowEvent("LOOT_ROLLS_COMPLETE")
    self:RegisterWowEvent("UPDATE_BATTLEFIELD_SCORE")
    self:RegisterWowEvent("UNIT_THREAT_LIST_UPDATE")
    self:RegisterWowEvent("PLAYER_REGEN_ENABLED")
    self:RegisterWowEvent("PLAYER_REGEN_DISABLED")
    self:RegisterWowEvent("SKILL_LINES_CHANGED")
    self:RegisterWowEvent("TRADE_SKILL_UPDATE")
    self:RegisterWowEvent("CHAT_MSG_SKILL")
    self:RegisterWowEvent("CHAT_MSG_SYSTEM")
    self:RegisterWowEvent("CHAT_MSG_TEXT_EMOTE")
    self:RegisterWowEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
    self:RegisterWowEvent("CHAT_MSG_BG_SYSTEM_HORDE")
    self:RegisterWowEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
    self:RegisterWowEvent("BATTLEGROUND_POINTS_UPDATE")
    self:RegisterWowEvent("ARENA_TEAM_UPDATE")
    self:RegisterWowEvent("ARENA_TEAM_ROSTER_UPDATE")
    self:RegisterWowEvent("BAG_UPDATE")
    self:RegisterWowEvent("LOOT_OPENED")
    self:RegisterWowEvent("START_LOOT_ROLL")
    self:RegisterWowEvent("LOOT_SLOT_CLEARED")

    -- Initialize state
    self.dungeonState = {
        inInstance = false,
        instanceName = nil,
        instanceId = nil,
        difficulty = nil,
        startTime = nil,
        totalDeaths = 0,
        wipes = 0,
        encounterActive = false,
        currentBoss = nil,
        currentBossNpcId = nil,
        encounterStartTime = nil,
        bossesKilled = {},
        totalBossesInInstance = 0,
    }

    self.pvpState = {
        inBattleground = false,
        bgName = nil,
        kills = 0,
        killingBlows = 0,
        startTime = nil,
        flagCarriers = {},  -- [playerName] = true for current flag carriers (WSG/EOTS)
        pendingAssaults = {}, -- [objectiveName] = { player = string, time = number } for AB claim->capture
        pendingObjectiveInteraction = nil, -- { time = number, objectiveName = string } for AV capture correlation
    }

    self.fallingState = {
        isFalling = false,
        startTime = nil,
    }

    -- Track last known gold
    self.lastGold = GetMoney()
    self.lastGoldMilestone = math.floor(self.lastGold / 10000) -- In gold units

    -- Track explored zones (to avoid duplicate fires)
    self.exploredZones = {}

    -- Track skill levels for detecting skill-ups
    self.skillLevels = {}
    self:InitializeSkillTracking()

    -- Track reputation for detecting gains
    self.reputationStandings = {}
    self:InitializeReputationTracking()

    -- Track arena ratings
    self.arenaRatings = {}
    self:InitializeArenaTracking()

    -- Track keys in inventory
    self.knownKeys = {}
    self:InitializeKeyTracking()

    -- Track fishing state
    self.fishingState = {
        isFishing = false,
        castTime = nil,
    }

    -- Track crafting state
    self.craftingState = {
        lastCraftSpellId = nil,
        lastCraftTime = nil,
    }

    -- Track loot rolls
    self.activeLootRolls = {}

    -- Track disenchanting
    self.disenchantState = {
        isDisenchanting = false,
        targetItem = nil,
    }

    -- Easter egg: run 2 minutes nonstop (only track until achievement 9001 is completed)
    self.runningState = {
        seconds = 0,
        FAST_AF_BOIII_ACHIEVEMENT_ID = 9001,
    }
end

-------------------------------------------------------------------------------
-- WoW Event Registration
-------------------------------------------------------------------------------

---@param event string
function eventBridge:RegisterWowEvent(event)
    if not self.registeredWowEvents[event] then
        self.eventFrame:RegisterEvent(event)
        self.registeredWowEvents[event] = true
    end
end

-------------------------------------------------------------------------------
-- Bridge Event Registration
-------------------------------------------------------------------------------

---@param bridgeName BridgeEvent
---@param callback function
---@return CallbackObject|nil
function eventBridge:RegisterEvent(bridgeName, callback)
    return self.cbUtils:AddCallback("EventBridge_" .. bridgeName, callback)
end

---Fire a bridge event
---@param bridgeName BridgeEvent
---@param payload table
function eventBridge:Fire(bridgeName, payload)
    -- Debug logging
    if Private.DebugUtils then
        Private.DebugUtils:LogEvent(bridgeName, payload)
    end

    local callbacks = self.cbUtils:GetCallbacks("EventBridge_" .. bridgeName)
    for _, cb in ipairs(callbacks) do
        cb:Trigger(payload)
    end

    -- Also notify the achievement engine
    if Private.AchievementEngine then
        Private.AchievementEngine:OnBridgeEvent(bridgeName, payload)
    end
end

-------------------------------------------------------------------------------
-- WoW Event Handlers
-------------------------------------------------------------------------------

function eventBridge:OnWowEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        self:HandlePlayerEnteringWorld(...)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        self:HandleZoneChanged()
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        self:HandleSubZoneChanged()
    elseif event == "MAP_EXPLORATION_UPDATED" then
        self:HandleMapExplorationUpdated()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:HandleCombatLog(...) -- Pass args for TBC
    elseif event == "PLAYER_LEVEL_UP" then
        self:HandleLevelUp(...)
    elseif event == "PLAYER_MONEY" then
        self:HandleMoneyChanged()
    elseif event == "QUEST_TURNED_IN" then
        self:HandleQuestTurnedIn(...)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        self:HandleEquipmentChanged(...)
    elseif event == "UNIT_THREAT_LIST_UPDATE" then
        self:HandleThreatListUpdate(...)
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:HandleCombatEnd()
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:HandleCombatStart()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        self:HandleSpellcastSucceeded(...)
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        self:HandleBattlefieldUpdate()
    elseif event == "UPDATE_FACTION" then
        self:HandleReputationChanged()
    elseif event == "CHAT_MSG_LOOT" then
        self:HandleLootMessage(...)
    elseif event == "SKILL_LINES_CHANGED" or event == "TRADE_SKILL_UPDATE" then
        self:HandleSkillUpdate()
    elseif event == "CHAT_MSG_SKILL" then
        self:HandleSkillMessage(...)
    elseif event == "CHAT_MSG_SYSTEM" then
        self:HandleSystemMessage(...)
    elseif event == "CHAT_MSG_TEXT_EMOTE" then
        self:HandlePlayerEmote(...)
    elseif event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" or event == "CHAT_MSG_BG_SYSTEM_HORDE" or event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
        self:HandleBGSystemMessage(...)
    elseif event == "ARENA_TEAM_UPDATE" or event == "ARENA_TEAM_ROSTER_UPDATE" then
        self:HandleArenaTeamUpdate()
    elseif event == "BAG_UPDATE" then
        self:HandleBagUpdate(...)
    elseif event == "LOOT_OPENED" then
        self:HandleLootOpened()
    elseif event == "START_LOOT_ROLL" then
        self:HandleStartLootRoll(...)
    elseif event == "LOOT_ROLLS_COMPLETE" then
        self:HandleLootRollsComplete(...)
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        self:HandleHonorGain(...)
    elseif event == "LOOT_SLOT_CLEARED" then
        self:HandleLootSlotCleared(...)
    elseif event == "BATTLEGROUND_POINTS_UPDATE" then
        self:HandleBattlegroundPointsUpdate()
    end
end

-------------------------------------------------------------------------------
-- Instance Handling
-------------------------------------------------------------------------------

function eventBridge:HandlePlayerEnteringWorld(isInitialLogin, isReloadingUi)
    self:UpdateInstanceState()
end

function eventBridge:HandleZoneChanged()
    self:UpdateInstanceState()
    self:FireZoneExplored()
end

function eventBridge:HandleSubZoneChanged()
    self:FireZoneExplored()
end

function eventBridge:HandleMapExplorationUpdated()
    self:FireZoneExplored()
end

function eventBridge:FireZoneExplored()
    local zone = GetRealZoneText()
    local subZone = GetSubZoneText()

    if zone and zone ~= "" then
        -- Create unique key for this zone/subzone combo
        local key = zone .. "|" .. (subZone or "")

        -- Only fire if we haven't already fired for this zone
        if not self.exploredZones[key] then
            self.exploredZones[key] = true

            self:Fire("ZONE_EXPLORED", {
                zone = zone,
                subZone = subZone or "",
            })
        end
    end
end

function eventBridge:UpdateInstanceState()
    local inInstance, instanceType = IsInInstance()
    local instanceName, _, difficultyIndex, _, _, _, _, instanceId = GetInstanceInfo()

    local wasInInstance = self.dungeonState.inInstance
    local oldInstanceId = self.dungeonState.instanceId

    self.dungeonState.inInstance = inInstance and (instanceType == "party" or instanceType == "raid")

    if self.dungeonState.inInstance then
        -- Entering or already in instance
        if not wasInInstance or oldInstanceId ~= instanceId then
            -- New instance entered - reset state
            self.dungeonState.instanceName = instanceName
            self.dungeonState.instanceId = instanceId
            self.dungeonState.difficulty = difficultyIndex == 2 and Enums.Difficulty.Heroic or Enums.Difficulty.Normal
            self.dungeonState.startTime = GetTime()
            self.dungeonState.totalDeaths = 0
            self.dungeonState.wipes = 0
            self.dungeonState.bossesKilled = {}
            self.dungeonState.encounterActive = false
            self.dungeonState.currentBoss = nil

            -- Count bosses in this instance
            self.dungeonState.totalBossesInInstance = self:CountBossesInInstance(instanceName)

            self:Fire("INSTANCE_ENTERED", {
                instance = instanceName,
                instanceId = instanceId,
                difficulty = self.dungeonState.difficulty,
                raidSize = self:GetGroupSize(),
                timestamp = GetTime(),
            })
        end
    else
        -- Left instance
        if wasInInstance then
            self.dungeonState.inInstance = false
            self.dungeonState.instanceName = nil
            self.dungeonState.instanceId = nil
            self.dungeonState.bossesKilled = {}
        end
    end

    -- Check for battleground
    if instanceType == "pvp" then
        if not self.pvpState.inBattleground then
            self.pvpState.inBattleground = true
            self.pvpState.bgName = instanceName
            self.pvpState.startTime = GetTime()
            self.pvpState.kills = 0
            self.pvpState.killingBlows = 0
            self.pvpState.pendingAssaults = {}
            self.pvpState.pendingObjectiveInteraction = nil

            self:Fire("BATTLEGROUND_MATCH_START", {
                battleground = instanceName,
            })
        end
    elseif instanceType == "arena" then
        -- Arena match started
        if not self.arenaState.inArena then
            self.arenaState.inArena = true
            self.arenaState.startTime = GetTime()
            -- Detect bracket from number of players
            local numPlayers = GetNumPartyMembers and GetNumPartyMembers() or GetNumGroupMembers()
            if numPlayers then
                if numPlayers <= 2 then
                    self.arenaState.bracket = 2
                elseif numPlayers <= 3 then
                    self.arenaState.bracket = 3
                else
                    self.arenaState.bracket = 5
                end
            end
        end
    else
        -- Left BG/Arena
        if self.pvpState.inBattleground then
            -- BG ended without a winner detected - fire anyway
            self.pvpState.inBattleground = false
        end
        if self.arenaState and self.arenaState.inArena then
            -- Arena ended
            self:CheckArenaMatchEnd()
        end
    end
end

---Count how many bosses are in a given instance
---@param instanceName string
---@return number
function eventBridge:CountBossesInInstance(instanceName)
    local count = 0
    for _, data in pairs(BOSS_DATA) do
        if data.instance == instanceName then
            count = count + 1
        end
    end
    return count
end

-------------------------------------------------------------------------------
-- Boss Engagement via Threat (TBC-compatible)
-------------------------------------------------------------------------------

function eventBridge:HandleThreatListUpdate(unit)
    if not self.dungeonState.inInstance then return end
    if unit ~= "target" then return end

    -- Check if target is a boss
    local guid = UnitGUID("target")
    if not guid then return end

    local npcId = self:GetNpcIdFromGUID(guid)
    if not npcId then return end

    local bossData = BOSS_DATA[npcId]
    if not bossData then return end

    -- Check if we're in combat with this boss
    if UnitAffectingCombat("target") and not self.dungeonState.encounterActive then
        self.dungeonState.encounterActive = true
        self.dungeonState.currentBoss = bossData.name
        self.dungeonState.currentBossNpcId = npcId
        self.dungeonState.encounterStartTime = GetTime()
        self.dungeonState.encounterDeaths = 0  -- Reset deaths for this encounter
        self.dungeonState.mechanicFailCount = 0  -- Reset mechanic fails for this encounter

        self:Fire("DUNGEON_ENCOUNTER_START", {
            bossName = bossData.name,
            bossId = npcId,
            instance = self.dungeonState.instanceName or bossData.instance,
            instanceId = self.dungeonState.instanceId or 0,
            difficulty = self.dungeonState.difficulty or Enums.Difficulty.Normal,
            raidSize = self:GetGroupSize(),
            timestamp = GetTime(),
        })
    end
end

function eventBridge:HandleCombatStart()
    -- Combat started - could be boss engagement
    -- We primarily use UNIT_THREAT_LIST_UPDATE for boss detection
end

function eventBridge:HandleCombatEnd()
    -- Combat ended
    if self.dungeonState.encounterActive then
        -- If we're out of combat but boss didn't die, it's a wipe
        self.dungeonState.wipes = (self.dungeonState.wipes or 0) + 1
        self.dungeonState.encounterActive = false
        self.dungeonState.currentBoss = nil
        self.dungeonState.currentBossNpcId = nil
    end
end

-------------------------------------------------------------------------------
-- Fall Tracking (There goes my Hero)
-------------------------------------------------------------------------------

function eventBridge:HandleFallUpdate(elapsed)
    if type(IsFalling) ~= "function" or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        return
    end

    local const = Private.constants
    local minSeconds = const and const.FALLING and const.FALLING.MIN_SECONDS or 0

    local falling = IsFalling()
    if falling and not self.fallingState.isFalling then
        self.fallingState.isFalling = true
        self.fallingState.startTime = GetTime()
        return
    end

    if not falling and self.fallingState.isFalling then
        self.fallingState.isFalling = false
        local startTime = self.fallingState.startTime
        self.fallingState.startTime = nil

        if startTime then
            local duration = GetTime() - startTime
            if duration >= minSeconds then
                self:Fire("FALL_SURVIVED", {
                    duration = duration,
                    zone = GetZoneText() or "Unknown",
                })
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Running 2 minutes nonstop (Easter egg: Fast AF BOIII)
-- Only runs while achievement 9001 is not completed; stops tracking after completion.
-------------------------------------------------------------------------------
function eventBridge:HandleRunningUpdate(elapsed)
    -- Do not track running at all once the achievement is completed (saves work every frame)
    local aid = self.runningState and self.runningState.FAST_AF_BOIII_ACHIEVEMENT_ID or 9001
    local engine = Private.AchievementEngine
    if not engine or engine.completedAchievements[aid] then
        return
    end

    local isRunning = false
    if type(IsRunning) == "function" then
        isRunning = IsRunning()
    end
    if not isRunning and type(GetUnitSpeed) == "function" then
        local speed = GetUnitSpeed("player")
        if speed and speed > 5 then
            isRunning = true
        end
    end
    if type(IsMounted) == "function" and IsMounted() then
        isRunning = false
    end
    if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") then
        isRunning = false
    end

    if not isRunning then
        self.runningState.seconds = 0
        return
    end

    self.runningState.seconds = (self.runningState.seconds or 0) + elapsed
    if self.runningState.seconds >= 120 then
        self.runningState.seconds = 0
        self:Fire("RUNNING_2_MINUTES", {})
    end
end

-------------------------------------------------------------------------------
-- Combat Log Handling (Boss Deaths, PvP, Mechanics)
-- TBC combat log format: timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...
-------------------------------------------------------------------------------

---Check if a GUID belongs to a party or raid member (including the player)
---@param guid string
---@return boolean
function eventBridge:IsPartyOrRaidMemberGUID(guid)
    -- Check if it's the player
    if guid == UnitGUID("player") then
        return true
    end

    -- Check if in raid
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if UnitGUID("raid" .. i) == guid then
                return true
            end
        end

    -- Check if in party (5-man group)
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            if UnitGUID("party" .. i) == guid then
                return true
            end
        end
    end

    return false
end

function eventBridge:HandleCombatLog(...)
    local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags = CombatLogGetCurrentEventInfo()

    local playerGUID = UnitGUID("player")

    -- Handle unit deaths
    if subevent == "UNIT_DIED" then
        -- Player death tracking
        if destGUID == playerGUID then
            if self.dungeonState.inInstance then
                self.dungeonState.totalDeaths = self.dungeonState.totalDeaths + 1

                -- Track deaths during boss encounter
                if self.dungeonState.encounterActive then
                    self.dungeonState.encounterDeaths = (self.dungeonState.encounterDeaths or 0) + 1
                end
            end

            self:Fire("PLAYER_DIED", {
                inBattleground = self.pvpState.inBattleground or false,
                inArena = self.arenaState.inArena or false,
                location = GetZoneText() or "Unknown",
            })
        end

        -- Boss death detection
        local npcId = self:GetNpcIdFromGUID(destGUID)
        if npcId then
            local bossData = BOSS_DATA[npcId]
            if bossData then
                self:HandleBossDeath(npcId, bossData, destName)
            end
        end
    end

    -- Handle player killing blow in PvP
    if subevent == "PARTY_KILL" and sourceGUID == playerGUID then
        local destType = strsplit("-", destGUID)
        if destType == "Player" then
            self.pvpState.killingBlows = self.pvpState.killingBlows + 1

            local targetType = nil
            if self.pvpState.flagCarriers and self.pvpState.flagCarriers[destName] then
                targetType = "flag_carrier"
                self.pvpState.flagCarriers[destName] = nil
            end
            -- Also check name without realm (combat log may use "Name-Realm")
            local destNameShort = destName and (destName:gsub("%-.*", "")) or ""
            if not targetType and destNameShort ~= destName and self.pvpState.flagCarriers[destNameShort] then
                targetType = "flag_carrier"
                self.pvpState.flagCarriers[destNameShort] = nil
            end

            self:Fire("PVP_KILLING_BLOW", {
                victimClass = Private.UnitCache:GetClassByGUID(destGUID),
                victimLevel = Private.UnitCache:GetLevelByGUID(destGUID),
                location = GetZoneText() or "Unknown",
                targetType = targetType,
            })
        elseif destType == "Creature" then
            -- Regular creature kill
            local npcId = self:GetNpcIdFromGUID(destGUID)

            self:Fire("CREATURE_KILLED", {
                creatureName = destName,
                creatureId = npcId,
                level = Private.UnitCache:GetLevelByGUID(destGUID),
                creatureType = Private.UnitCache:GetCreatureTypeByGUID(destGUID),
            })
        end
    end

    -- Handle spell damage to party/raid members (mechanic fail detection)
    -- TBC spell info starts at arg 9: spellId, spellName, spellSchool
    if subevent == "SPELL_DAMAGE" and self:IsPartyOrRaidMemberGUID(destGUID) then
        if self.dungeonState.encounterActive then
            local spellId, spellName = select(9, ...)

            -- Track fail count for this encounter
            self.dungeonState.mechanicFailCount = (self.dungeonState.mechanicFailCount or 0) + 1

            -- Strip realm name if present (combat log may include "Name-Realm")
            local victimName = destName and (destName:gsub("%-.*", "")) or "Unknown"

            self:Fire("DUNGEON_MECHANIC_FAILED", {
                mechanicName = spellName or "Unknown",
                bossName = self.dungeonState.currentBoss or "Unknown",
                instance = self.dungeonState.instanceName or "Unknown",
                playerName = victimName,
                failCount = self.dungeonState.mechanicFailCount,
            })
        end
    end

    -- Handle honorable kills
    if subevent == "PARTY_KILL" then
        local destType = strsplit("-", destGUID)
        if destType == "Player" and self.pvpState.inBattleground then
            self.pvpState.kills = self.pvpState.kills + 1

            local isKillingBlow = (sourceGUID == playerGUID)
            self:Fire("PVP_KILL", {
                victimClass = Private.UnitCache:GetClassByGUID(destGUID),
                victimLevel = Private.UnitCache:GetLevelByGUID(destGUID),
                location = GetZoneText() or "Unknown",
                isKillingBlow = isKillingBlow,
                totalKills = self.pvpState.kills,
            })
        end
    end
end

---Handle boss death
---@param npcId number
---@param bossData table
---@param bossName string
function eventBridge:HandleBossDeath(npcId, bossData, bossName)
    -- Already killed this boss this run?
    if self.dungeonState.bossesKilled[npcId] then
        return
    end

    self.dungeonState.bossesKilled[npcId] = true

    local duration = 0
    if self.dungeonState.encounterStartTime then
        duration = GetTime() - self.dungeonState.encounterStartTime
    end

    -- Fire boss killed event
    self:Fire("DUNGEON_BOSS_KILLED", {
        bossName = bossData.name,
        bossId = npcId,
        instance = bossData.instance or self.dungeonState.instanceName,
        instanceId = self.dungeonState.instanceId or 0,
        difficulty = self.dungeonState.difficulty or Enums.Difficulty.Normal,
        duration = duration,
        deaths = self.dungeonState.encounterDeaths or 0,
        raidSize = self:GetGroupSize(),
    })

    -- Reset encounter state
    self.dungeonState.encounterActive = false
    self.dungeonState.currentBoss = nil
    self.dungeonState.currentBossNpcId = nil

    -- Check if this was the final boss (dungeon clear)
    if bossData.isFinalBoss then
        local totalDuration = GetTime() - (self.dungeonState.startTime or GetTime())

        local instanceName = bossData.instance or self.dungeonState.instanceName
        local totalDeaths = self.dungeonState.totalDeaths
        self:Fire("DUNGEON_CLEARED", {
            instance = instanceName,
            instanceName = instanceName,  -- alias for config (Always Immortal, The Tower Unbroken, Midnight Rush)
            instanceId = self.dungeonState.instanceId or 0,
            difficulty = self.dungeonState.difficulty or Enums.Difficulty.Normal,
            duration = totalDuration,
            totalDeaths = totalDeaths,
            deaths = totalDeaths,  -- alias for config
            wipes = self.dungeonState.wipes or 0,
            raidSize = self:GetGroupSize(),
        })
    end
end

-------------------------------------------------------------------------------
-- Helper Functions
-------------------------------------------------------------------------------

---Extract NPC ID from GUID
---@param guid string
---@return number|nil
function eventBridge:GetNpcIdFromGUID(guid)
    if not guid then return nil end

    local guidType, _, _, _, _, npcId = strsplit("-", guid)
    if guidType == "Creature" or guidType == "Vehicle" then
        return tonumber(npcId)
    end
    return nil
end

---Get group size (TBC-compatible)
---@return number
function eventBridge:GetGroupSize()
    -- TBC uses GetNumRaidMembers() and GetNumPartyMembers()
    local raidSize = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidSize > 0 then
        return raidSize
    end
    local partySize = GetNumPartyMembers and GetNumPartyMembers() or 0
    if partySize > 0 then
        return partySize + 1 -- +1 for player
    end
    return 1 -- Solo
end

-------------------------------------------------------------------------------
-- Level and Gold Handling
-------------------------------------------------------------------------------

function eventBridge:HandleLevelUp(level)
    self:Fire("LEVEL_UP", {
        level = level,
    })
end

function eventBridge:HandleMoneyChanged()
    local currentGold = GetMoney()
    local currentMilestone = math.floor(currentGold / 10000) -- In gold units

    -- Fire milestone event if crossed a new threshold
    if currentMilestone > self.lastGoldMilestone then
        self:Fire("GOLD_MILESTONE", {
            amount = math.floor(currentGold / 10000), -- Gold amount (not copper)
        })
        self.lastGoldMilestone = currentMilestone
    end

    self.lastGold = currentGold
end

-------------------------------------------------------------------------------
-- Quest and Reputation Handling
-------------------------------------------------------------------------------

function eventBridge:HandleQuestTurnedIn(questId, xpReward, moneyReward)
    local questTitle = QuestUtils_GetQuestName(questId) or "Unknown Quest"
    local isDaily = Private.constants.DAILY_QUESTS[questId] or false

    self:Fire("QUEST_COMPLETED", {
        questId = questId,
        questName = questTitle,
        zone = GetZoneText() or "Unknown",
        isDaily = isDaily,
        xpGained = xpReward or 0,
        goldGained = moneyReward and math.floor(moneyReward / 10000) or 0,  -- Convert copper to gold
    })
end

-------------------------------------------------------------------------------
-- Equipment Handling
-------------------------------------------------------------------------------

function eventBridge:HandleEquipmentChanged(slot, hasItem)
    if hasItem then
        local itemLink = GetInventoryItemLink("player", slot)
        if itemLink then
            local itemName, _, quality, itemLevel = GetItemInfo(itemLink)

            -- Check for epic (quality 4)
            if quality and quality >= 4 then
                -- Extract itemId from link (TBC compatible)
                local itemId = tonumber(itemLink:match("item:(%d+)"))

                self:Fire("EPIC_GEAR_EQUIPPED", {
                    itemId = itemId,
                    itemName = itemName or "Unknown",
                    itemLevel = itemLevel or 0,
                    quality = quality,  -- Matches Enums.ItemQuality (4 = Epic)
                    slot = slot,  -- Maps directly to Enums.EquipSlot values
                })
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Profession Handling
-------------------------------------------------------------------------------

-- Spell IDs for crafting professions (TBC)
local CRAFTING_SPELL_IDS = {
    -- Alchemy
    [28672] = { profession = 171, name = "Alchemy" },
    [28675] = { profession = 171, name = "Alchemy" },
    -- Blacksmithing
    [29844] = { profession = 164, name = "Blacksmithing" },
    [29845] = { profession = 164, name = "Blacksmithing" },
    -- Enchanting (Disenchant is separate)
    [13262] = { profession = 333, name = "Enchanting", isDisenchant = true },
    -- Engineering
    [30350] = { profession = 202, name = "Engineering" },
    [30351] = { profession = 202, name = "Engineering" },
    -- Jewelcrafting
    [31252] = { profession = 755, name = "Jewelcrafting" },
    [31253] = { profession = 755, name = "Jewelcrafting" },
    -- Leatherworking
    [32549] = { profession = 165, name = "Leatherworking" },
    [32550] = { profession = 165, name = "Leatherworking" },
    -- Tailoring
    [26790] = { profession = 197, name = "Tailoring" },
    [26801] = { profession = 197, name = "Tailoring" },
    -- Cooking
    [33359] = { profession = 185, name = "Cooking" },
    -- First Aid
    [27028] = { profession = 129, name = "First Aid" },
}

-- Profession skill IDs
local PROFESSION_SKILL_IDS = {
    [171] = "Alchemy",
    [164] = "Blacksmithing",
    [333] = "Enchanting",
    [202] = "Engineering",
    [182] = "Herbalism",
    [755] = "Jewelcrafting",
    [165] = "Leatherworking",
    [186] = "Mining",
    [393] = "Skinning",
    [197] = "Tailoring",
    [185] = "Cooking",
    [129] = "First Aid",
    [356] = "Fishing",
}

-- Gathering spells
local GATHERING_SPELLS = {
    ["Mining"] = { gatherType = 1 }, -- Enums.GatherType.Mining
    ["Herb Gathering"] = { gatherType = 2 }, -- Enums.GatherType.Herbalism
    ["Skinning"] = { gatherType = 3 }, -- Enums.GatherType.Skinning
    ["Find Herbs"] = { gatherType = 2 },
    ["Find Minerals"] = { gatherType = 1 },
}

-- TBC Key item IDs with key type
local TBC_KEYS = {
    -- Heroic Keys (Enums.KeyType.Heroic = 1)
    [30622] = { name = "Flamewrought Key", keyType = 1 },      -- Hellfire Citadel Heroic
    [30623] = { name = "Reservoir Key", keyType = 1 },         -- Coilfang Reservoir Heroic
    [30633] = { name = "Auchenai Key", keyType = 1 },          -- Auchindoun Heroic
    [30634] = { name = "Warpforged Key", keyType = 1 },        -- Tempest Keep Heroic
    [30635] = { name = "Key of Time", keyType = 1 },           -- Caverns of Time Heroic
    -- Attunement Keys (Enums.KeyType.Attunement = 2)
    [30637] = { name = "Shattered Halls Key", keyType = 2 },   -- Shattered Halls
    [31084] = { name = "Key to the Arcatraz", keyType = 2 },   -- Arcatraz
    [24490] = { name = "The Master's Key", keyType = 2 },      -- Karazhan
    [32649] = { name = "Medallion of Karabor", keyType = 2 },  -- Black Temple
    [31704] = { name = "The Tempest Key", keyType = 2 },       -- Tempest Keep
    [25463] = { name = "Shadowy Key", keyType = 2 },           -- Shadow Labyrinth
    [27991] = { name = "Shadow Labyrinth Key", keyType = 2 },  -- Shadow Labyrinth
}

-- TBC Fish item IDs
local TBC_FISH = {
    [27422] = "Barbed Gill Trout",
    [27425] = "Spotted Feltail",
    [27429] = "Zangarian Sporefish",
    [27435] = "Figluster's Mudfish",
    [27437] = "Icefin Bluefish",
    [27438] = "Golden Darter",
    [27439] = "Furious Crawdad",
    [27515] = "Huge Spotted Feltail",
    [27516] = "Enormous Barbed Gill Trout",
    [34864] = "Baby Crocolisk",
    [27388] = "Mr. Pinchy",
    [35286] = "Bloated Barbed Gill Trout",
    [35287] = "Bloated Spotted Feltail",
}

function eventBridge:HandleSpellcastSucceeded(unit, castGUID, spellId)
    if unit ~= "player" then return end

    local spellName = GetSpellInfo(spellId)
    if not spellName then return end

    -- Fishing detection - set flag for loot handling
    if spellName == "Fishing" then
        self.fishingState.isFishing = true
        self.fishingState.castTime = GetTime()
        return
    end

    -- AV capture interaction: correlate "Opening" with later faction message
    if spellName == "Opening" and self.pvpState.inBattleground and self.pvpState.bgName == "Alterac Valley" then
        local objectiveName = nil
        if type(UnitName) == "function" then
            objectiveName = UnitName("target")
        end
        self.pvpState.pendingObjectiveInteraction = {
            time = GetTime(),
            objectiveName = objectiveName,
        }
        return
    end

    -- Disenchanting detection
    if spellId == 13262 then -- Disenchant spell ID
        self.disenchantState.isDisenchanting = true
        return
    end

    -- Ring enchant detection (TBC Enchanter-only ring enchants)
    local ringEnchants = {
        ["Enchant Ring - Spellpower"] = true,
        ["Enchant Ring - Healing Power"] = true,
        ["Enchant Ring - Stats"] = true,
        ["Enchant Ring - Striking"] = true,
    }
    if ringEnchants[spellName] then
        self:Fire("RING_ENCHANTED", {
            enchantName = spellName,
            spellId = spellId,
        })
        return
    end

    -- Check for crafting spells
    local craftInfo = CRAFTING_SPELL_IDS[spellId]
    if craftInfo and not craftInfo.isDisenchant then
        self.craftingState.lastCraftSpellId = spellId
        self.craftingState.lastCraftTime = GetTime()
        -- Fire will happen when the item is created (via CHAT_MSG_LOOT or similar)
        return
    end

    -- Check for gathering
    local gatherInfo = GATHERING_SPELLS[spellName]
    if gatherInfo then
        -- Gathering success - will fire when loot is received
        return
    end
end

-------------------------------------------------------------------------------
-- Skill Tracking and SKILL_UP Implementation
-------------------------------------------------------------------------------

function eventBridge:InitializeSkillTracking()
    self.skillLevels = {}
    -- Populate current skill levels
    local numSkills = GetNumSkillLines()
    for i = 1, numSkills do
        local skillName, isHeader, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
        if not isHeader and skillName then
            self.skillLevels[skillName] = {
                rank = skillRank,
                maxRank = skillMaxRank,
            }
        end
    end
end

function eventBridge:HandleSkillUpdate()
    -- Compare current skills with tracked skills
    local numSkills = GetNumSkillLines()
    for i = 1, numSkills do
        local skillName, isHeader, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
        if not isHeader and skillName then
            local tracked = self.skillLevels[skillName]
            if tracked then
                if skillRank > tracked.rank then
                    -- Skill up detected!
                    local professionId = self:GetProfessionIdByName(skillName)
                    self:Fire("SKILL_UP", {
                        profession = professionId,
                        oldLevel = tracked.rank,
                        newLevel = skillRank,
                    })
                    tracked.rank = skillRank
                end
                tracked.maxRank = skillMaxRank
            else
                -- New skill learned
                self.skillLevels[skillName] = {
                    rank = skillRank,
                    maxRank = skillMaxRank,
                }
            end
        end
    end
end

function eventBridge:HandleSkillMessage(message)
    -- Skill messages like "Your skill in Mining has increased to 310."
    if not message then return end

    local skillName, newLevel = message:match("Your skill in (.+) has increased to (%d+)")
    if skillName and newLevel then
        newLevel = tonumber(newLevel)
        local professionId = self:GetProfessionIdByName(skillName)
        local oldLevel = self.skillLevels[skillName] and self.skillLevels[skillName].rank or (newLevel - 1)

        self:Fire("SKILL_UP", {
            profession = professionId,
            oldLevel = oldLevel,
            newLevel = newLevel,
        })

        -- Update tracked value
        if self.skillLevels[skillName] then
            self.skillLevels[skillName].rank = newLevel
        end
    end
end

function eventBridge:GetProfessionIdByName(name)
    local nameToId = {
        ["Alchemy"] = 171,
        ["Blacksmithing"] = 164,
        ["Enchanting"] = 333,
        ["Engineering"] = 202,
        ["Herbalism"] = 182,
        ["Jewelcrafting"] = 755,
        ["Leatherworking"] = 165,
        ["Mining"] = 186,
        ["Skinning"] = 393,
        ["Tailoring"] = 197,
        ["Cooking"] = 185,
        ["First Aid"] = 129,
        ["Fishing"] = 356,
        ["Riding"] = 762,
    }
    return nameToId[name]
end

-- Reverse mapping for getting skill level
local PROFESSION_ID_TO_NAME = {
    [171] = "Alchemy",
    [164] = "Blacksmithing",
    [333] = "Enchanting",
    [202] = "Engineering",
    [182] = "Herbalism",
    [755] = "Jewelcrafting",
    [165] = "Leatherworking",
    [186] = "Mining",
    [393] = "Skinning",
    [197] = "Tailoring",
    [185] = "Cooking",
    [129] = "First Aid",
    [356] = "Fishing",
    [762] = "Riding",
}

function eventBridge:GetProfessionSkillLevel(professionId)
    local profName = PROFESSION_ID_TO_NAME[professionId]
    if not profName then return 0 end

    if self.skillLevels[profName] then
        return self.skillLevels[profName].rank or 0
    end
    return 0
end

-------------------------------------------------------------------------------
-- Loot Handling (ITEM_CRAFTED, FISH_CAUGHT, BADGE_EARNED, RESOURCE_GATHERED)
-------------------------------------------------------------------------------

-- For primal/mote weekly achievements: 1 primal = 10 motes (mote-equivalent counting).
local PRIMAL_MOTE_EQUIVALENT = {
    ["Primal Mana"] = 10,
    ["Mote of Mana"] = 1,
    ["Primal Fire"] = 10,
    ["Mote of Fire"] = 1,
    ["Primal Shadow"] = 10,
    ["Mote of Shadow"] = 1,
    ["Primal Air"] = 10,
    ["Mote of Air"] = 1,
    ["Primal Water"] = 10,
    ["Mote of Water"] = 1,
    ["Primal Earth"] = 10,
    ["Mote of Earth"] = 1,
    ["Primal Life"] = 10,
    ["Mote of Life"] = 1,
}

function eventBridge:HandleLootMessage(message)
    if not message then return end

    -- Check for Badge of Justice
    if message:find("Badge of Justice") then
        -- Track total badges (stored in state)
        self.badgeCount = (self.badgeCount or 0) + 1

        self:Fire("BADGE_EARNED", {
            badgeType = "Badge of Justice",
            count = 1,
            totalCount = self.badgeCount,
            source = self.dungeonState.encounterActive and Enums.BadgeSource.Boss or Enums.BadgeSource.Quest,
        })
    end

    -- Parse loot message for item
    -- Pattern: "You receive loot: |cff...|Hitem:ITEMID:...|h[Item Name]|h|r"
    local itemLink = message:match("|c%x+|Hitem:.-|h%[.-%]|h|r")
    if itemLink then
        local itemId = tonumber(itemLink:match("item:(%d+)"))
        local itemName = itemLink:match("%[(.-)%]")
        local quantity = tonumber(message:match("|h|r%s*[xX](%d+)")) or 1

        if itemId then
            -- Generic item looted (currently used for specific achievement triggers)
            if itemName then
                self:Fire("ITEM_LOOTED", {
                    itemId = itemId,
                    itemName = itemName,
                    quantity = quantity,
                    zone = GetZoneText() or "Unknown",
                })
            end

            -- Check if it's a fish and we were fishing
            if TBC_FISH[itemId] or (self.fishingState.isFishing and GetTime() - (self.fishingState.castTime or 0) < 30) then
                self:Fire("FISH_CAUGHT", {
                    fishId = itemId,
                    fishName = itemName,
                    zone = GetZoneText() or "Unknown",
                })
                self.fishingState.isFishing = false
            end

            -- Check if it's a key
            local keyData = TBC_KEYS[itemId]
            if keyData then
                self:Fire("KEY_OBTAINED", {
                    keyId = itemId,
                    keyName = keyData.name,
                    keyType = keyData.keyType,  -- Enums.KeyType.Heroic or .Attunement
                })
            end

            -- Check for primal loot (Mana Matters, Playing with Fire, Primal Procurer weekly achievements)
            if itemName and (itemName:find("Primal") or itemName:find("Mote of")) then
                local eq = PRIMAL_MOTE_EQUIVALENT[itemName]
                local count = quantity
                if eq then
                    count = quantity * eq
                end

                self:Fire("PRIMAL_LOOTED", {
                    itemId = itemId,
                    itemName = itemName,
                    zone = GetZoneText() or "Unknown",
                    count = count,      -- mote-equivalent units when known, else quantity
                    quantity = quantity -- raw stack quantity from loot message (best-effort)
                })
            end

            -- Check for resource gathering (ore, herbs, leather)
            local gatherType = self:DetectGatherType(itemId, itemName)
            if gatherType then
                self:Fire("RESOURCE_GATHERED", {
                    itemId = itemId,
                    itemName = itemName,
                    gatherType = gatherType,
                })
            end

            -- Check for crafting (if we just crafted something)
            if self.craftingState.lastCraftTime and GetTime() - self.craftingState.lastCraftTime < 5 then
                local profession = self:DetectCraftingProfession(itemId, itemName)
                if profession then
                    -- Get current skill level for this profession
                    local skillLevel = self:GetProfessionSkillLevel(profession)
                    -- Get item quality
                    local _, _, quality = GetItemInfo(itemId)
                    self:Fire("ITEM_CRAFTED", {
                        itemId = itemId,
                        itemName = itemName,
                        profession = profession,
                        skillLevel = skillLevel or 0,
                        itemQuality = quality or 1,  -- Default to common if unavailable
                        count = 1,  -- TODO: multi-craft detection would need CHAT_MSG_LOOT quantity or similar
                    })
                end
                self.craftingState.lastCraftTime = nil
            end

            -- Check for disenchanting result
            if self.disenchantState.isDisenchanting then
                local isEnchantingMat = self:IsEnchantingMaterial(itemId)
                if isEnchantingMat then
                    local _, _, _, resultItemLevel = GetItemInfo(itemId)
                    self:Fire("ITEM_DISENCHANTED", {
                        resultItemId = itemId,
                        resultItemName = itemName,
                        resultItemLevel = resultItemLevel or 0,
                    })
                    self.disenchantState.isDisenchanting = false
                end
            end
        end
    end

    -- Check for "You create:" pattern (crafting)
    local createdItem = message:match("You create: (|c%x+|Hitem:.-|h%[.-%]|h|r)")
    if createdItem then
        local itemId = tonumber(createdItem:match("item:(%d+)"))
        local itemName = createdItem:match("%[(.-)%]")
        if itemId then
            local profession = self:DetectCraftingProfession(itemId, itemName)
            local skillLevel = profession and self:GetProfessionSkillLevel(profession) or 0
            local _, _, quality = GetItemInfo(itemId)
            self:Fire("ITEM_CRAFTED", {
                itemId = itemId,
                itemName = itemName,
                profession = profession,
                skillLevel = skillLevel,
                itemQuality = quality or 1,  -- Default to common if unavailable
                count = 1,  -- Single craft
            })
        end
    end

    -- Check for loot roll wins
    self:CheckLootRollWin(message)
end

function eventBridge:HandleLootOpened()
    -- Track treasure chests via loot window opening
    if type(UnitName) ~= "function" then return end
    local targetName = UnitName("target")
    if not targetName or targetName == "" then return end

    local lowerName = targetName:lower()
    local isChest = lowerName:find("chest") or lowerName:find("treasure") or lowerName:find("cache") or lowerName:find("coffer")
    if not isChest then return end

    self:Fire("TREASURE_CHEST_LOOTED", {
        chestName = targetName,
        zone = GetZoneText() or "Unknown",
    })
end

function eventBridge:DetectGatherType(itemId, itemName)
    if not itemName then return nil end

    -- TBC Mining ores only
    local orePatterns = { "Fel Iron", "Adamantite", "Khorium", "Eternium" }
    for _, pattern in ipairs(orePatterns) do
        if itemName:find(pattern) then
            return 1 -- Enums.GatherType.Mining
        end
    end

    -- TBC Herbalism only
    local herbPatterns = { "Felweed", "Dreaming Glory", "Terocone", "Ragveil", "Flame Cap", "Netherbloom", "Nightmare Vine", "Mana Thistle", "Ancient Lichen", "Fel Lotus" }
    for _, pattern in ipairs(herbPatterns) do
        if itemName:find(pattern) then
            return 2 -- Enums.GatherType.Herbalism
        end
    end

    -- TBC Skinning only
    local skinPatterns = { "Knothide Leather", "Fel Hide", "Nether Dragonscales", "Thick Clefthoof Leather", "Cobra Scales", "Wind Scales" }
    for _, pattern in ipairs(skinPatterns) do
        if itemName:find(pattern) then
            return 3 -- Enums.GatherType.Skinning
        end
    end

    return nil
end

function eventBridge:DetectCraftingProfession(itemId, itemName)
    if not itemName then return nil end

    -- Try to detect profession from item name patterns
    local patterns = {
        { pattern = "Potion", profession = 171 }, -- Alchemy
        { pattern = "Elixir", profession = 171 },
        { pattern = "Flask", profession = 171 },
        { pattern = "Transmute", profession = 171 },
        { pattern = "Oil", profession = 171 },

        { pattern = "Plate", profession = 164 }, -- Blacksmithing
        { pattern = "Sword", profession = 164 },
        { pattern = "Axe", profession = 164 },
        { pattern = "Mace", profession = 164 },
        { pattern = "Hammer", profession = 164 },

        { pattern = "Enchant", profession = 333 }, -- Enchanting

        { pattern = "Scope", profession = 202 }, -- Engineering
        { pattern = "Bomb", profession = 202 },
        { pattern = "Goggles", profession = 202 },

        { pattern = "Cut", profession = 755 }, -- Jewelcrafting (gems)
        { pattern = "Gem", profession = 755 },
        { pattern = "Ring", profession = 755 },
        { pattern = "Necklace", profession = 755 },

        { pattern = "Armor Kit", profession = 165 }, -- Leatherworking
        { pattern = "Leather", profession = 165 },
        { pattern = "Mail", profession = 165 },

        { pattern = "Bag", profession = 197 }, -- Tailoring
        { pattern = "Cloth", profession = 197 },
        { pattern = "Robe", profession = 197 },
        { pattern = "Mooncloth", profession = 197 },
        { pattern = "Spellcloth", profession = 197 },
        { pattern = "Shadowcloth", profession = 197 },

        { pattern = "Cooked", profession = 185 }, -- Cooking
        { pattern = "Roast", profession = 185 },
        { pattern = "Stew", profession = 185 },
        { pattern = "Soup", profession = 185 },

        { pattern = "Bandage", profession = 129 }, -- First Aid
    }

    for _, p in ipairs(patterns) do
        if itemName:find(p.pattern) then
            return p.profession
        end
    end

    return nil
end

function eventBridge:IsEnchantingMaterial(itemId)
    -- Common TBC enchanting materials
    local enchantMats = {
        [22445] = true, -- Arcane Dust
        [22446] = true, -- Greater Planar Essence
        [22447] = true, -- Lesser Planar Essence
        [22448] = true, -- Small Prismatic Shard
        [22449] = true, -- Large Prismatic Shard
        [22450] = true, -- Void Crystal
        [34057] = true, -- Abyss Crystal
    }
    return enchantMats[itemId]
end

-------------------------------------------------------------------------------
-- Reputation Tracking and REPUTATION_GAINED Implementation
-------------------------------------------------------------------------------

function eventBridge:InitializeReputationTracking()
    self.reputationStandings = {}
    -- Store current reputation values
    for i = 1, GetNumFactions() do
        local name, _, standingId, barMin, barMax, barValue = GetFactionInfo(i)
        if name then
            self.reputationStandings[name] = {
                standing = standingId,
                value = barValue,
                min = barMin,
                max = barMax,
            }
        end
    end
end

function eventBridge:HandleReputationChanged()
    for i = 1, GetNumFactions() do
        local name, _, standingId, barMin, barMax, barValue, _, _, _, _, _, _, _, factionId = GetFactionInfo(i)
        if name then
            local tracked = self.reputationStandings[name]
            if tracked then
                local repGained = barValue - tracked.value

                -- Check if standing changed (rank up) or rep increased
                if standingId > tracked.standing or barValue > tracked.value then
                    self:Fire("REPUTATION_GAINED", {
                        faction = name,
                        factionId = factionId or 0,
                        repGained = repGained > 0 and repGained or 0,
                        standing = standingId,  -- Maps to Enums.Standing values
                        currentRep = barValue,
                    })
                end
                tracked.standing = standingId
                tracked.value = barValue
                tracked.min = barMin
                tracked.max = barMax
            else
                -- New faction encountered
                self.reputationStandings[name] = {
                    standing = standingId,
                    value = barValue,
                    min = barMin,
                    max = barMax,
                }
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Key Tracking and KEY_OBTAINED Implementation
-------------------------------------------------------------------------------

function eventBridge:InitializeKeyTracking()
    self.knownKeys = {}
    -- Scan bags for existing keys
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            local itemId = itemInfo and itemInfo.itemID
            if itemId and TBC_KEYS[itemId] then
                self.knownKeys[itemId] = true
            end
        end
    end
    -- Also check keyring if it exists
    if KEYRING_CONTAINER then
        local numSlots = C_Container.GetContainerNumSlots(KEYRING_CONTAINER)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(KEYRING_CONTAINER, slot)
            local itemId = itemInfo and itemInfo.itemID
            if itemId and TBC_KEYS[itemId] then
                self.knownKeys[itemId] = true
            end
        end
    end
end

function eventBridge:HandleBagUpdate(bagId)
    -- Check for new keys
    local numSlots = C_Container.GetContainerNumSlots(bagId) or 0
    for slot = 1, numSlots do
        local itemInfo = C_Container.GetContainerItemInfo(bagId, slot)
        local itemId = itemInfo and itemInfo.itemID
        local keyData = itemId and TBC_KEYS[itemId]
        if keyData and not self.knownKeys[itemId] then
            self.knownKeys[itemId] = true
            self:Fire("KEY_OBTAINED", {
                keyId = itemId,
                keyName = keyData.name,
                keyType = keyData.keyType,  -- Enums.KeyType.Heroic or .Attunement
            })
        end
    end
end

-------------------------------------------------------------------------------
-- Battleground Handling and BATTLEGROUND_MATCH_END Implementation
-------------------------------------------------------------------------------

function eventBridge:HandleBattlefieldUpdate()
    if not self.pvpState.inBattleground then return end

    -- Check for winner
    local winner = GetBattlefieldWinner()
    if winner then
        local playerFaction = UnitFactionGroup("player") == "Alliance" and 1 or 0
        local isVictory = (winner == playerFaction)

        local duration
        if type(GetBattlefieldInstanceRunTime) == "function" then
            local ms = GetBattlefieldInstanceRunTime()
            if ms and ms > 0 then
                duration = ms / 1000
            end
        end
        if not duration then
            duration = GetTime() - (self.pvpState.startTime or GetTime())
        end

        -- Get final stats
        local numScores = GetNumBattlefieldScores()
        local kills, deaths, honorGained = 0, 0, 0
        for i = 1, numScores do
            local name, killingBlows, honorKills, deaths_i, honorGained_i = GetBattlefieldScore(i)
            if name == UnitName("player") then
                kills = honorKills
                deaths = deaths_i
                honorGained = honorGained_i
                self.pvpState.killingBlows = killingBlows
                break
            end
        end

        self:Fire("BATTLEGROUND_MATCH_END", {
            battleground = self.pvpState.bgName,
            result = isVictory and 1 or 2, -- Enums.BattlegroundResult.Victory/Defeat
            duration = duration,
            kills = kills,
            deaths = deaths,
            honorGained = honorGained,
            killingBlows = self.pvpState.killingBlows,
        })

        -- Reset state
        self.pvpState.inBattleground = false
        self.pvpState.bgName = nil
        self.pvpState.kills = 0
        self.pvpState.killingBlows = 0
        self.pvpState.startTime = nil
        self.pvpState.flagCarriers = {}
    end
end

function eventBridge:HandleHonorGain(message)
    -- CHAT_MSG_COMBAT_HONOR_GAIN fires with message like "PlayerName dies, honorable kill Rank: Scout (Estimated Honor Points: 27)"
    if not message then return end

    -- Extract honor amount from message
    local honorAmount = message:match("Honor Points: (%d+)")
    if honorAmount then
        honorAmount = tonumber(honorAmount) or 0
    else
        honorAmount = 0
    end

    -- Track kills for PvP achievements
    if self.pvpState.inBattleground or self.pvpState.inArena then
        self.pvpState.kills = (self.pvpState.kills or 0) + 1
    end

    -- Fire KILL event for PvP kill tracking
    self:Fire("KILL", {
        honorGained = honorAmount,
        inBattleground = self.pvpState.inBattleground or false,
        inArena = self.pvpState.inArena or false,
    })
end

function eventBridge:HandleLootSlotCleared(slot)
    -- This event fires when an item is taken from loot window
    -- Useful for tracking items that were actually looted
    -- The actual item tracking is done via CHAT_MSG_LOOT which has more info
    -- This is primarily used to know when loot window interaction happened
end

function eventBridge:HandleBattlegroundPointsUpdate()
    -- This fires when BG score updates (capturing objectives, killing enemies, etc.)
    -- The main score tracking is in HandleBattlefieldUpdate which checks for winner
    -- This event is useful for real-time progress tracking
    if not self.pvpState.inBattleground then return end

    -- Update battlefield stats in real-time
    local numScores = GetNumBattlefieldScores()
    for i = 1, numScores do
        local name, killingBlows, honorKills = GetBattlefieldScore(i)
        if name == UnitName("player") then
            self.pvpState.kills = honorKills or 0
            self.pvpState.killingBlows = killingBlows or 0
            break
        end
    end
end

function eventBridge:HandleBGSystemMessage(message)
    if not message or not self.pvpState.inBattleground then return end

    -- Track flag carriers for targetType = "flag_carrier" (Stormtrooper achievement)
    if self.pvpState.flagCarriers then
        local pickupName = message:match("^(.+) picks up the flag") or message:match("picked up by (.+)%.?$") or message:match("picked up by (.+)")
        if pickupName and pickupName ~= "" then
            local name = pickupName:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" then
                self.pvpState.flagCarriers[name] = true
            end
        end
        if message:find("flag was returned") or message:find("captured the flag") then
            self.pvpState.flagCarriers = {}
        end
    end

    local playerName = UnitName("player")
    local lowerMessage = message:lower()
    local objectiveType, objectiveName = self:DetectObjectiveType(message)

    -- Alterac Valley: faction messages are generic; correlate with recent "Opening" cast
    if self.pvpState.bgName == "Alterac Valley" then
        if lowerMessage:find("has taken the") or lowerMessage:find("has captured the") then
            local pending = self.pvpState.pendingObjectiveInteraction
            if pending and pending.time then
                local elapsed = GetTime() - pending.time
                local withinWindow = elapsed <= 2.5
                if withinWindow then
                    local match = true
                    if pending.objectiveName and pending.objectiveName ~= "" and objectiveName and objectiveName ~= "Unknown" then
                        match = pending.objectiveName:lower():find(objectiveName:lower(), 1, true) ~= nil
                    end
                    if match and objectiveType == Enums.ObjectiveType.Tower then
                        self:Fire("PVP_OBJECTIVE_CAPTURED", {
                            objectiveType = objectiveType,
                            location = self.pvpState.bgName or GetZoneText() or "Unknown",
                            objectiveName = objectiveName or "Unknown",
                        })
                    end
                end
            end
            self.pvpState.pendingObjectiveInteraction = nil
        end
    end

    -- Arathi Basin: "claims the" assault then "has taken the" capture
    if self.pvpState.bgName == "Arathi Basin" then
        local claimant = message:match("^(.+) claims the") or message:match("^(.+) has assaulted the")
        if claimant and objectiveName and objectiveName ~= "Unknown" then
            local name = claimant:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" then
                self.pvpState.pendingAssaults[objectiveName] = {
                    player = name,
                    time = GetTime(),
                }
            end
        end

        if lowerMessage:find("has taken the") or lowerMessage:find("has captured the") then
            local pending = self.pvpState.pendingAssaults[objectiveName]
            if pending then
                local maxWindow = 70 -- 60s base capture + buffer
                local elapsed = GetTime() - (pending.time or 0)
                if elapsed <= maxWindow then
                    local captureFaction = message:match("^The ([%a]+) has taken the") or message:match("^The ([%a]+) has captured the")
                    local playerFaction = (type(UnitFactionGroup) == "function") and UnitFactionGroup("player") or nil
                    if (not captureFaction or not playerFaction or captureFaction == playerFaction) and pending.player == playerName then
                        self:Fire("PVP_OBJECTIVE_CAPTURED", {
                            objectiveType = objectiveType,  -- Enums.ObjectiveType.Flag/Base/Tower
                            location = self.pvpState.bgName or GetZoneText() or "Unknown",
                            objectiveName = objectiveName or "Unknown",
                        })
                    end
                end
                self.pvpState.pendingAssaults[objectiveName] = nil
                return
            end
        end

        -- For AB assaults, we wait for capture confirmation
        if claimant and claimant ~= "" then
            return
        end
    end

    -- Track objective captures (immediate for other BGs / messages that include player)
    local capturePatterns = {
        "has taken the",
        "has captured the",
        "has assaulted the",
        "flag was picked up",
        "captured the flag",
        "flag was returned",
        "returns the flag",
    }

    for _, pattern in ipairs(capturePatterns) do
        if message:find(pattern) and message:find(playerName) then
            local isFlagReturn = (pattern == "flag was returned" or pattern == "returns the flag")
            self:Fire("PVP_OBJECTIVE_CAPTURED", {
                objectiveType = objectiveType,
                location = self.pvpState.bgName or GetZoneText() or "Unknown",
                objectiveName = objectiveName or "Unknown",
                isFlagReturn = isFlagReturn,
            })
            break
        end
    end
end

function eventBridge:HandleSystemMessage(message)
    if not message then return end

    -- Honor token earned messages (Halaa tokens, Marks of Honor)
    local tokenPatterns = {
        ["Halaa Battle Token"] = 26045,
        ["Halaa Research Token"] = 26044,
        ["Mark of Honor"] = 20560,
    }

    for tokenName, tokenId in pairs(tokenPatterns) do
        if message:find(tokenName) then
            self:Fire("PVP_TOKEN_EARNED", {
                tokenType = tokenName,
                tokenId = tokenId,
                count = 1,
                totalCount = GetItemCount(tokenId),
            })
            break
        end
    end
end

function eventBridge:HandlePlayerEmote(message)
    if not message then return end

    -- CHAT_MSG_TEXT_EMOTE format: "You roar." or similar (player's own emotes)
    local lowerMessage = message:lower()

    -- Only process if the message starts with "you " (your own emotes)
    if not lowerMessage:find("^you ") then return end

    local emoteType = nil

    -- Detect emote type from message
    if lowerMessage:find("roar") then
        emoteType = "roar"
    elseif lowerMessage:find("dance") then
        emoteType = "dance"
    elseif lowerMessage:find("cheer") then
        emoteType = "cheer"
    end

    if not emoteType then return end

    -- Get player's current target
    local targetName = UnitName("target")
    local targetExists = UnitExists("target")

    -- Only fire if we have a valid target
    if targetExists and targetName then
        self:Fire("EMOTE_SENT", {
            emoteType = emoteType,
            targetName = targetName,
        })
    end
end

function eventBridge:DetectObjectiveType(message)
    local objectiveType = 2  -- Default to Base
    local objectiveName = "Unknown"
    local lowerMessage = message:lower()

    local avObjectives = {
        ["iceblood tower"] = "Iceblood Tower",
        ["tower point"] = "Tower Point",
        ["east frostwolf tower"] = "East Frostwolf Tower",
        ["west frostwolf tower"] = "West Frostwolf Tower",
        ["stonehearth bunker"] = "Stonehearth Bunker",
        ["icewing bunker"] = "Icewing Bunker",
    }

    for key, display in pairs(avObjectives) do
        if lowerMessage:find(key) then
            objectiveType = 3
            objectiveName = display
            return objectiveType, objectiveName
        end
    end

    -- AB bases
    if lowerMessage:find("farm") then
        objectiveType = 2  -- Base
        objectiveName = "Farm"
    elseif lowerMessage:find("stables") then
        objectiveType = 2
        objectiveName = "Stables"
    elseif lowerMessage:find("blacksmith") then
        objectiveType = 2
        objectiveName = "Blacksmith"
    elseif lowerMessage:find("lumber mill") then
        objectiveType = 2
        objectiveName = "Lumber Mill"
    elseif lowerMessage:find("gold mine") then
        objectiveType = 2
        objectiveName = "Gold Mine"
    -- AV objectives
    elseif lowerMessage:find("tower") then
        objectiveType = 3  -- Tower
        objectiveName = "Tower"
    elseif lowerMessage:find("bunker") then
        objectiveType = 3
        objectiveName = "Bunker"
    elseif lowerMessage:find("graveyard") then
        objectiveType = 3
        objectiveName = "Graveyard"
    -- WSG/EOTS flag
    elseif lowerMessage:find("flag") then
        objectiveType = 1  -- Flag
        objectiveName = "Flag"
    end

    return objectiveType, objectiveName
end

-------------------------------------------------------------------------------
-- Arena Handling and ARENA_MATCH_END / ARENA_RATING_MILESTONE Implementation
-------------------------------------------------------------------------------

function eventBridge:InitializeArenaTracking()
    self.arenaRatings = {}
    self.arenaState = {
        inArena = false,
        bracket = nil,
        startTime = nil,
    }

    -- Get current arena ratings
    for bracket = 1, 3 do
        local teamName, teamSize, teamRating = GetArenaTeam(bracket)
        if teamName then
            local bracketSize = bracket == 1 and 2 or (bracket == 2 and 3 or 5)
            self.arenaRatings[bracketSize] = {
                name = teamName,
                rating = teamRating or 0,
            }
        end
    end
end

function eventBridge:HandleArenaTeamUpdate()
    -- Check for rating changes
    for bracket = 1, 3 do
        local teamName, teamSize, teamRating = GetArenaTeam(bracket)
        if teamName and teamRating then
            local bracketSize = bracket == 1 and 2 or (bracket == 2 and 3 or 5)
            local tracked = self.arenaRatings[bracketSize]

            if tracked then
                -- Check for milestone crossings
                local oldRating = tracked.rating
                local newRating = teamRating

                -- Milestones: 1500, 1700, 1850, 2000, 2200
                local milestones = { 1500, 1700, 1850, 2000, 2200 }
                for _, milestone in ipairs(milestones) do
                    if oldRating < milestone and newRating >= milestone then
                        self:Fire("ARENA_RATING_MILESTONE", {
                            bracket = bracketSize,
                            rating = newRating,
                            ratingGain = newRating - oldRating,
                            milestone = milestone,
                            teamName = teamName,
                        })
                    end
                end

                tracked.rating = newRating
            else
                -- New team
                self.arenaRatings[bracketSize] = {
                    name = teamName,
                    rating = teamRating,
                }
            end
        end
    end

    -- Check if arena match ended (rating changed after being in arena)
    if self.arenaState.inArena then
        self:CheckArenaMatchEnd()
    end
end

---Returns true if the arena team for the given bracket is all guild members (best-effort TBC)
---@param bracket number 2, 3, or 5 (Enums.ArenaBracket)
---@return boolean
function eventBridge:IsArenaTeamGuildTeam(bracket)
    if not IsInGuild() then return false end
    local teamIndex = (bracket == 2 and 1) or (bracket == 3 and 2) or (bracket == 5 and 3)
    if not teamIndex then return false end
    local numMembers = GetNumArenaTeamMembers and GetNumArenaTeamMembers(teamIndex)
    if not numMembers or numMembers == 0 then return false end
    local guildNames = {}
    for i = 1, GetNumGuildMembers and GetNumGuildMembers() or 0 do
        local name = GetGuildRosterInfo and select(1, GetGuildRosterInfo(i))
        if name then
            guildNames[name:gsub("%-.*", "")] = true
            guildNames[name] = true
        end
    end
    for i = 1, numMembers do
        local name = GetArenaTeamRosterInfo and select(1, GetArenaTeamRosterInfo(teamIndex, i))
        if name and not guildNames[name] and not guildNames[name:gsub("%-.*", "")] then
            return false
        end
    end
    return true
end

function eventBridge:CheckArenaMatchEnd()
    if not self.arenaState.inArena then return end

    -- Try to determine result from rating change
    local bracket = self.arenaState.bracket
    if bracket and self.arenaRatings[bracket] then
        local duration = GetTime() - (self.arenaState.startTime or GetTime())
        local currentRating = self.arenaRatings[bracket].rating or 0
        local ok, guildTeam = pcall(function() return self:IsArenaTeamGuildTeam(bracket) end)
        if not ok then guildTeam = false end

        self:Fire("ARENA_MATCH_END", {
            bracket = bracket,  -- Enums.ArenaBracket (2, 3, or 5)
            result = 1, -- TODO: determine win/loss from rating delta or combat log
            ratingChange = 0, -- TODO: track rating before/after match for delta
            newRating = currentRating,
            duration = duration,
            guildTeam = guildTeam,
        })
    end

    self.arenaState.inArena = false
    self.arenaState.bracket = nil
    self.arenaState.startTime = nil
end

-------------------------------------------------------------------------------
-- Loot Roll Handling and LOOT_ROLL_WON Implementation
-------------------------------------------------------------------------------

function eventBridge:HandleStartLootRoll(rollId, rollTime)
    self.activeLootRolls[rollId] = {
        startTime = GetTime(),
        rollTime = rollTime,
    }
end

function eventBridge:HandleLootRollsComplete(rollId)
    -- Check if player won this roll
    local rollInfo = self.activeLootRolls[rollId]
    if rollInfo then
        -- The actual winner info might need to be tracked via chat messages
        self.activeLootRolls[rollId] = nil
    end
end

-- Also track roll wins via system messages
function eventBridge:CheckLootRollWin(message)
    if not message then return end

    local playerName = UnitName("player")

    -- Pattern: "PlayerName won: [Item Name]"
    -- Pattern: "PlayerName has selected Need/Greed for: [Item Name]"
    if message:find(playerName) and message:find("won:") then
        local itemLink = message:match("|c%x+|Hitem:.-|h%[.-%]|h|r")
        if itemLink then
            local itemId = tonumber(itemLink:match("item:(%d+)"))
            local itemName = itemLink:match("%[(.-)%]")
            local _, _, quality = GetItemInfo(itemLink)

            local rollType = 1 -- Default to Need (Enums.RollType.Need)
            if message:find("Greed") then
                rollType = 2  -- Enums.RollType.Greed
            elseif message:find("Disenchant") then
                rollType = 3  -- Enums.RollType.Disenchant
            end

            -- Try to extract roll value from message
            local rollValue = tonumber(message:match("rolled (%d+)")) or 0

            self:Fire("LOOT_ROLL_WON", {
                itemId = itemId,
                itemName = itemName,
                itemQuality = quality,  -- Matches Enums.ItemQuality
                rollType = rollType,    -- Matches Enums.RollType
                rollValue = rollValue,
            })
        end
    end
end
