-- Reckoning Achievement Frame
-- A custom achievement UI for private servers without the Blizzard Achievement API

-- Create addon namespace
Reckoning = Reckoning or {}
Reckoning.Achievements = Reckoning.Achievements or {}

local Reckoning_Achievements = Reckoning.Achievements

-- Get Private namespace (set by Init.lua)
local Private = Reckoning.Private

-- Forward declarations so guild event button OnClick (created earlier in file) can call these
local EnsureBugReportDropDown
local EnsureBugReportDialog

-------------------------------------------------------------------------------
-- Frame Registration (Deferred to avoid taint)
-------------------------------------------------------------------------------

-- Register frame with Blizzard UI system on first use
local function RegisterFrameWithBlizzardUI()
    if not UIPanelWindows["ReckoningAchievementFrame"] then
        UIPanelWindows["ReckoningAchievementFrame"] = { area = "doublewide", pushable = 0, xoffset = 80, whileDead = 1 }
    end

    -- Register for ESC close
    local found = false
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == "ReckoningAchievementFrame" then
            found = true
            break
        end
    end
    if not found then
        tinsert(UISpecialFrames, "ReckoningAchievementFrame")
    end
end

-------------------------------------------------------------------------------
-- Constants and Colors
-------------------------------------------------------------------------------

-- Store constants in addon namespace to avoid conflicts
Reckoning_Achievements.GOLD_BORDER_COLOR       = ACHIEVEMENT_GOLD_BORDER_COLOR or CreateColor(1, 0.675, 0.125)
Reckoning_Achievements.RED_BORDER_COLOR        = ACHIEVEMENT_RED_BORDER_COLOR or CreateColor(0.7, 0.15, 0.05)
Reckoning_Achievements.BLUE_BORDER_COLOR       = ACHIEVEMENT_BLUE_BORDER_COLOR or CreateColor(0.129, 0.671, 0.875)
Reckoning_Achievements.YELLOW_BORDER_COLOR     = ACHIEVEMENT_YELLOW_BORDER_COLOR or CreateColor(0.4, 0.2, 0.0)

-- Achievement button heights
Reckoning_Achievements.BUTTON_COLLAPSEDHEIGHT  = 84
Reckoning_Achievements.BUTTON_MAXHEIGHT        = 232

-- Filter constants
Reckoning_Achievements.FILTER_ALL              = 1
Reckoning_Achievements.FILTER_COMPLETE         = 2
Reckoning_Achievements.FILTER_INCOMPLETE       = 3

-- Local references for backward compatibility and convenience
local ACHIEVEMENTBUTTON_COLLAPSEDHEIGHT        = Reckoning_Achievements.BUTTON_COLLAPSEDHEIGHT
local ACHIEVEMENTBUTTON_MAXHEIGHT              = Reckoning_Achievements.BUTTON_MAXHEIGHT
local ACHIEVEMENT_FILTER_ALL                   = Reckoning_Achievements.FILTER_ALL
local ACHIEVEMENT_FILTER_COMPLETE              = Reckoning_Achievements.FILTER_COMPLETE
local ACHIEVEMENT_FILTER_INCOMPLETE            = Reckoning_Achievements.FILTER_INCOMPLETE

-- Filter strings for display
ACHIEVEMENTFRAME_FILTER_ALL                    = ACHIEVEMENTFRAME_FILTER_ALL or "All"
ACHIEVEMENTFRAME_FILTER_COMPLETED              = ACHIEVEMENTFRAME_FILTER_COMPLETED or "Completed"
ACHIEVEMENTFRAME_FILTER_INCOMPLETE             = ACHIEVEMENTFRAME_FILTER_INCOMPLETE or "Incomplete"

-- Backdrop for the main frame with wood border
BACKDROP_ACHIEVEMENTS_0_64                     = BACKDROP_ACHIEVEMENTS_0_64 or {
    edgeFile = "Interface\\AchievementFrame\\UI-Achievement-WoodBorder",
    edgeSize = 64,
    tileEdge = true,
};

-------------------------------------------------------------------------------
-- Data Storage
-------------------------------------------------------------------------------

---@class ReckoningAchievementCategory
---@field id number
---@field name string
---@field order number
---@field parentId number|nil

---@class ReckoningAchievement
---@field id number
---@field categoryId number
---@field name string
---@field description string|nil
---@field points number|nil
---@field icon string|number|nil
---@field current number|nil
---@field total number|nil
---@field completed boolean|nil
---@field criteria table<number, {name: string, completed: boolean}>|nil

-- Store data in addon namespace
Reckoning_Achievements._categories             = Reckoning_Achievements._categories or {}
Reckoning_Achievements._categoryOrder          = Reckoning_Achievements._categoryOrder or {}
Reckoning_Achievements._achievements           = Reckoning_Achievements._achievements or {}
Reckoning_Achievements._achievementsByCategory = Reckoning_Achievements._achievementsByCategory or {}

-- Local reference for internal use
local Data                                     = Reckoning_Achievements

-- Check if an achievement is available based on current week
-- This must be defined before Data functions that use it
local function IsAchievementAvailable(achievement)
    if not achievement then return false end

    -- Achievements without startWeek or with startWeek <= 1 are always available
    local startWeek = achievement.startWeek
    if not startWeek or startWeek <= 1 then
        return true
    end

    -- For achievements with startWeek > 1, check current week
    -- Default to 0 (before launch) if we can't determine - this hides future achievements
    local currentWeek = 0

    -- Try to get current week from DatabaseUtils (calculates from actual time)
    -- or fall back to AchievementUtils (cached value)
    local priv = Private or Reckoning.Private
    if priv then
        if priv.DatabaseUtils and priv.DatabaseUtils.GetCurrentWeek then
            currentWeek = priv.DatabaseUtils:GetCurrentWeek() or 0
        elseif priv.AchievementUtils and priv.AchievementUtils.GetCurrentWeek then
            currentWeek = priv.AchievementUtils:GetCurrentWeek() or 0
        end
    end

    return currentWeek >= startWeek
end

-------------------------------------------------------------------------------
-- Data API
-------------------------------------------------------------------------------

function Data:RegisterCategory(id, name, parentId, order)
    assert(type(id) == "number", "RegisterCategory: id must be a number")
    assert(type(name) == "string", "RegisterCategory: name must be a string")
    local category = {
        id = id,
        name = name,
        parentId = parentId,
        order = order or id,
    }
    self._categories[id] = category
    self._categoryOrder[id] = category.order
    self._achievementsByCategory[id] = self._achievementsByCategory[id] or {}
end

function Data:RegisterAchievement(id, categoryId, def)
    assert(type(id) == "number", "RegisterAchievement: id must be a number")
    assert(type(categoryId) == "number", "RegisterAchievement: categoryId must be a number")
    assert(type(def) == "table", "RegisterAchievement: def must be a table")

    if not self._categories[categoryId] then
        self:RegisterCategory(categoryId, tostring(categoryId))
    end

    local achievement = {
        id = id,
        categoryId = categoryId,
        name = def.name or tostring(id),
        description = def.description,
        points = def.points,
        icon = def.icon,
        current = def.current,
        total = def.total,
        completed = def.completed,
        criteria = def.criteria, -- Array of {name = "...", completed = true/false}
        startWeek = def.startWeek, -- Week when achievement becomes available
        cadence = def.cadence, -- Weekly/Daily cadence
    }
    self._achievements[id] = achievement
    local list = self._achievementsByCategory[categoryId]
    list[#list + 1] = achievement
end

function Data:SetAchievementProgress(id, current, total, completed)
    local achievement = self._achievements[id]
    if not achievement then
        return
    end
    achievement.current = current
    achievement.total = total
    achievement.completed = completed
end

function Data:GetCategories()
    -- Build category list similar to Blizzard's ACHIEVEMENTUI_CATEGORIES
    -- Each element has: id, parent (true if has children, or parentId number for sub-cats), collapsed, hidden

    local categories = {}
    local parentLookup = {}
    local childrenLookup = {}

    -- Add Summary as the first category (special ID -1)
    table.insert(categories, {
        id = -1,
        name = "Summary",
        parent = nil,
        collapsed = nil,
        hidden = false,
    })

    -- First pass: identify parents and children
    for _, category in pairs(self._categories) do
        if category.parentId then
            childrenLookup[category.parentId] = childrenLookup[category.parentId] or {}
            table.insert(childrenLookup[category.parentId], category)
        else
            parentLookup[category.id] = category
        end
    end

    -- Get sorted parent categories
    local sortedParents = {}
    for _, category in pairs(parentLookup) do
        sortedParents[#sortedParents + 1] = category
    end
    table.sort(sortedParents, function(a, b)
        local ao = a.order or a.id
        local bo = b.order or b.id
        if ao ~= bo then return ao < bo end
        return a.name < b.name
    end)

    -- Build final list with children after parents
    for _, parent in ipairs(sortedParents) do
        local hasChildren = childrenLookup[parent.id] ~= nil
        table.insert(categories, {
            id = parent.id,
            name = parent.name,
            parent = hasChildren and true or nil,    -- true means "has children"
            collapsed = hasChildren and true or nil, -- collapsed by default
            hidden = false,
        })

        -- Add children of this parent
        if childrenLookup[parent.id] then
            -- Sort children
            local children = childrenLookup[parent.id]
            table.sort(children, function(a, b)
                local ao = a.order or a.id
                local bo = b.order or b.id
                if ao ~= bo then return ao < bo end
                return a.name < b.name
            end)

            for _, child in ipairs(children) do
                table.insert(categories, {
                    id = child.id,
                    name = child.name,
                    parent = parent.id, -- number means "is child of this parent"
                    hidden = true,      -- hidden by default (parent is collapsed)
                })
            end
        end
    end

    return categories
end

function Data:GetAchievements(categoryId, filter, searchText)
    local sourceList = self._achievementsByCategory[categoryId] or {}
    local list = {}

    -- Apply filter and search
    for _, achievement in ipairs(sourceList) do
        -- Skip achievements that aren't available yet (startWeek > currentWeek)
        if not IsAchievementAvailable(achievement) then
            -- Skip unavailable achievements
        else
            local passFilter = true
            local passSearch = true

            -- Filter check
            if filter == ACHIEVEMENT_FILTER_COMPLETE then
                passFilter = achievement.completed == true
            elseif filter == ACHIEVEMENT_FILTER_INCOMPLETE then
                passFilter = achievement.completed ~= true
            end

            -- Search check
            if searchText and searchText ~= "" then
                local lowerSearch = string.lower(searchText)
                local lowerName = string.lower(achievement.name or "")
                local lowerDesc = string.lower(achievement.description or "")
                passSearch = string.find(lowerName, lowerSearch, 1, true) or string.find(lowerDesc, lowerSearch, 1, true)
            end

            if passFilter and passSearch then
                list[#list + 1] = achievement
            end
        end
    end

    -- Sort: completed first, then by points desc, then name
    table.sort(list, function(a, b)
        local ap = a.points or 0
        local bp = b.points or 0
        if ap ~= bp then
            return ap > bp
        end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

function Data:SearchAllAchievements(searchText)
    if not searchText or searchText == "" then
        return {}
    end

    local results = {}
    local lowerSearch = string.lower(searchText)

    for _, achievement in pairs(self._achievements) do
        -- Skip unavailable achievements
        if IsAchievementAvailable(achievement) then
            local lowerName = string.lower(achievement.name or "")
            local lowerDesc = string.lower(achievement.description or "")
            if string.find(lowerName, lowerSearch, 1, true) or string.find(lowerDesc, lowerSearch, 1, true) then
                results[#results + 1] = achievement
            end
        end
    end

    -- Sort by relevance (name matches first, then by points)
    table.sort(results, function(a, b)
        local aNameMatch = string.find(string.lower(a.name or ""), lowerSearch, 1, true) ~= nil
        local bNameMatch = string.find(string.lower(b.name or ""), lowerSearch, 1, true) ~= nil
        if aNameMatch ~= bNameMatch then
            return aNameMatch
        end
        local ap = a.points or 0
        local bp = b.points or 0
        if ap ~= bp then
            return ap > bp
        end
        return (a.name or "") < (b.name or "")
    end)

    -- Limit to 10 results
    local limited = {}
    for i = 1, math.min(10, #results) do
        limited[i] = results[i]
    end
    return limited
end

function Data:GetTotalPointsEarned()
    local priv = Reckoning and Reckoning.Private
    local addon = priv and priv.Addon
    local db = addon and addon.Database
    local completedData = db and db.completed
    local correctionSync = priv and priv.CorrectionSyncUtils

    local total = 0
    for _, achievement in pairs(self._achievements) do
        if not (IsAchievementAvailable(achievement) and achievement.completed) then
            -- skip
        else
            local points = achievement.points or 0
            if correctionSync and correctionSync.ShouldCountAchievementPoints then
                local completedAt, addonVersion = nil, nil
                if completedData and achievement.id and completedData[achievement.id] then
                    completedAt = completedData[achievement.id].completedAt
                    addonVersion = completedData[achievement.id].addonVersion and tostring(completedData[achievement.id].addonVersion) or nil
                end
                if not correctionSync:ShouldCountAchievementPoints(achievement.id, completedAt, addonVersion) then
                    points = 0
                end
            end
            total = total + points
        end
    end
    return total
end

function Data:GetCompletedAchievementCount()
    local count = 0
    for _, achievement in pairs(self._achievements) do
        if IsAchievementAvailable(achievement) and achievement.completed then
            count = count + 1
        end
    end
    return count
end

function Data:GetTotalAchievementCount()
    local count = 0
    for _, achievement in pairs(self._achievements) do
        if IsAchievementAvailable(achievement) then
            count = count + 1
        end
    end
    return count
end

function Data:GetRecentCompletedAchievements(maxCount)
    maxCount = maxCount or 4
    local completed = {}
    for _, achievement in pairs(self._achievements) do
        if IsAchievementAvailable(achievement) and achievement.completed then
            completed[#completed + 1] = achievement
        end
    end
    -- Sort by most recently completed (we don't have timestamps, so by ID descending for now)
    table.sort(completed, function(a, b)
        return (a.id or 0) > (b.id or 0)
    end)
    -- Return only the first maxCount
    local result = {}
    for i = 1, math.min(maxCount, #completed) do
        result[i] = completed[i]
    end
    return result
end

function Data:GetCategoryProgress(categoryId, includeSubcategories)
    -- Default to including subcategories
    if includeSubcategories == nil then includeSubcategories = true end

    local achievements = self._achievementsByCategory[categoryId] or {}
    local total = 0
    local completed = 0
    for _, achievement in ipairs(achievements) do
        -- Only count available achievements
        if IsAchievementAvailable(achievement) then
            total = total + 1
            if achievement.completed then
                completed = completed + 1
            end
        end
    end

    -- Recursively include subcategory achievements
    if includeSubcategories then
        for _, cat in pairs(self._categories) do
            if cat.parentId == categoryId then
                local subCompleted, subTotal = self:GetCategoryProgress(cat.id, true)
                completed = completed + subCompleted
                total = total + subTotal
            end
        end
    end

    return completed, total
end

function Data:GetAchievementCategory(achievementId)
    local achievement = self._achievements[achievementId]
    if achievement then
        return achievement.categoryId
    end
    return nil
end

-------------------------------------------------------------------------------
-- Data Integration
-- Categories and achievements are registered via Private.AchievementUtils
-- in config.lua. The AchievementUtils:RegisterCategories() and
-- AchievementUtils:RegisterAchievements() functions call Data:RegisterCategory()
-- and Data:RegisterAchievement() to populate this frame's data.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Helper Functions
-------------------------------------------------------------------------------

local function GetAchievementFrame()
    return _G["ReckoningAchievementFrame"]
end

local function FormatProgress(achievement)
    if type(achievement.current) == "number" and type(achievement.total) == "number" then
        return string.format("%d/%d", achievement.current, achievement.total)
    end
    return nil
end

-------------------------------------------------------------------------------
-- Admin Tab: Ticket UI
-------------------------------------------------------------------------------

--- Called from XML when clicking Tickets, Actions, or Log in the Admin left panel.
function ReckoningAdmin_SelectSubTab(frame, subTab)
    if not frame or not frame.Admin then
        return
    end
    local admin = frame.Admin
    admin.selectedSubTab = subTab
    if admin.ScrollFrame then admin.ScrollFrame:SetShown(subTab == "tickets") end
    if admin.ActionsScrollFrame then admin.ActionsScrollFrame:SetShown(subTab == "actions") end
    if admin.LogScrollFrame then admin.LogScrollFrame:SetShown(subTab == "log") end
    if admin.LogHeader then admin.LogHeader:SetShown(subTab == "log") end
    if admin.LogFilterRow then admin.LogFilterRow:SetShown(subTab == "log") end
    if admin.LogEmptyState and subTab ~= "log" then admin.LogEmptyState:Hide() end
    if admin.ResolveButton then admin.ResolveButton:SetShown(subTab == "tickets") end
    if admin.EmptyState then admin.EmptyState:Hide() end
    if admin.ActionsEmptyState then admin.ActionsEmptyState:Hide() end
    if admin.LogEmptyState then admin.LogEmptyState:Hide() end
    if subTab == "tickets" then
        ReckoningAdminTickets_Refresh(frame)
    elseif subTab == "actions" then
        ReckoningAdminActions_Refresh(frame)
    elseif subTab == "log" then
        ReckoningAdminLog_Refresh(frame)
    end
end

function ReckoningAdmin_EnsureUI(frame)
    if not frame then return end
    -- Admin frame and left panel (Categories with Tickets/Actions buttons) come from XML.
    local admin = frame.Admin
    if not admin or not admin.Content then
        return
    end
    if admin.ScrollFrame then
        return
    end

    local content = admin.Content
    admin.selectedSubTab = "tickets"

    local info = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("TOPLEFT", 16, -14)
    info:SetText("Officer/GM only.")
    admin.Info = info

    local empty = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("CENTER", 0, 0)
    empty:SetText("No tickets.")
    empty:Hide()
    admin.EmptyState = empty

    local resolve = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resolve:SetSize(120, 22)
    resolve:SetPoint("TOPRIGHT", -16, -14)
    resolve:SetText("Resolve")
    resolve:Disable()
    admin.ResolveButton = resolve

    -- Only create HybridScrollFrame for officers/GM; Blizzard's template expects a scrollBar
    -- child which we must create when building the frame in Lua. Non-admins never get the
    -- scroll frame, so they never hit HybridScrollFrame_CreateButtons (scrollBar nil).
    local priv = Private or Reckoning.Private
    local ticketSync = priv and priv.TicketSyncUtils
    local isAdmin = ticketSync and ticketSync:IsAdmin() == true

    if isAdmin then
        local contentTop = 40
        local scrollName = "ReckoningAchievementFrameAdminScroll"
        local scroll = CreateFrame("ScrollFrame", scrollName, content, "HybridScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 8, -contentTop)
        scroll:SetPoint("BOTTOMRIGHT", -28, 10)
        admin.ScrollFrame = scroll

        -- HybridScrollFrame_CreateButtons expects scroll.scrollBar; XML templates add a
        -- Slider named "$parentScrollBar". Create it when building in Lua.
        local bar = CreateFrame("Slider", scrollName .. "ScrollBar", scroll, "HybridScrollBarTemplate")
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 1, -14)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 1, 12)
        scroll.scrollBar = bar

        HybridScrollFrame_CreateButtons(scroll, "ReckoningGuildEventButtonTemplate", 0, -4)

        for _, btn in ipairs(scroll.buttons or {}) do
            btn:SetHeight(64)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, mouseButton)
                if mouseButton == "RightButton" and self.achievementId and UIDropDownMenu_Initialize and ToggleDropDownMenu then
                    EnsureBugReportDialog()
                    local dd = EnsureBugReportDropDown()
                    dd.achievementId = self.achievementId
                    ToggleDropDownMenu(1, nil, dd, "cursor", 0, 0)
                    return
                end
                admin.selectedTicketId = self.ticketId
                if admin.ResolveButton then
                    admin.ResolveButton:SetEnabled(self.ticketId ~= nil)
                end
                ReckoningAdminTickets_Refresh(frame)
            end)
        end

        -- Actions panel: scroll list of corrections
        local actionsScrollName = "ReckoningAchievementFrameAdminActionsScroll"
        local actionsScroll = CreateFrame("ScrollFrame", actionsScrollName, content, "HybridScrollFrameTemplate")
        actionsScroll:SetPoint("TOPLEFT", 8, -contentTop)
        actionsScroll:SetPoint("BOTTOMRIGHT", -28, 10)
        local actionsBar = CreateFrame("Slider", actionsScrollName .. "ScrollBar", actionsScroll, "HybridScrollBarTemplate")
        actionsBar:SetPoint("TOPLEFT", actionsScroll, "TOPRIGHT", 1, -14)
        actionsBar:SetPoint("BOTTOMLEFT", actionsScroll, "BOTTOMRIGHT", 1, 12)
        actionsScroll.scrollBar = actionsBar
        HybridScrollFrame_CreateButtons(actionsScroll, "ReckoningGuildEventButtonTemplate", 0, -4)
        admin.ActionsScrollFrame = actionsScroll
        actionsScroll:Hide()
        admin.ExpandedAchievements = admin.ExpandedAchievements or {}
        for _, btn in ipairs(actionsScroll.buttons or {}) do
            -- Prevent template OnClick from capturing; let Cancel/Manage/Expand receive clicks
            btn:SetScript("OnClick", nil)
            local expandBtn = CreateFrame("Button", nil, btn)
            expandBtn:SetSize(22, 22)
            expandBtn:SetPoint("LEFT", btn, "LEFT", 4, 0)
            local expandFs = expandBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            expandFs:SetPoint("CENTER", 0, 0)
            expandFs:SetText("▼")
            expandBtn.text = expandFs
            expandBtn:SetScript("OnClick", function(self)
                local aid = self.achievementId
                if aid == nil then return end
                admin.ExpandedAchievements[aid] = not admin.ExpandedAchievements[aid]
                ReckoningAdminActions_Refresh(frame)
            end)
            btn.ExpandButton = expandBtn
            -- Cancel: higher frame level so it stays clickable above template layers
            local cancelBtn = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate")
            cancelBtn:SetSize(56, 22)
            cancelBtn:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            cancelBtn:SetText("Cancel")
            btn.CancelButton = cancelBtn
            -- Manage: same, so clicks register
            local manageBtn = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate")
            manageBtn:SetSize(56, 22)
            manageBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -6, 0)
            manageBtn:SetText("Manage")
            btn.ManageButton = manageBtn
        end

        local actionsEmpty = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        actionsEmpty:SetPoint("CENTER", 0, -20)
        actionsEmpty:SetText("No actions yet.")
        actionsEmpty:Hide()
        admin.ActionsEmptyState = actionsEmpty

        -- Log panel: roster-style header + filters + scroll
        local logHeader = CreateFrame("Frame", nil, content)
        logHeader:SetPoint("TOPLEFT", 8, -contentTop)
        logHeader:SetPoint("TOPRIGHT", -28, -contentTop)
        logHeader:SetHeight(24)
        logHeader:Hide()
        admin.LogHeader = logHeader
        local logHeaderBg = logHeader:CreateTexture(nil, "BACKGROUND")
        logHeaderBg:SetAllPoints()
        logHeaderBg:SetColorTexture(0, 0, 0, 0.5)
        local function addLogHeaderButton(parent, text, x, width, column)
            local btn = CreateFrame("Button", nil, parent)
            btn:SetPoint("LEFT", x, 0)
            btn:SetSize(width, 24)
            local fs = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            fs:SetPoint("LEFT", 4, 0)
            fs:SetText(text)
            fs:SetTextColor(1, 0.82, 0)
            btn:SetScript("OnClick", function()
                if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or "igMainMenuOptionCheckBoxOn") end
                ReckoningAdminLog_SortBy(frame, column)
            end)
            btn:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1) end)
            btn:SetScript("OnLeave", function() fs:SetTextColor(1, 0.82, 0) end)
            return btn
        end
        addLogHeaderButton(logHeader, "Date", 0, 120, "issuedAt")
        addLogHeaderButton(logHeader, "Author", 124, 90, "issuedBy")
        addLogHeaderButton(logHeader, "Type", 218, 130, "type")
        addLogHeaderButton(logHeader, "Achievement", 352, 200, "achievementName")

        admin.LogSortState = { column = "issuedAt", ascending = false }
        admin.LogFilters = { searchText = "", typeFilter = nil, authorFilter = nil, datePreset = "all" }

        local logFilterRow = CreateFrame("Frame", nil, content)
        logFilterRow:SetPoint("TOPLEFT", 8, -contentTop - 28)
        logFilterRow:SetPoint("TOPRIGHT", -28, -contentTop - 28)
        logFilterRow:SetHeight(26)
        logFilterRow:Hide()
        admin.LogFilterRow = logFilterRow
        local searchBox = CreateFrame("EditBox", nil, logFilterRow, "InputBoxTemplate")
        searchBox:SetPoint("LEFT", 0, 0)
        searchBox:SetSize(140, 20)
        searchBox:SetAutoFocus(false)
        searchBox:SetScript("OnTextChanged", function() admin.LogFilters.searchText = searchBox:GetText(); ReckoningAdminLog_Refresh(frame) end)
        searchBox:SetScript("OnEscapePressed", function() searchBox:ClearFocus() end)
        admin.LogSearchBox = searchBox
        local searchLabel = logFilterRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        searchLabel:SetPoint("RIGHT", searchBox, "LEFT", -4, 0)
        searchLabel:SetText("Search:")
        local function createLogFilterDropdown(name, width, options, getKey)
            local dd = CreateFrame("Frame", nil, logFilterRow, "UIDropDownMenuTemplate")
            dd:SetPoint("LEFT", getKey and 150 or (name == "Type" and 150 or (name == "Author" and 280 or 380)), 0)
            UIDropDownMenu_SetWidth(dd, width or 100)
            dd.GetKey = getKey
            dd.options = options
            return dd
        end
        local typeDD = CreateFrame("Frame", nil, logFilterRow, "UIDropDownMenuTemplate")
        typeDD:SetPoint("LEFT", 150, 0)
        UIDropDownMenu_SetWidth(typeDD, 120)
        admin.LogTypeDropdown = typeDD
        local authorDD = CreateFrame("Frame", nil, logFilterRow, "UIDropDownMenuTemplate")
        authorDD:SetPoint("LEFT", 278, 0)
        UIDropDownMenu_SetWidth(authorDD, 100)
        admin.LogAuthorDropdown = authorDD
        local dateDD = CreateFrame("Frame", nil, logFilterRow, "UIDropDownMenuTemplate")
        dateDD:SetPoint("LEFT", 386, 0)
        UIDropDownMenu_SetWidth(dateDD, 80)
        admin.LogDateDropdown = dateDD

        local logScrollName = "ReckoningAchievementFrameAdminLogScroll"
        local logScroll = CreateFrame("ScrollFrame", logScrollName, content, "HybridScrollFrameTemplate")
        logScroll:SetPoint("TOPLEFT", 8, -contentTop - 58)
        logScroll:SetPoint("BOTTOMRIGHT", -28, 10)
        local logBar = CreateFrame("Slider", logScrollName .. "ScrollBar", logScroll, "HybridScrollBarTemplate")
        logBar:SetPoint("TOPLEFT", logScroll, "TOPRIGHT", 1, -14)
        logBar:SetPoint("BOTTOMLEFT", logScroll, "BOTTOMRIGHT", 1, 12)
        logScroll.scrollBar = logBar
        HybridScrollFrame_CreateButtons(logScroll, "ReckoningGuildRosterButtonTemplate", 0, 0, nil, nil, 0, -2)
        admin.LogScrollFrame = logScroll
        logScroll:Hide()
        for i, btn in ipairs(logScroll.buttons or {}) do
            btn:SetHeight(22)
            btn:RegisterForClicks("LeftButtonUp")
            if not btn.LogDateCol then
                btn.LogDateCol = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                btn.LogDateCol:SetPoint("LEFT", 6, 0)
                btn.LogAuthorCol = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                btn.LogAuthorCol:SetPoint("LEFT", 128, 0)
                btn.LogTypeCol = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                btn.LogTypeCol:SetPoint("LEFT", 222, 0)
                btn.LogAchievementCol = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                btn.LogAchievementCol:SetPoint("LEFT", 356, 0)
                btn.bg = btn:CreateTexture(nil, "BACKGROUND")
                btn.bg:SetAllPoints()
                btn.bg:SetColorTexture(0, 0, 0, 0.2)
            end
        end

        local logEmpty = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        logEmpty:SetPoint("CENTER", 0, -20)
        logEmpty:SetText("No log entries.")
        logEmpty:Hide()
        admin.LogEmptyState = logEmpty
    else
        admin.ScrollFrame = nil
        admin.ActionsScrollFrame = nil
        admin.LogScrollFrame = nil
    end

    resolve:SetScript("OnClick", function()
        local privRes = Private or Reckoning.Private
        local ticketSyncRes = privRes and privRes.TicketSyncUtils
        if not ticketSyncRes or not ticketSyncRes.ResolveTicket then return end
        if not admin.selectedTicketId then return end
        ticketSyncRes:ResolveTicket(admin.selectedTicketId)
        admin.selectedTicketId = nil
        resolve:Disable()
        ReckoningAdminTickets_Refresh(frame)
    end)
end

local function Admin_GetSortedTickets()
    local priv = Private or Reckoning.Private
    local ticketSync = priv and priv.TicketSyncUtils
    if not ticketSync or not ticketSync.GetTickets then
        return {}, false
    end
    local isAdmin = ticketSync:IsAdmin() == true
    local tickets = {}
    for id, t in pairs(ticketSync:GetTickets() or {}) do
        if type(t) == "table" then
            tickets[#tickets + 1] = t
        end
    end
    table.sort(tickets, function(a, b)
        local at = tonumber(a.createdAt) or 0
        local bt = tonumber(b.createdAt) or 0
        if at ~= bt then return at > bt end
        return tostring(a.id or "") < tostring(b.id or "")
    end)
    return tickets, isAdmin
end

function ReckoningAdminTickets_Refresh(frame)
    if not frame or not frame.Admin then return end
    local admin = frame.Admin

    local tickets, isAdmin = Admin_GetSortedTickets()
    if admin.Info then
        admin.Info:SetShown(not isAdmin)
    end
    if admin.ResolveButton then
        admin.ResolveButton:SetShown(isAdmin)
        admin.ResolveButton:SetEnabled(isAdmin and admin.selectedTicketId ~= nil)
    end

    if not isAdmin then
        if admin.ScrollFrame then admin.ScrollFrame:Hide() end
        if admin.ActionsScrollFrame then admin.ActionsScrollFrame:Hide() end
        if admin.EmptyState then
            admin.EmptyState:SetText("Admin only.")
            admin.EmptyState:Show()
        end
        if admin.ActionsEmptyState then admin.ActionsEmptyState:Hide() end
        return
    end

    if admin.selectedSubTab == "actions" then
        ReckoningAdminActions_Refresh(frame)
        return
    end

    -- Admin: request latest tickets when opening/refreshing the tab.
    local priv = Private or Reckoning.Private
    local ticketSync = priv and priv.TicketSyncUtils
    if ticketSync and ticketSync.RequestTickets then
        ticketSync:RequestTickets()
    end

    local openTickets = {}
    for _, t in ipairs(tickets) do
        if t.status ~= "resolved" then
            openTickets[#openTickets + 1] = t
        end
    end

    if admin.EmptyState then
        admin.EmptyState:SetText("No tickets.")
        admin.EmptyState:SetShown(#openTickets == 0)
    end
    if admin.ScrollFrame then
        admin.ScrollFrame:SetShown(admin.selectedSubTab == "tickets" and #openTickets > 0)
    end

    local scroll = admin.ScrollFrame
    if not scroll or not scroll.buttons then return end

    local offset = HybridScrollFrame_GetOffset(scroll)
    local buttons = scroll.buttons
    local buttonHeight = 64
    local totalHeight = #openTickets * (buttonHeight + 4)
    HybridScrollFrame_Update(scroll, totalHeight, scroll:GetHeight())

    for i = 1, #buttons do
        local index = offset + i
        local btn = buttons[i]
        local t = openTickets[index]

        if not t then
            btn:Hide()
        else
            btn.ticketId = t.id
            btn.achievementId = t.achievementId

            local achievement = Data and Data._achievements and Data._achievements[t.achievementId]
            local name = achievement and achievement.name or ("Achievement #" .. tostring(t.achievementId or "?"))
            local icon = achievement and achievement.icon or "Interface\\Icons\\INV_Misc_QuestionMark"

            if btn.icon and btn.icon.texture then
                btn.icon.texture:SetTexture(icon)
            end
            if btn.label then
                btn.label:SetText(string.format("[%s] %s", tostring(t.id or "?"), name))
            end
            if btn.description then
                local reporter = tostring(t.reporter or "Player")
                local reason = tostring(t.reason or "")
                btn.description:SetText(string.format("|cffaaaaaa%s:|r %s", reporter, reason))
            end

            -- Reuse shield points text to show ACK status.
            if btn.shield and btn.shield.points then
                if t.ackedAt then
                    btn.shield.points:SetText("ACK")
                else
                    btn.shield.points:SetText("")
                end
            end

            btn:SetAlpha((admin.selectedTicketId == t.id) and 1 or 0.95)
            btn:Show()
        end
    end
end

function ReckoningAdminActions_Refresh(frame)
    if not frame or not frame.Admin then return end
    local admin = frame.Admin
    local correctionSync = (Private or Reckoning.Private) and (Private or Reckoning.Private).CorrectionSyncUtils
    if not correctionSync or not correctionSync.GetCorrections then return end
    if correctionSync.RequestCorrections then
        correctionSync:RequestCorrections()
    end
    if not admin.ActionsScrollFrame or not admin.ActionsScrollFrame.buttons then return end

    local activeList = {}
    for _, c in pairs(correctionSync:GetCorrections()) do
        if type(c) == "table" and c.id and c.type ~= "cancel" and not (correctionSync.IsCorrectionVoided and correctionSync:IsCorrectionVoided(c)) then
            activeList[#activeList + 1] = c
        end
    end

    local grouped = {}
    for _, c in ipairs(activeList) do
        local aid = c.achievementId
        if not grouped[aid] then
            grouped[aid] = { achievementId = aid, corrections = {} }
        end
        grouped[aid].corrections[#grouped[aid].corrections + 1] = c
    end
    local groups = {}
    for _, grp in pairs(grouped) do
        table.sort(grp.corrections, function(a, b) return (tonumber(a.issuedAt) or 0) > (tonumber(b.issuedAt) or 0) end)
        groups[#groups + 1] = grp
    end
    table.sort(groups, function(a, b)
        local at = #a.corrections > 0 and (tonumber(a.corrections[1].issuedAt) or 0) or 0
        local bt = #b.corrections > 0 and (tonumber(b.corrections[1].issuedAt) or 0) or 0
        return at > bt
    end)

    local displayList = {}
    for _, grp in ipairs(groups) do
        local aid = grp.achievementId
        local achievement = Data and Data._achievements and Data._achievements[aid]
        grp.name = achievement and achievement.name or ("Achievement #" .. tostring(aid or "?"))
        grp.icon = achievement and achievement.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        displayList[#displayList + 1] = { type = "group", achievementId = aid, name = grp.name, icon = grp.icon, corrections = grp.corrections }
        if admin.ExpandedAchievements[aid] ~= false then
            for _, c in ipairs(grp.corrections) do
                displayList[#displayList + 1] = { type = "action", correction = c }
            end
        end
    end

    if admin.ActionsEmptyState then
        admin.ActionsEmptyState:SetShown(#displayList == 0)
    end
    local scroll = admin.ActionsScrollFrame
    scroll:SetShown(#displayList > 0)

    -- One row height for all: achievement rows "regular" size, action rows same so Cancel has room
    local ROW_HEIGHT = 52
    local ROW_GAP = 4
    local totalHeight = #displayList * (ROW_HEIGHT + ROW_GAP)
    local offset = HybridScrollFrame_GetOffset(scroll)
    local buttons = scroll.buttons
    HybridScrollFrame_Update(scroll, totalHeight, scroll:GetHeight())

    for i = 1, #buttons do
        local index = offset + i
        local btn = buttons[i]
        local item = displayList[index]
        if not item then
            if btn.ExpandButton then btn.ExpandButton:Hide() end
            if btn.CancelButton then btn.CancelButton:Hide() end
            if btn.ManageButton then btn.ManageButton:Hide() end
            btn:Hide()
        else
            local isGroup = (item.type == "group")
            btn:SetHeight(ROW_HEIGHT)

            -- Keep Cancel/Manage above template layers so they receive clicks
            local baseLevel = btn:GetFrameLevel()
            if btn.CancelButton then btn.CancelButton:SetFrameLevel(baseLevel + 10) end
            if btn.ManageButton then btn.ManageButton:SetFrameLevel(baseLevel + 10) end
            if btn.ExpandButton then btn.ExpandButton:SetFrameLevel(baseLevel + 10) end

            if isGroup then
                btn.ExpandButton.achievementId = item.achievementId
                btn.ExpandButton:Show()
                btn.ExpandButton.text:SetText((admin.ExpandedAchievements[item.achievementId] ~= false) and "▼" or "▶")
                if btn.icon and btn.icon.texture then
                    btn.icon.texture:SetTexture(item.icon)
                    btn.icon.texture:Show()
                end
                if btn.label then
                    btn.label:SetText(item.name)
                    btn.label:SetWidth(280)
                end
                if btn.description then
                    btn.description:SetText(#item.corrections == 1 and "1 action" or (#item.corrections .. " actions"))
                    btn.description:Show()
                end
                if btn.CancelButton then btn.CancelButton:Hide() end
                if btn.ManageButton then
                    btn.ManageButton:Show()
                    btn.ManageButton.achievementId = item.achievementId
                    btn.ManageButton:SetScript("OnClick", function(self)
                        local aid = self.achievementId
                        if aid and ReckoningAchievementManage_Show then ReckoningAchievementManage_Show(aid) end
                    end)
                end
            else
                local c = item.correction
                if btn.ExpandButton then btn.ExpandButton:Hide() end
                local achievement = Data and Data._achievements and Data._achievements[c.achievementId]
                local icon = achievement and achievement.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
                local typeLabel = (c.type == "full_invalidate" and "Invalidate (all)") or (c.type == "invalidate_from_date" and "Invalid from date") or (c.type == "revalidate" and "Revalidate") or (c.type == "reset" and "Reset") or tostring(c.type or "?")
                local dateStr = c.issuedAt and date("%Y-%m-%d %H:%M", c.issuedAt) or ""
                local params = ""
                if c.type == "invalidate_from_date" and c.fromDate then
                    params = " from " .. date("%Y-%m-%d %H:%M", c.fromDate)
                elseif (c.type == "revalidate" or c.type == "reset") and c.addonVersion and c.addonVersion ~= "" then
                    params = " min v" .. tostring(c.addonVersion)
                end
                if params ~= "" then typeLabel = typeLabel .. params end
                if btn.icon and btn.icon.texture then
                    btn.icon.texture:SetTexture(icon)
                    btn.icon.texture:Show()
                end
                if btn.label then
                    btn.label:SetText("  " .. typeLabel)
                    btn.label:SetWidth(240)
                end
                if btn.description then
                    btn.description:SetText(string.format("|cff888888%s|r %s", tostring(c.issuedBy or "?"), dateStr))
                    btn.description:Show()
                end
                if btn.CancelButton then
                    btn.CancelButton:Show()
                    btn.CancelButton.correctionId = c.id
                    btn.CancelButton:SetScript("OnClick", function(self)
                        local id = self.correctionId
                        if not id then return end
                        local priv = Private or Reckoning.Private
                        local cs = priv and priv.CorrectionSyncUtils
                        if cs and cs.CancelCorrection then
                            cs:CancelCorrection(id)
                            ReckoningAdminActions_Refresh(frame)
                            if ReckoningAdminLog_Refresh then ReckoningAdminLog_Refresh(frame) end
                        end
                    end)
                end
                if btn.ManageButton then btn.ManageButton:Hide() end
            end
            btn:Show()
        end
    end
end

function ReckoningAdminLog_SortBy(frame, column)
    if not frame or not frame.Admin then return end
    local admin = frame.Admin
    local state = admin.LogSortState
    if not state then return end
    state.ascending = (state.column == column) and not state.ascending or (column ~= state.column)
    state.column = column
    ReckoningAdminLog_Refresh(frame)
end

local function AdminLog_TypeLabel(ctype)
    if ctype == "full_invalidate" then return "Invalidate (all)" end
    if ctype == "invalidate_from_date" then return "Invalid from date" end
    if ctype == "revalidate" then return "Revalidate" end
    if ctype == "cancel" then return "Cancel" end
    if ctype == "reset" then return "Reset" end
    return tostring(ctype or "?")
end

function ReckoningAdminLog_Refresh(frame)
    if not frame or not frame.Admin then return end
    local admin = frame.Admin
    local correctionSync = (Private or Reckoning.Private) and (Private or Reckoning.Private).CorrectionSyncUtils
    if not correctionSync or not correctionSync.GetCorrections then return end
    if correctionSync.RequestCorrections then
        correctionSync:RequestCorrections()
    end
    if not admin.LogScrollFrame or not admin.LogScrollFrame.buttons then return end

    local list = {}
    local authors = {}
    for _, c in pairs(correctionSync:GetCorrections()) do
        if type(c) == "table" and c.id then
            list[#list + 1] = c
            local who = tostring(c.issuedBy or "?")
            if who ~= "" then authors[who] = true end
        end
    end

    local filters = admin.LogFilters or {}
    local searchText = (filters.searchText or ""):lower():match("^%s*(.-)%s*$") or ""
    if searchText ~= "" then
        local filtered = {}
        for _, c in ipairs(list) do
            local achievement = Data and Data._achievements and Data._achievements[c.achievementId]
            local name = (achievement and achievement.name or ("Achievement #" .. tostring(c.achievementId or "?"))):lower()
            local idStr = tostring(c.achievementId or ""):lower()
            if name:find(searchText, 1, true) or idStr:find(searchText, 1, true) then
                filtered[#filtered + 1] = c
            end
        end
        list = filtered
    end
    if filters.typeFilter and filters.typeFilter ~= "" then
        local filtered = {}
        for _, c in ipairs(list) do
            if c.type == filters.typeFilter then filtered[#filtered + 1] = c end
        end
        list = filtered
    end
    if filters.authorFilter and filters.authorFilter ~= "" then
        local filtered = {}
        for _, c in ipairs(list) do
            if tostring(c.issuedBy or "") == filters.authorFilter then filtered[#filtered + 1] = c end
        end
        list = filtered
    end
    local now = time()
    local datePreset = filters.datePreset or "all"
    if datePreset == "24h" or datePreset == "7d" or datePreset == "30d" then
        local sec = (datePreset == "24h" and 86400) or (datePreset == "7d" and 604800) or 2592000
        local cutoff = now - sec
        local filtered = {}
        for _, c in ipairs(list) do
            if (tonumber(c.issuedAt) or 0) >= cutoff then filtered[#filtered + 1] = c end
        end
        list = filtered
    end

    local sortCol = (admin.LogSortState and admin.LogSortState.column) or "issuedAt"
    local ascending = admin.LogSortState and admin.LogSortState.ascending
    table.sort(list, function(a, b)
        local av, bv
        if sortCol == "issuedAt" then
            av = tonumber(a.issuedAt) or 0
            bv = tonumber(b.issuedAt) or 0
        elseif sortCol == "issuedBy" then
            av = tostring(a.issuedBy or "")
            bv = tostring(b.issuedBy or "")
        elseif sortCol == "type" then
            av = tostring(a.type or "")
            bv = tostring(b.type or "")
        else
            local aa = Data and Data._achievements and Data._achievements[a.achievementId]
            local ab = Data and Data._achievements and Data._achievements[b.achievementId]
            av = (aa and aa.name or ("Achievement #" .. tostring(a.achievementId or "?")))
            bv = (ab and ab.name or ("Achievement #" .. tostring(b.achievementId or "?")))
        end
        if av == bv then
            return (tonumber(a.issuedAt) or 0) > (tonumber(b.issuedAt) or 0)
        end
        if sortCol == "issuedAt" or sortCol == "issuedBy" or sortCol == "type" then
            if ascending then return av < bv else return av > bv end
        end
        if ascending then return av < bv else return av > bv end
    end)

    -- Update filter dropdowns (Type, Author, Date)
    if admin.LogTypeDropdown and UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(admin.LogTypeDropdown, function(self, level)
            if level ~= 1 then return end
            local opts = {
                { value = nil, text = "All types" },
                { value = "full_invalidate", text = "Invalidate (all)" },
                { value = "invalidate_from_date", text = "Invalid from date" },
                { value = "revalidate", text = "Revalidate" },
                { value = "cancel", text = "Cancel" },
                { value = "reset", text = "Reset" },
            }
            for _, o in ipairs(opts) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = o.text
                info.func = function(_, val)
                    admin.LogFilters.typeFilter = val
                    UIDropDownMenu_SetText(admin.LogTypeDropdown, o.text)
                    ReckoningAdminLog_Refresh(frame)
                end
                info.arg1 = o.value
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        UIDropDownMenu_SetText(admin.LogTypeDropdown, filters.typeFilter and AdminLog_TypeLabel(filters.typeFilter) or "All types")
    end
    if admin.LogAuthorDropdown and UIDropDownMenu_Initialize then
        local authorList = {}
        for who in pairs(authors) do authorList[#authorList + 1] = who end
        table.sort(authorList)
        UIDropDownMenu_Initialize(admin.LogAuthorDropdown, function(self, level)
            if level ~= 1 then return end
            local info = UIDropDownMenu_CreateInfo()
            info.text = "All"
            info.func = function()
                admin.LogFilters.authorFilter = nil
                UIDropDownMenu_SetText(admin.LogAuthorDropdown, "All")
                ReckoningAdminLog_Refresh(frame)
            end
            UIDropDownMenu_AddButton(info, level)
            for _, who in ipairs(authorList) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = who
                info.func = function(_, val)
                    admin.LogFilters.authorFilter = val
                    UIDropDownMenu_SetText(admin.LogAuthorDropdown, who)
                    ReckoningAdminLog_Refresh(frame)
                end
                info.arg1 = who
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        UIDropDownMenu_SetText(admin.LogAuthorDropdown, (filters.authorFilter and filters.authorFilter ~= "") and filters.authorFilter or "All")
    end
    if admin.LogDateDropdown and UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(admin.LogDateDropdown, function(self, level)
            if level ~= 1 then return end
            local presets = { { "all", "All" }, { "24h", "24h" }, { "7d", "7 days" }, { "30d", "30 days" } }
            for _, p in ipairs(presets) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = p[2]
                info.func = function(_, val)
                    admin.LogFilters.datePreset = val
                    UIDropDownMenu_SetText(admin.LogDateDropdown, p[2])
                    ReckoningAdminLog_Refresh(frame)
                end
                info.arg1 = p[1]
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        local dateLabel = (datePreset == "24h" and "24h") or (datePreset == "7d" and "7 days") or (datePreset == "30d" and "30 days") or "All"
        UIDropDownMenu_SetText(admin.LogDateDropdown, dateLabel)
    end

    if admin.LogEmptyState then
        admin.LogEmptyState:SetShown(#list == 0)
    end
    local scroll = admin.LogScrollFrame
    if scroll then
        scroll:SetShown(#list > 0)
        if scroll.scrollBar and scroll.scrollBar.SetValue then scroll.scrollBar:SetValue(0) end
    end

    local offset = HybridScrollFrame_GetOffset(scroll)
    local buttons = scroll.buttons
    local buttonHeight = 22
    local totalHeight = #list * (buttonHeight + 2)
    HybridScrollFrame_Update(scroll, totalHeight, scroll:GetHeight())

    for i = 1, #buttons do
        local index = offset + i
        local btn = buttons[i]
        local c = list[index]
        if not c then
            btn:Hide()
        else
            local achievement = Data and Data._achievements and Data._achievements[c.achievementId]
            local name = achievement and achievement.name or ("Achievement #" .. tostring(c.achievementId or "?"))
            btn.LogDateCol:SetText(c.issuedAt and date("%Y-%m-%d %H:%M", c.issuedAt) or "")
            btn.LogAuthorCol:SetText(tostring(c.issuedBy or "?"))
            btn.LogTypeCol:SetText(AdminLog_TypeLabel(c.type))
            btn.LogAchievementCol:SetText(name)
            if index % 2 == 0 then btn.bg:Show() else btn.bg:Hide() end
            btn:SetHeight(buttonHeight)
            btn:Show()
        end
    end
end

-------------------------------------------------------------------------------
-- Toggle Function
-------------------------------------------------------------------------------

function ReckoningAchievementFrame_Toggle()
    -- Register with Blizzard UI system (deferred to avoid taint at load time)
    RegisterFrameWithBlizzardUI()

    local frame = GetAchievementFrame()
    if not frame then
        return
    end
    if frame:IsShown() then
        if HideUIPanel then
            HideUIPanel(frame)
        else
            frame:Hide()
        end
    else
        if ShowUIPanel then
            ShowUIPanel(frame)
        else
            frame:Show()
        end
    end
end

-------------------------------------------------------------------------------
-- Frame Handlers
-------------------------------------------------------------------------------

function ReckoningGoldBorderBackdrop_OnLoad(self)
    local color = Reckoning_Achievements.GOLD_BORDER_COLOR or ACHIEVEMENT_GOLD_BORDER_COLOR
    if color and color.GetRGB then
        self:SetBackdropBorderColor(color:GetRGB())
    elseif color then
        self:SetBackdropBorderColor(color.r or 1, color.g or 0.675, color.b or 0.125)
    end
    -- Make the background transparent
    self:SetBackdropColor(0, 0, 0, 0)
    self:SetFrameLevel(self:GetFrameLevel() + 1)
end

function ReckoningAchievementFrame_OnLoad(self)
    self.selectedCategoryId = nil
    self.selectedAchievementId = nil

    -- Apply backdrop (wood border frame)
    if self.ApplyBackdrop then
        self:ApplyBackdrop()
    elseif BACKDROP_ACHIEVEMENTS_0_64 then
        self:SetBackdrop(BACKDROP_ACHIEVEMENTS_0_64)
    end

    -- Get references to child frames via parentKey or by name
    self.Header = self.Header or _G[self:GetName() .. "Header"]
    self.Categories = self.Categories or _G[self:GetName() .. "Categories"]
    self.Achievements = self.Achievements or _G[self:GetName() .. "Achievements"]

    -- Get scroll frame containers
    local categoriesContainer = self.Categories and
        (self.Categories.Container or _G[self.Categories:GetName() .. "Container"])
    local achievementsContainer = self.Achievements and
        (self.Achievements.Container or _G[self.Achievements:GetName() .. "Container"])

    self.categoriesContainer = categoriesContainer
    self.achievementsContainer = achievementsContainer

    -- Set up update functions
    if categoriesContainer then
        categoriesContainer.update = function()
            ReckoningAchievementFrame_UpdateCategories(self)
        end
    end

    if achievementsContainer then
        achievementsContainer.update = function()
            ReckoningAchievementFrame_UpdateAchievements(self)
        end
    end

    -- Create scroll buttons
    if categoriesContainer and HybridScrollFrame_CreateButtons then
        HybridScrollFrame_CreateButtons(categoriesContainer, "ReckoningAchievementCategoryButtonTemplate", 0, -2)
    end

    if achievementsContainer and HybridScrollFrame_CreateButtons then
        HybridScrollFrame_CreateButtons(achievementsContainer, "ReckoningAchievementButtonTemplate", 0, -2)
    end

    -- Don't hide scrollbars
    if categoriesContainer and HybridScrollFrame_SetDoNotHideScrollBar then
        HybridScrollFrame_SetDoNotHideScrollBar(categoriesContainer, true)
    end
    if achievementsContainer and HybridScrollFrame_SetDoNotHideScrollBar then
        HybridScrollFrame_SetDoNotHideScrollBar(achievementsContainer, true)
    end

    -- Initialize filter
    self.currentFilter = ACHIEVEMENT_FILTER_ALL
    self.searchText = ""

    -- Set up filter dropdown
    self.FilterDropDown = self.FilterDropDown or _G[self:GetName() .. "FilterDropDown"]
    if self.FilterDropDown and UIDropDownMenu_Initialize then
        UIDropDownMenu_SetWidth(self.FilterDropDown, 100)
        UIDropDownMenu_Initialize(self.FilterDropDown, function(dropdown)
            ReckoningAchievementFilterDropDown_Initialize(dropdown, self)
        end)
        UIDropDownMenu_SetText(self.FilterDropDown, ACHIEVEMENTFRAME_FILTER_ALL)
    end

    -- Set up search box
    self.SearchBox = self.SearchBox or _G[self:GetName() .. "SearchBox"]
    if self.SearchBox then
        self.SearchBox:SetScript("OnTextChanged", function(editBox)
            SearchBoxTemplate_OnTextChanged(editBox)
            self.searchText = editBox:GetText() or ""

            -- Update global search results only (no category filtering)
            ReckoningAchievementFrame_UpdateSearchResults(self)
        end)
    end

    -- Initialize tabs (don't use PanelTemplates for AchievementFrameTabButtonTemplate)
    -- Category list will be loaded in OnShow after config.lua registers achievements

    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or "igCharacterInfoOpen")

    -- Update the micro button state
    if ReckoningAchievementMicroButton_UpdateIcon then
        ReckoningAchievementMicroButton_UpdateIcon()
    end

    -- Hide Admin tab for non-officers/GM before selecting default tab
    ReckoningAchievementFrame_UpdateAdminTabVisibility()
    -- Select Achievements tab by default
    ReckoningAchievementFrame_SelectTab(1)
end

function ReckoningAchievementFrame_OnShow(self)
        -- Keep the addon layout panel anchored to the center of the screen (not to a side)
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    
    -- Refresh category list (config.lua has registered achievements by now)
    self.categoryList = Data:GetCategories()

    -- Select first category if none selected
    if not self.selectedCategoryId then
        self.selectedCategoryId = self.categoryList[1] and self.categoryList[1].id or nil
    end

    -- Update points display
    if self.Header and self.Header.Points then
        self.Header.Points:SetText(tostring(Data:GetTotalPointsEarned()))
    end

    -- Update categories and achievements
    ReckoningAchievementFrame_UpdateCategories(self)
    ReckoningAchievementFrame_UpdateAchievements(self)
    ReckoningAchievementFrame_UpdateSummary(self)

    -- Update Admin tab visibility (officer/GM only) and tab visuals
    ReckoningAchievementFrame_UpdateAdminTabVisibility()
    ReckoningAchievementFrame_SelectTab(1)

    -- Update the micro button state
    if ReckoningAchievementMicroButton_UpdateIcon then
        ReckoningAchievementMicroButton_UpdateIcon()
    end
end

function ReckoningAchievementFrame_OnHide(self)
    GameTooltip:Hide()
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or "igCharacterInfoClose")

    -- Update the micro button state
    if ReckoningAchievementMicroButton_UpdateIcon then
        ReckoningAchievementMicroButton_UpdateIcon()
    end
end

-------------------------------------------------------------------------------
-- Public Refresh API
-------------------------------------------------------------------------------

---Refresh the achievement frame with current data (call after achievements update)
function ReckoningAchievementFrame_Refresh()
    local frame = ReckoningAchievementFrame
    if not frame then return end

    -- Refresh category list
    frame.categoryList = Data:GetCategories()

    -- Update points display
    if frame.Header and frame.Header.Points then
        frame.Header.Points:SetText(tostring(Data:GetTotalPointsEarned()))
    end

    -- Only update visible elements if frame is shown
    if frame:IsShown() then
        ReckoningAchievementFrame_UpdateCategories(frame)
        ReckoningAchievementFrame_UpdateAchievements(frame)
        ReckoningAchievementFrame_UpdateSummary(frame)
    end
end

-- Expose to global namespace for external calls
Reckoning_Achievements.RefreshFrame = ReckoningAchievementFrame_Refresh

-------------------------------------------------------------------------------
-- Tab System
-------------------------------------------------------------------------------

--- Update Admin tab (Tab3) visibility: show only for guild officers/GM, hide otherwise.
--- Call from OnLoad and OnShow so rank changes are reflected.
function ReckoningAchievementFrame_UpdateAdminTabVisibility()
    local frame = ReckoningAchievementFrame
    if not frame then return end

    local tab3 = _G["ReckoningAchievementFrameTab3"]
    if not tab3 then return end

    local priv = Private or Reckoning.Private
    local ticketSync = priv and priv.TicketSyncUtils
    local isAdmin = ticketSync and ticketSync:IsAdmin() == true

    if isAdmin then
        tab3:Show()
    else
        tab3:Hide()
        -- If we're currently showing the Admin content, switch to Achievements tab
        if frame.Admin and frame.Admin:IsShown() then
            ReckoningAchievementFrame_SelectTab(1)
        end
    end
end

function ReckoningAchievementFrame_SelectTab(tabNum)
    local frame = ReckoningAchievementFrame

    -- Update tab button states manually (ReckoningAchievementFrameTabButtonTemplate doesn't use PanelTemplates)
    -- Access textures using _G since they're named regions, not parentKey properties
    local tab1Name = "ReckoningAchievementFrameTab1"
    local tab2Name = "ReckoningAchievementFrameTab2"
    local tab3Name = "ReckoningAchievementFrameTab3"

    local tab1 = _G[tab1Name]
    local tab2 = _G[tab2Name]
    local tab3 = _G[tab3Name]

    local function SetTabSelected(tabName, tabObj, selected)
        if not _G[tabName .. "Left"] then
            return
        end
        if selected then
            _G[tabName .. "Left"]:Hide()
            _G[tabName .. "Middle"]:Hide()
            _G[tabName .. "Right"]:Hide()
            _G[tabName .. "LeftDisabled"]:Show()
            _G[tabName .. "MiddleDisabled"]:Show()
            _G[tabName .. "RightDisabled"]:Show()
        else
            _G[tabName .. "Left"]:Show()
            _G[tabName .. "Middle"]:Show()
            _G[tabName .. "Right"]:Show()
            _G[tabName .. "LeftDisabled"]:Hide()
            _G[tabName .. "MiddleDisabled"]:Hide()
            _G[tabName .. "RightDisabled"]:Hide()
        end

        if tabObj then
            tabObj.isSelected = selected
            if tabObj.text then
                if selected then
                    tabObj.text:SetTextColor(1, 1, 1)
                else
                    tabObj.text:SetTextColor(1, 0.82, 0)
                end
            end
            if selected and tabObj.leftHighlight then
                tabObj.leftHighlight:Hide()
                tabObj.middleHighlight:Hide()
                tabObj.rightHighlight:Hide()
            end
        end
    end

    SetTabSelected(tab1Name, tab1, tabNum == 1)
    SetTabSelected(tab2Name, tab2, tabNum == 2)
    SetTabSelected(tab3Name, tab3, tabNum == 3)
    frame.Achievements:Hide()
    frame.Summary:Hide()
    frame.SearchBox:Hide()
    frame.SearchResults:Hide()
    frame.Guild:Hide()
    frame.Categories:Hide()
    if frame.Admin then
        frame.Admin:Hide()
    end

    -- Hide/Show DDLInsets based on tab
    if frame.Header then
        if frame.Header.LeftDDLInset then
            frame.Header.LeftDDLInset:SetShown(tabNum == 1)
        end
        if frame.Header.RightDDLInset then
            frame.Header.RightDDLInset:SetShown(tabNum == 1)
        end
    end

    -- Hide/Show Filter and Search based on tab
    if frame.FilterDropDown then
        frame.FilterDropDown:SetShown(tabNum == 1)
    end

    -- Change Categories background texture based on tab
    local categoriesBG = _G["ReckoningAchievementFrameCategoriesBG"]
    if categoriesBG then
        if tabNum == 1 then
            -- Achievements tab - use achievement parchment
            categoriesBG:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Parchment")
        else
            -- Guild tab - use guild parchment
            categoriesBG:SetTexture("Interface\\AchievementFrame\\UI-GuildAchievement-Parchment")
        end
    end

    -- Show content for selected tab
    if tabNum == 1 then
        -- Achievements tab - Show categories sidebar and summary
        frame.Categories:Show()
        frame.Summary:Show()
        frame.SearchBox:Show()
    elseif tabNum == 2 then
        -- Guild tab - Select default sub-tab (Events)
        frame.Guild:Show()
        ReckoningGuildFrame_SelectSubTab(frame, "events")
    elseif tabNum == 3 then
        -- Admin tab (left: Tickets/Actions like Guild; right: content)
        if ReckoningAdmin_EnsureUI then
            ReckoningAdmin_EnsureUI(frame)
        end
        if frame.Admin then
            frame.Admin:Show()
            -- Restore last selected sub-tab so switching main tabs doesn't reset view
            local subTab = (frame.Admin.selectedSubTab == "actions" or frame.Admin.selectedSubTab == "log") and frame.Admin.selectedSubTab or "tickets"
            ReckoningAdmin_SelectSubTab(frame, subTab)
        end
    end
end

-------------------------------------------------------------------------------
-- Guild Sub-Tab Selection
-------------------------------------------------------------------------------
function ReckoningGuildFrame_SelectSubTab(frame, subTab)
    if not frame or not frame.Guild then
        return
    end

    local guild = frame.Guild
    local categories = guild.Categories
    if not categories or not categories.Container then
        return
    end

    local container = categories.Container
    local eventsButton = container.EventsButton
    local rosterButton = container.RosterButton

    -- Update button states
    if eventsButton then
        if subTab == "events" then
            eventsButton:LockHighlight()
        else
            eventsButton:UnlockHighlight()
        end
    end

    if rosterButton then
        if subTab == "roster" then
            rosterButton:LockHighlight()
        else
            rosterButton:UnlockHighlight()
        end
    end

    -- Update content panel visibility and background
    local content = guild.Content
    if content then
        -- Darken background for both Roster and Events tabs
        if content.Background then
            if subTab == "roster" or subTab == "events" then
                content.Background:SetVertexColor(0.6, 0.6, 0.6)
            else
                content.Background:SetVertexColor(1, 1, 1)
            end
        end

        -- Show/hide appropriate content panels
        if content.Events then
            if subTab == "events" then
                content.Events:Show()
                ReckoningGuildEvents_Initialize(content.Events)
            else
                content.Events:Hide()
            end
        end

        if content.Roster then
            if subTab == "roster" then
                content.Roster:Show()
                ReckoningGuildRoster_Initialize(content.Roster)
            else
                content.Roster:Hide()
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Guild Events Data (now using real synced data)
-------------------------------------------------------------------------------

-- Cache for current guild events display
local GUILD_EVENTS_CACHE = {}

local function RefreshGuildEventsCache()
    local guildSync = Private.GuildSyncUtils
    if not guildSync then
        GUILD_EVENTS_CACHE = {}
        return
    end

    GUILD_EVENTS_CACHE = guildSync:GetRecentEvents(100)
end

local function ReckoningGuildEventButton_OnLoad(button)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Add tooltip support
    button:SetScript("OnEnter", function(self)
        if self.exactTimestamp then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Earned: " .. self.exactTimestamp, 1, 1, 1)
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

local function ReckoningGuildEventButton_Update(button, index)
    local eventData = GUILD_EVENTS_CACHE[index]
    if not eventData then
        button:Hide()
        return
    end

    -- Get achievement data directly
    local achievement = Data._achievements[eventData.achievementId]
    if not achievement then
        button:Hide()
        return
    end

    -- Store achievement data for click handler and tooltip
    button.achievementId = eventData.achievementId
    button.categoryId = achievement.categoryId

    -- Update button display (similar to achievement buttons)
    if button.icon and button.icon.texture then
        button.icon.texture:SetTexture(achievement.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    end

    if button.label then
        button.label:SetText(achievement.name or "Unknown Achievement")
    end

    if button.description then
        local classColor = CLASS_COLORS[eventData.playerClass] or CLASS_COLORS[eventData.class] or {1, 1, 1}
        -- Format timestamp using GuildSyncUtils if available, otherwise use raw timestamp
        local timestamp = eventData.timestamp
        if type(timestamp) == "number" and Private.GuildSyncUtils then
            timestamp = Private.GuildSyncUtils:FormatTimestamp(timestamp)
        end

        -- Light grey text for "Earned by", class-colored player name, light grey for timestamp
        local playerText = string.format("|cffaaaaaa Earned by |r|cff%02x%02x%02x%s|r|cffaaaaaa - %s|r",
            classColor[1] * 255, classColor[2] * 255, classColor[3] * 255,
            eventData.playerName, timestamp or "Unknown")
        button.description:SetText(playerText)
    end

    if button.points then
        button.points:SetText(achievement.points or 0)
    end

    -- Store exact timestamp for tooltip
    if type(eventData.timestamp) == "number" and Private.GuildSyncUtils then
        button.exactTimestamp = Private.GuildSyncUtils:FormatExactTimestamp(eventData.timestamp)
    else
        button.exactTimestamp = eventData.exactTimestamp
    end

    -- Hide shield/earned indicator
    if button.shield then
        button.shield:Hide()
    end

    button:Show()
end

function ReckoningGuildEvents_Initialize(events)
    if not events or not events.ScrollFrame then
        return
    end

    -- Refresh the cache from GuildSyncUtils
    RefreshGuildEventsCache()

    local scrollFrame = events.ScrollFrame
    local offset = HybridScrollFrame_GetOffset(scrollFrame)
    local buttons = scrollFrame.buttons

    if not buttons then
        return
    end

    local buttonHeight = 64
    local buttonSpacing = -4
    local totalHeight = #GUILD_EVENTS_CACHE * (buttonHeight + math.abs(buttonSpacing))
    HybridScrollFrame_Update(scrollFrame, totalHeight, scrollFrame:GetHeight())

    for i = 1, #buttons do
        local button = buttons[i]
        local index = offset + i
        ReckoningGuildEventButton_Update(button, index)
    end

    -- Show/hide empty state
    local eventsFrame = scrollFrame:GetParent()
    if eventsFrame and eventsFrame.EmptyState then
        if #GUILD_EVENTS_CACHE == 0 then
            eventsFrame.EmptyState:Show()
            scrollFrame:Hide()
        else
            eventsFrame.EmptyState:Hide()
            scrollFrame:Show()
        end
    end
end

-------------------------------------------------------------------------------
-- Guild Sync Button Functionality
-------------------------------------------------------------------------------

local function GetGuildSyncShowLogs()
    local addon = Private and Private.Addon
    if not addon or not addon.GetDatabaseValue then
        return false
    end
    return addon:GetDatabaseValue("settings.guildSync.showLogs", true) == true
end

function ReckoningGuildFrame_InitShowLogsToggle(toggle)
    if not toggle or not toggle.SetChecked then return end
    toggle:SetChecked(GetGuildSyncShowLogs())
end

function ReckoningGuildFrame_ToggleShowLogs(toggle)
    local addon = Private and Private.Addon
    if not addon or not addon.SetDatabaseValue then return end

    local enabled = (toggle and toggle.GetChecked and toggle:GetChecked()) and true or false
    addon:SetDatabaseValue("settings.guildSync.showLogs", enabled)

    if enabled then
        addon:Print("Guild sync logs enabled.")
    else
        addon:Print("Guild sync logs disabled.")
    end
end

function ReckoningGuildFrame_TriggerSync()
    local guildSync = Private.GuildSyncUtils
    if not guildSync then
        print("|cffff0000[Reckoning]|r Guild sync not available")
        return
    end

    if not IsInGuild() then
        print("|cffff0000[Reckoning]|r You must be in a guild to sync")
        return
    end

    local success, message = guildSync:TriggerManualSync()
    if success then
        print("|cff00ff00[Reckoning]|r " .. message)
    else
        print("|cffff0000[Reckoning]|r " .. message)
    end
end

local function ReckoningGuildEventsScrollFrame_OnLoad(scrollFrame)
    local parentEvents = scrollFrame:GetParent()
    scrollFrame.update = function() ReckoningGuildEvents_Initialize(parentEvents) end
    HybridScrollFrame_CreateButtons(scrollFrame, "ReckoningGuildEventButtonTemplate", 0, 0, nil, nil, 0, -4)

    for i, button in ipairs(scrollFrame.buttons) do
        button:SetHeight(64)

        -- Scale down icon for compact view
        if button.icon then
            button.icon:SetSize(48, 48)
        end

        ReckoningGuildEventButton_OnLoad(button)

        -- Set click handler: right-click = Report Bug for this achievement, left-click = jump to achievement
        button:SetScript("OnClick", function(self, mouseButton)
            if not self.achievementId then return end

            if mouseButton == "RightButton" then
                if UIDropDownMenu_Initialize and ToggleDropDownMenu then
                    EnsureBugReportDialog()
                    local dd = EnsureBugReportDropDown()
                    dd.achievementId = self.achievementId
                    ToggleDropDownMenu(1, nil, dd, "cursor", 0, 0)
                end
                return
            end

            -- Left-click: switch to Achievements tab and select this achievement
            ReckoningAchievementFrame_SelectTab(1)
            ReckoningAchievementFrame_SelectAchievement(self.achievementId)
            PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or "igMainMenuOptionCheckBoxOn")
        end)
    end

    -- Set up sync button text
    if parentEvents and parentEvents.Header and parentEvents.Header.SyncButton then
        parentEvents.Header.SyncButton:SetText("Sync")
    end

    -- Initialize show logs toggle state
    if parentEvents and parentEvents.Header and parentEvents.Header.ShowLogsToggle then
        ReckoningGuildFrame_InitShowLogsToggle(parentEvents.Header.ShowLogsToggle)
    end
end

-- Hook to initialize events scrollframe on first show
hooksecurefunc("ReckoningGuildFrame_SelectSubTab", function(frame, subTab)
    if subTab == "events" and frame.Guild and frame.Guild.Content and frame.Guild.Content.Events then
        local events = frame.Guild.Content.Events
        if events.ScrollFrame and not events.ScrollFrame.initialized then
            ReckoningGuildEventsScrollFrame_OnLoad(events.ScrollFrame)
            events.ScrollFrame.initialized = true
            ReckoningGuildEvents_Initialize(events)
        end
    end
end)

-------------------------------------------------------------------------------
-- Guild Roster Data (now using real synced data)
-------------------------------------------------------------------------------
local ROSTER_SORT_STATE = {
    column = "name",
    ascending = true
}

-- Cache for current roster display
local GUILD_ROSTER_CACHE = {}

local function RefreshGuildRosterCache()
    local guildSync = Private.GuildSyncUtils
    if not guildSync then
        GUILD_ROSTER_CACHE = {}
        return
    end

    -- Get roster data with current sort settings
    GUILD_ROSTER_CACHE = guildSync:GetRosterData(ROSTER_SORT_STATE.column, ROSTER_SORT_STATE.ascending)
end

local CLASS_COLORS = {
    ["Warrior"] = {0.78, 0.61, 0.43},
    ["WARRIOR"] = {0.78, 0.61, 0.43},
    ["Paladin"] = {0.96, 0.55, 0.73},
    ["PALADIN"] = {0.96, 0.55, 0.73},
    ["Hunter"] = {0.67, 0.83, 0.45},
    ["HUNTER"] = {0.67, 0.83, 0.45},
    ["Rogue"] = {1, 0.96, 0.41},
    ["ROGUE"] = {1, 0.96, 0.41},
    ["Priest"] = {1, 1, 1},
    ["PRIEST"] = {1, 1, 1},
    ["Death Knight"] = {0.77, 0.12, 0.23},
    ["DEATHKNIGHT"] = {0.77, 0.12, 0.23},
    ["Shaman"] = {0, 0.44, 0.87},
    ["SHAMAN"] = {0, 0.44, 0.87},
    ["Mage"] = {0.41, 0.8, 0.94},
    ["MAGE"] = {0.41, 0.8, 0.94},
    ["Warlock"] = {0.58, 0.51, 0.79},
    ["WARLOCK"] = {0.58, 0.51, 0.79},
    ["Druid"] = {1, 0.49, 0.04},
    ["DRUID"] = {1, 0.49, 0.04},
}

local function ReckoningGuildRosterButton_OnLoad(button)
    button:RegisterForClicks("LeftButtonUp")
    button.Name = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    button.Name:SetPoint("LEFT", 10, 0)
    button.Class = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    button.Class:SetPoint("LEFT", 150, 0)
    button.Points = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    button.Points:SetPoint("LEFT", 250, 0)
    button.Version = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    button.Version:SetPoint("LEFT", 330, 0)
    button.LastSeen = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    button.LastSeen:SetPoint("LEFT", 420, 0)

    -- Alternating background
    if not button.bg then
        button.bg = button:CreateTexture(nil, "BACKGROUND")
        button.bg:SetAllPoints()
        button.bg:SetColorTexture(0, 0, 0, 0.2)
    end
end

local function ReckoningGuildRosterButton_Update(button, index)
    local data = GUILD_ROSTER_CACHE[index]
    if data then
        button.Name:SetText(data.name or "Unknown")

        -- Format class name for display
        local displayClass = data.class or "Unknown"
        if displayClass == displayClass:upper() then
            -- Convert WARRIOR to Warrior
            displayClass = displayClass:sub(1,1) .. displayClass:sub(2):lower()
        end
        button.Class:SetText(displayClass)

        local points = data.totalPoints or 0
        button.Points:SetText(tostring(points))

        button.Version:SetText(data.version or "N/A")

        -- Format lastSeen timestamp
        local lastSeenText = "Unknown"
        local lastSeenColor = {0.5, 0.5, 0.5}

        if data.isOnline then
            lastSeenText = "Online"
            lastSeenColor = {0, 1, 0}
        elseif data.lastSeen then
            if Private.GuildSyncUtils then
                lastSeenText = Private.GuildSyncUtils:FormatTimestamp(data.lastSeen)
            else
                lastSeenText = date("%m/%d/%Y", data.lastSeen)
            end

            -- Color based on how recent
            local elapsed = time() - data.lastSeen
            if elapsed < 3600 then -- Less than 1 hour
                lastSeenColor = {0.7, 0.7, 0.7}
            elseif elapsed < 86400 then -- Less than 1 day
                lastSeenColor = {0.6, 0.6, 0.6}
            else
                lastSeenColor = {0.5, 0.5, 0.5}
            end
        end

        button.LastSeen:SetText(lastSeenText)
        button.LastSeen:SetTextColor(lastSeenColor[1], lastSeenColor[2], lastSeenColor[3])

        -- Apply class color
        local classColor = CLASS_COLORS[data.class] or CLASS_COLORS[displayClass]
        if classColor then
            button.Class:SetTextColor(classColor[1], classColor[2], classColor[3])
        end

        -- Points color (gold-ish)
        button.Points:SetTextColor(1, 0.82, 0)

        -- Alternating row background
        if index % 2 == 0 then
            button.bg:Show()
        else
            button.bg:Hide()
        end

        button:Show()
    else
        button:Hide()
    end
end

function ReckoningGuildRoster_Initialize(roster)
    if not roster or not roster.ScrollFrame then
        return
    end

    -- Refresh the cache from GuildSyncUtils
    RefreshGuildRosterCache()

    local scrollFrame = roster.ScrollFrame
    local offset = HybridScrollFrame_GetOffset(scrollFrame)
    local buttons = scrollFrame.buttons

    if not buttons then
        return
    end

    local totalHeight = #GUILD_ROSTER_CACHE * 22
    HybridScrollFrame_Update(scrollFrame, totalHeight, scrollFrame:GetHeight())

    for i = 1, #buttons do
        local button = buttons[i]
        local index = offset + i
        ReckoningGuildRosterButton_Update(button, index)
    end

    -- Show/hide empty state
    if roster.EmptyState then
        if #GUILD_ROSTER_CACHE == 0 then
            roster.EmptyState:Show()
            scrollFrame:Hide()
            roster.Header:Hide()
        else
            roster.EmptyState:Hide()
            scrollFrame:Show()
            roster.Header:Show()
        end
    end
end

local function ReckoningGuildRosterScrollFrame_OnLoad(scrollFrame)
    local parentRoster = scrollFrame:GetParent()
    scrollFrame.update = function() ReckoningGuildRoster_Initialize(parentRoster) end
    HybridScrollFrame_CreateButtons(scrollFrame, "ReckoningGuildRosterButtonTemplate", 0, 0, nil, nil, 0, -2)

    for i, button in ipairs(scrollFrame.buttons) do
        button:SetHeight(20)
        ReckoningGuildRosterButton_OnLoad(button)
    end
end

-- Hook to initialize roster scrollframe on first show
hooksecurefunc("ReckoningGuildFrame_SelectSubTab", function(frame, subTab)
    if subTab == "roster" and frame.Guild and frame.Guild.Content and frame.Guild.Content.Roster then
        local roster = frame.Guild.Content.Roster
        if roster.ScrollFrame and not roster.ScrollFrame.initialized then
            ReckoningGuildRosterScrollFrame_OnLoad(roster.ScrollFrame)
            roster.ScrollFrame.initialized = true
            ReckoningGuildRoster_Initialize(roster)
        end
    end
end)

-------------------------------------------------------------------------------
-- Guild Roster Sorting
-------------------------------------------------------------------------------
function ReckoningGuildRoster_SortBy(roster, column)
    if not roster then
        return
    end

    -- Map "status" to "lastSeen" for GuildSyncUtils
    local sortColumn = column
    if column == "status" then
        sortColumn = "lastSeen"
    end

    -- Toggle sort direction if clicking same column
    if ROSTER_SORT_STATE.column == sortColumn then
        ROSTER_SORT_STATE.ascending = not ROSTER_SORT_STATE.ascending
    else
        ROSTER_SORT_STATE.column = sortColumn
        ROSTER_SORT_STATE.ascending = true
    end

    -- Refresh the roster cache with new sort settings
    RefreshGuildRosterCache()

    -- Reset scroll position and update display
    if roster.ScrollFrame then
        local scrollFrame = roster.ScrollFrame
        HybridScrollFrame_SetOffset(scrollFrame, 0)
        scrollFrame:SetVerticalScroll(0)

        -- Force immediate button updates
        local offset = 0
        local buttons = scrollFrame.buttons
        if buttons then
            for i = 1, #buttons do
                local button = buttons[i]
                local index = offset + i
                ReckoningGuildRosterButton_Update(button, index)
            end
        end

        local totalHeight = #GUILD_ROSTER_CACHE * 22
        HybridScrollFrame_Update(scrollFrame, totalHeight, scrollFrame:GetHeight())
    end
end

-------------------------------------------------------------------------------
-- Guild Data Refresh Callback
-------------------------------------------------------------------------------
-- Register to refresh UI when guild data is updated
local function OnGuildDataUpdated()
    -- Refresh events tab if visible
    local frame = ReckoningAchievementFrame
    if frame and frame.Guild and frame.Guild.Content then
        local events = frame.Guild.Content.Events
        if events and events:IsVisible() and events.ScrollFrame then
            ReckoningGuildEvents_Initialize(events)
        end

        local roster = frame.Guild.Content.Roster
        if roster and roster:IsVisible() and roster.ScrollFrame then
            ReckoningGuildRoster_Initialize(roster)
        end
    end
end

-- Hook into callback system (delayed to ensure Private is available)
C_Timer.After(1, function()
    -- Re-fetch Private in case it wasn't available at file load time
    Private = Private or Reckoning.Private
    if Private and Private.CallbackUtils then
        Private.CallbackUtils:AddCallback("GuildDataUpdated", OnGuildDataUpdated)
    end
end)

-------------------------------------------------------------------------------
-- Filter Dropdown
-------------------------------------------------------------------------------

function ReckoningAchievementFilterDropDown_Initialize(dropdown, frame)
    local info = UIDropDownMenu_CreateInfo()

    -- All
    info.text = ACHIEVEMENTFRAME_FILTER_ALL
    info.value = ACHIEVEMENT_FILTER_ALL
    info.func = function()
        frame.currentFilter = ACHIEVEMENT_FILTER_ALL
        UIDropDownMenu_SetText(dropdown, ACHIEVEMENTFRAME_FILTER_ALL)
        ReckoningAchievementFrame_UpdateAchievements(frame)
    end
    info.checked = (frame.currentFilter == ACHIEVEMENT_FILTER_ALL)
    UIDropDownMenu_AddButton(info)

    -- Completed
    info.text = ACHIEVEMENTFRAME_FILTER_COMPLETED
    info.value = ACHIEVEMENT_FILTER_COMPLETE
    info.func = function()
        frame.currentFilter = ACHIEVEMENT_FILTER_COMPLETE
        UIDropDownMenu_SetText(dropdown, ACHIEVEMENTFRAME_FILTER_COMPLETED)
        ReckoningAchievementFrame_UpdateAchievements(frame)
    end
    info.checked = (frame.currentFilter == ACHIEVEMENT_FILTER_COMPLETE)
    UIDropDownMenu_AddButton(info)

    -- Incomplete
    info.text = ACHIEVEMENTFRAME_FILTER_INCOMPLETE
    info.value = ACHIEVEMENT_FILTER_INCOMPLETE
    info.func = function()
        frame.currentFilter = ACHIEVEMENT_FILTER_INCOMPLETE
        UIDropDownMenu_SetText(dropdown, ACHIEVEMENTFRAME_FILTER_INCOMPLETE)
        ReckoningAchievementFrame_UpdateAchievements(frame)
    end
    info.checked = (frame.currentFilter == ACHIEVEMENT_FILTER_INCOMPLETE)
    UIDropDownMenu_AddButton(info)
end

-------------------------------------------------------------------------------
-- Category Button Handlers
-------------------------------------------------------------------------------

function ReckoningAchievementCategoryButton_OnLoad(button)
    button:RegisterForClicks("LeftButtonUp")
end

function ReckoningAchievementCategoryButton_OnClick(button)
    local frame = GetAchievementFrame()
    if not frame or not button.categoryId then
        return
    end

    local element = button.element
    local categories = frame.categoryList
    local id = button.categoryId

    -- Handle expand/collapse for parent categories (parent = true means has children)
    if element and element.parent == true then
        -- This is a parent category with children
        if button.isSelected and element.collapsed == false then
            -- Already selected and expanded, so collapse
            element.collapsed = true
            for _, cat in ipairs(categories) do
                if cat.parent == id then
                    cat.hidden = true
                end
            end
        else
            -- Expand this parent, collapse all others
            for _, cat in ipairs(categories) do
                if cat.parent == id then
                    -- Show children of this parent
                    cat.hidden = false
                elseif cat.parent == true then
                    -- Collapse other parent categories
                    cat.collapsed = true
                elseif type(cat.parent) == "number" and cat.parent ~= id then
                    -- Hide children of other parents
                    cat.hidden = true
                end
            end
            element.collapsed = false
        end
    end

    -- Mark selection
    local scrollFrame = frame.categoriesContainer
    if scrollFrame and scrollFrame.buttons then
        for _, categoryButton in ipairs(scrollFrame.buttons) do
            categoryButton.isSelected = nil
        end
    end
    button.isSelected = true

    frame.selectedCategoryId = button.categoryId
    frame.selectedAchievementId = nil
    ReckoningAchievementFrame_UpdateCategories(frame)
    ReckoningAchievementFrame_UpdateAchievements(frame)
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or "igCharacterInfoTab")
end

-------------------------------------------------------------------------------
-- Achievement Button Handlers
-------------------------------------------------------------------------------

function ReckoningAchievementButton_OnLoad(button)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.collapsed = true
    -- Set backdrop color to transparent to avoid grey overlay
    if button.SetBackdropColor then
        button:SetBackdropColor(0, 0, 0, 0)
    end
end

local BUG_REPORT_DROPDOWN
local BUG_REPORT_DIALOG

EnsureBugReportDropDown = function()
    if BUG_REPORT_DROPDOWN then
        return BUG_REPORT_DROPDOWN
    end

    BUG_REPORT_DROPDOWN = CreateFrame("Frame", "ReckoningBugReportDropDown", UIParent, "UIDropDownMenuTemplate")

    UIDropDownMenu_Initialize(BUG_REPORT_DROPDOWN, function(self, level)
        if level ~= 1 then return end
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Report Bug"
        info.notCheckable = true
        info.func = function()
            local d = BUG_REPORT_DIALOG
            if d and d.ShowForAchievement then
                d:ShowForAchievement(self.achievementId)
            end
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(info, level)

        local priv = Private or Reckoning.Private
        local correctionSync = priv and priv.CorrectionSyncUtils
        if correctionSync and correctionSync:IsAdmin() then
            info = UIDropDownMenu_CreateInfo()
            info.text = "Manage achievement"
            info.notCheckable = true
            info.func = function()
                if ReckoningAchievementManage_Show then
                    ReckoningAchievementManage_Show(self.achievementId)
                end
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    return BUG_REPORT_DROPDOWN
end

EnsureBugReportDialog = function()
    if BUG_REPORT_DIALOG then
        return BUG_REPORT_DIALOG
    end

    local f = CreateFrame("Frame", "ReckoningBugReportDialog", UIParent, "BackdropTemplate")
    f:SetSize(420, 170)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Report Achievement Bug")

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -6)
    subtitle:SetText("Describe the issue (max 140 characters).")

    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetSize(360, 24)
    edit:SetPoint("TOP", subtitle, "BOTTOM", 0, -14)
    edit:SetMaxLetters(140)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    edit:SetScript("OnEnterPressed", function() f.Submit:Click() end)
    f.EditBox = edit

    local counter = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    counter:SetPoint("TOPRIGHT", edit, "BOTTOMRIGHT", 0, -6)
    counter:SetText("0/140")
    f.Counter = counter

    edit:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if f.Counter then
            f.Counter:SetText(string.format("%d/140", #text))
        end
    end)

    local submit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    submit:SetSize(120, 24)
    submit:SetPoint("BOTTOMRIGHT", -18, 16)
    submit:SetText("Submit")
    f.Submit = submit

    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(120, 24)
    cancel:SetPoint("RIGHT", submit, "LEFT", -10, 0)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() f:Hide() end)

    submit:SetScript("OnClick", function()
        local priv = Private or Reckoning.Private
        local ticketSync = priv and priv.TicketSyncUtils
        local addon = priv and priv.Addon

        if not ticketSync or not ticketSync.CreateTicket or not ticketSync.BroadcastTicketCreate then
            if addon and addon.Print then
                addon:Print("Ticket system not available.")
            end
            f:Hide()
            return
        end

        if type(IsInGuild) == "function" and not IsInGuild() then
            if addon and addon.Print then
                addon:Print("You must be in a guild to report tickets.")
            end
            f:Hide()
            return
        end

        local reason = (f.EditBox and f.EditBox:GetText()) or ""
        if reason == "" then
            if addon and addon.Print then
                addon:Print("Please enter a short reason before submitting.")
            end
            return
        end

        local ticket = ticketSync:CreateTicket(f.achievementId, reason)
        if ticket then
            ticketSync:BroadcastTicketCreate(ticket)
            if addon and addon.Print then
                addon:Print(string.format("Ticket submitted (%s).", tostring(ticket.id)))
            end
            -- Refresh Admin tab so officers see their own ticket when they open it
            local frame = ReckoningAchievementFrame
            if frame and ReckoningAdminTickets_Refresh then
                ReckoningAdminTickets_Refresh(frame)
            end
        end

        f:Hide()
    end)

    function f:ShowForAchievement(achievementId)
        self.achievementId = achievementId
        if self.EditBox then
            self.EditBox:SetText("")
            self.EditBox:SetFocus()
        end
        if self.Counter then
            self.Counter:SetText("0/140")
        end
        self:Show()
    end

    f:Hide()
    BUG_REPORT_DIALOG = f
    return BUG_REPORT_DIALOG
end

-------------------------------------------------------------------------------
-- Manage Achievement dialog (officer/GM: invalidate / revalidate)
-------------------------------------------------------------------------------
local MANAGE_ACHIEVEMENT_DIALOG

-- Parse "From date" input: epoch number, or YYYY-MM-DD, or YYYY-MM-DD HH:MM. Returns Unix timestamp or nil (use time()).
function ReckoningAchievementManage_ParseFromDate(text)
    if not text or type(text) ~= "string" then return nil end
    text = text:match("^%s*(.-)%s*$") or text
    if text == "" then return nil end
    local num = tonumber(text)
    if num and num > 0 then return num end
    local y, m, d = text:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if y and m and d then
        local h, min = text:match(" (%d%d):(%d%d)$")
        h, min = tonumber(h) or 0, tonumber(min) or 0
        local t = { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = h, min = min, sec = 0 }
        local ok, ts = pcall(function() return time(t) end)
        if ok and ts then return ts end
    end
    return nil
end

-- Pending data for the confirm popup (Blizzard's StaticPopup may not pass data to OnAccept on all clients)
local RECKONING_MANAGE_PENDING_DATA = nil

-- Confirmation popup for Manage actions (uses StaticPopup when available)
function ReckoningAchievementManage_ShowConfirm(achievementId, actionType, opts, confirmText)
    achievementId = tonumber(achievementId)
    if not achievementId then return end
    confirmText = confirmText or "This action will be broadcast to the guild. Confirm?"
    print(string.format("[Reckoning:Manage] ShowConfirm called achievementId=%s actionType=%s", tostring(achievementId), tostring(actionType)))

    local function doActionFromData(data)
        if not data or not data.achievementId then
            print("[Reckoning:Manage] OnAccept: no data or achievementId")
            return
        end
        print(string.format("[Reckoning:Manage] OnAccept calling DoAction achievementId=%s", tostring(data.achievementId)))
        if ReckoningAchievementManage_DoAction then
            ReckoningAchievementManage_DoAction(data.achievementId, data.actionType, data.opts or {})
        else
            print("[Reckoning:Manage] OnAccept ReckoningAchievementManage_DoAction is nil")
        end
    end

    if StaticPopupDialogs and StaticPopup_Show then
        if not StaticPopupDialogs["RECKONING_MANAGE_CONFIRM"] then
            StaticPopupDialogs["RECKONING_MANAGE_CONFIRM"] = {
                text = "%s",
                button1 = "Confirm",
                button2 = "Cancel",
                timeout = 0,
                whileDead = 1,
                hideOnEscape = 1,
                preferredIndex = 3,
                OnAccept = function(self)
                    print("[Reckoning:Manage] StaticPopup OnAccept fired")
                    local data = (self and self.data) or RECKONING_MANAGE_PENDING_DATA
                    RECKONING_MANAGE_PENDING_DATA = nil
                    doActionFromData(data)
                end,
            }
        end
        RECKONING_MANAGE_PENDING_DATA = {
            achievementId = achievementId,
            actionType = actionType,
            opts = opts or {},
        }
        print("[Reckoning:Manage] StaticPopup_Show with pending data stored")
        StaticPopup_Show("RECKONING_MANAGE_CONFIRM", confirmText, nil, RECKONING_MANAGE_PENDING_DATA)
        return
    end

    -- Fallback: run immediately with no popup (e.g. older clients)
    print("[Reckoning:Manage] ShowConfirm fallback (no StaticPopup), calling DoAction directly")
    if ReckoningAchievementManage_DoAction then
        ReckoningAchievementManage_DoAction(achievementId, actionType, opts)
    end
end

function ReckoningAchievementManage_Show(achievementId)
    achievementId = tonumber(achievementId)
    if not achievementId then return end
    local priv = Private or Reckoning.Private
    local correctionSync = priv and priv.CorrectionSyncUtils
    if not correctionSync or not correctionSync:IsAdmin() then return end

    if not MANAGE_ACHIEVEMENT_DIALOG then
        local f = CreateFrame("Frame", "ReckoningManageAchievementDialog", UIParent, "BackdropTemplate")
        f:SetSize(400, 420)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 }
        })
        f.pendingActions = {}

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Action builder")
        f.Title = title

        local y = -42
        local function CreateListDropdown(parent, options, defaultValue, width, anchorX, anchorY, onSelectCallback)
            width = width or 80
            local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
            dd:SetPoint("TOPLEFT", anchorX or 16, anchorY or 0)
            UIDropDownMenu_SetWidth(dd, width)
            dd.selectedValue = defaultValue or (options[1] and options[1].value)
            UIDropDownMenu_Initialize(dd, function(self, level)
                if level ~= 1 then return end
                for _, opt in ipairs(options) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = opt.text
                    info.func = function(_, arg1)
                        self.selectedValue = arg1
                        UIDropDownMenu_SetText(self, opt.text)
                        if onSelectCallback then onSelectCallback() end
                    end
                    info.arg1 = opt.value
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            dd.SetSelectedValue = function(self, val)
                self.selectedValue = val
                for _, opt in ipairs(options) do
                    if opt.value == val then UIDropDownMenu_SetText(self, opt.text) break end
                end
            end
            return dd
        end
        local function BuilderOnSelect() if f.BuildPreviewSentence then f.BuildPreviewSentence(f) end end

        local typeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        typeLabel:SetPoint("TOPLEFT", 16, y)
        typeLabel:SetText("What should this action do?")
        y = y - 18
        local typeOpts = {
            { value = "full_invalidate", text = "Invalidate (all) – no one gets points" },
            { value = "invalidate_from_date", text = "Invalidate from a date onward" },
            { value = "revalidate", text = "Revalidate – require minimum addon version" },
            { value = "reset", text = "Don't count completions that match a condition" },
        }
        f.BuilderTypeDD = CreateListDropdown(f, typeOpts, "full_invalidate", 320, 16, y)
        y = y - 26

        -- Rule preview: sentence that updates from current selections
        local previewLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        previewLabel:SetPoint("TOPLEFT", 16, y)
        previewLabel:SetWidth(368)
        previewLabel:SetWordWrap(true)
        previewLabel:SetNonSpaceWrap(false)
        f.BuilderPreview = previewLabel
        y = y - 32

        local function BuildPreviewSentence(dialog)
            if not dialog.BuilderPreview then return end
            local t = dialog.BuilderTypeDD and dialog.BuilderTypeDD.selectedValue or "full_invalidate"
            local s
            if t == "full_invalidate" then
                s = "This achievement will not count for anyone (no points)."
            elseif t == "invalidate_from_date" then
                local Y = dialog.BuilderYearDD and dialog.BuilderYearDD.selectedValue or 2026
                local M = dialog.BuilderMonthDD and dialog.BuilderMonthDD.selectedValue or 1
                local D = dialog.BuilderDayDD and dialog.BuilderDayDD.selectedValue or 1
                s = string.format("Completions from %d-%02d-%02d onward will not count. Earlier completions keep their points.", Y, M, D)
            elseif t == "revalidate" then
                local verStr = (dialog.BuilderVersionEditBox and dialog.BuilderVersionEditBox:GetText() and dialog.BuilderVersionEditBox:GetText():match("^%s*(.-)%s*$")) or "1.0.0"
                local maj, mn, patch = verStr:match("^(%d+)%.(%d+)%.(%d+)$") or verStr:match("^(%d+)%.(%d+)$")
                maj = tonumber(maj) or 1
                mn = tonumber(mn) or 0
                patch = tonumber(patch) or 0
                s = string.format("Only completions done with addon version at least %d.%d.%d will count.", maj, mn, patch)
            elseif t == "reset" then
                local Y = dialog.BuilderYearDD and dialog.BuilderYearDD.selectedValue or 2026
                local M = dialog.BuilderMonthDD and dialog.BuilderMonthDD.selectedValue or 1
                local D = dialog.BuilderDayDD and dialog.BuilderDayDD.selectedValue or 1
                local verStr = (dialog.BuilderVersionEditBox and dialog.BuilderVersionEditBox:GetText() and dialog.BuilderVersionEditBox:GetText():match("^%s*(.-)%s*$")) or "0.0.0"
                local maj, mn, patch = verStr:match("^(%d+)%.(%d+)%.(%d+)$") or verStr:match("^(%d+)%.(%d+)$")
                maj = tonumber(maj) or 0
                mn = tonumber(mn) or 0
                patch = tonumber(patch) or 0
                local mode = (dialog.BuilderModeDD and dialog.BuilderModeDD.selectedValue) or "points"
                local datePart = string.format("completed before %d-%02d-%02d", Y, M, D)
                local verPart = string.format("addon version below %d.%d.%d", maj, mn, patch)
                local cond = datePart .. " or " .. verPart
                local effect = (mode == "uncomplete") and "will not count and be treated as not completed" or "will not count for points"
                s = "Completions that were " .. cond .. " " .. effect .. "."
            else
                s = ""
            end
            dialog.BuilderPreview:SetText("|cffa0a0a0" .. (s or "") .. "|r")
        end
        f.BuildPreviewSentence = BuildPreviewSentence

        local function UpdateBuilderVisibility(dialog)
            local t = dialog.BuilderTypeDD and dialog.BuilderTypeDD.selectedValue or "full_invalidate"
            local showFromDate = (t == "invalidate_from_date" or t == "reset")
            local showVersion = (t == "revalidate" or t == "reset")
            local showMode = (t == "reset")
            if dialog.BuilderFromDateLabel then dialog.BuilderFromDateLabel:SetShown(showFromDate) end
            if dialog.BuilderYearDD then dialog.BuilderYearDD:SetShown(showFromDate) end
            if dialog.BuilderMonthDD then dialog.BuilderMonthDD:SetShown(showFromDate) end
            if dialog.BuilderDayDD then dialog.BuilderDayDD:SetShown(showFromDate) end
            if dialog.BuilderVersionLabel then dialog.BuilderVersionLabel:SetShown(showVersion) end
            if dialog.BuilderVersionEditBox then dialog.BuilderVersionEditBox:SetShown(showVersion) end
            if dialog.BuilderModeLabel then dialog.BuilderModeLabel:SetShown(showMode) end
            if dialog.BuilderModeDD then dialog.BuilderModeDD:SetShown(showMode) end
            if dialog.BuildPreviewSentence then dialog.BuildPreviewSentence(dialog) end
        end
        f.UpdateBuilderVisibility = UpdateBuilderVisibility
        UIDropDownMenu_Initialize(f.BuilderTypeDD, function(self, level)
            if level ~= 1 then return end
            for _, opt in ipairs(typeOpts) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.text
                info.func = function(_, arg1)
                    self.selectedValue = arg1
                    UIDropDownMenu_SetText(self, opt.text)
                    if f.UpdateBuilderVisibility then f.UpdateBuilderVisibility(f) end
                end
                info.arg1 = opt.value
                UIDropDownMenu_AddButton(info, level)
            end
        end)

        y = y - 4
        -- Inline sentence labels so the form reads as a rule
        local fromDateLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fromDateLabel:SetPoint("TOPLEFT", 16, y)
        fromDateLabel:SetText("From this date (Y/M/D):")
        f.BuilderFromDateLabel = fromDateLabel
        y = y - 18
        local yearOpts, monthOpts, dayOpts = {}, {}, {}
        for yr = 2025, 2031 do yearOpts[#yearOpts + 1] = { value = yr, text = tostring(yr) } end
        for m = 1, 12 do monthOpts[#monthOpts + 1] = { value = m, text = tostring(m) } end
        for d = 1, 31 do dayOpts[#dayOpts + 1] = { value = d, text = tostring(d) } end
        local nowT = (type(date) == "function") and date("*t") or nil
        local defY, defM, defD = 2026, 1, 1
        if nowT and nowT.year then defY = math.max(2025, math.min(2031, nowT.year)) defM = nowT.month or 1 defD = nowT.day or 1 end
        f.BuilderYearDD = CreateListDropdown(f, yearOpts, defY, 58, 16, y, BuilderOnSelect)
        f.BuilderMonthDD = CreateListDropdown(f, monthOpts, defM, 45, 80, y, BuilderOnSelect)
        f.BuilderDayDD = CreateListDropdown(f, dayOpts, defD, 45, 130, y, BuilderOnSelect)
        f.BuilderFromDateRow = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.BuilderFromDateRow:SetPoint("TOPLEFT", 16, y)
        y = y - 26

        local minVerLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        minVerLabel:SetPoint("TOPLEFT", 16, y)
        minVerLabel:SetText("Version (type X.Y.Z, e.g. 1.2.3):")
        f.BuilderVersionLabel = minVerLabel
        y = y - 18
        local versionEdit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        versionEdit:SetPoint("TOPLEFT", 16, y)
        versionEdit:SetSize(120, 20)
        versionEdit:SetAutoFocus(false)
        versionEdit:SetMaxLetters(32)
        versionEdit:SetScript("OnTextChanged", function() BuilderOnSelect() end)
        versionEdit:SetScript("OnEscapePressed", function() versionEdit:ClearFocus() end)
        f.BuilderVersionEditBox = versionEdit
        f.BuilderVersionRow = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.BuilderVersionRow:SetPoint("TOPLEFT", 16, y)
        y = y - 26

        local modeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        modeLabel:SetPoint("TOPLEFT", 16, y)
        modeLabel:SetText("Effect for matching completions:")
        f.BuilderModeLabel = modeLabel
        y = y - 18
        f.BuilderModeDD = CreateListDropdown(f, { { value = "points", text = "Points only – don't count" }, { value = "uncomplete", text = "Treat as not completed (virtual)" } }, "points", 200, 16, y, BuilderOnSelect)
        f.BuilderModeRow = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.BuilderModeRow:SetPoint("TOPLEFT", 16, y)
        y = y - 28

        local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        addBtn:SetSize(120, 24)
        addBtn:SetPoint("TOPLEFT", 16, y)
        addBtn:SetText("Add action")
        addBtn:SetScript("OnClick", function()
            local aid = f.achievementId
            if not aid then return end
            local t = f.BuilderTypeDD and f.BuilderTypeDD.selectedValue or "full_invalidate"
            local opts = {}
            if t == "invalidate_from_date" then
                local Y = f.BuilderYearDD and f.BuilderYearDD.selectedValue or 2026
                local M = f.BuilderMonthDD and f.BuilderMonthDD.selectedValue or 1
                local D = f.BuilderDayDD and f.BuilderDayDD.selectedValue or 1
                local ok, ts = pcall(function() return time({ year = Y, month = M, day = D, hour = 12, min = 0, sec = 0 }) end)
                opts.fromDate = (ok and ts and ts > 0) and ts or time()
            elseif t == "revalidate" then
                local verText = (f.BuilderVersionEditBox and f.BuilderVersionEditBox:GetText() and f.BuilderVersionEditBox:GetText():match("^%s*(.-)%s*$")) or "1.0.0"
                local maj, mn, patch = verText:match("^(%d+)%.(%d+)%.(%d+)$") or verText:match("^(%d+)%.(%d+)$")
                opts.addonVersion = string.format("%d.%d.%d", tonumber(maj) or 1, tonumber(mn) or 0, tonumber(patch) or 0)
                opts.effectiveAt = time()
            elseif t == "reset" then
                local Y = f.BuilderYearDD and f.BuilderYearDD.selectedValue or 2026
                local M = f.BuilderMonthDD and f.BuilderMonthDD.selectedValue or 1
                local D = f.BuilderDayDD and f.BuilderDayDD.selectedValue or 1
                local ok, ts = pcall(function() return time({ year = Y, month = M, day = D, hour = 0, min = 0, sec = 0 }) end)
                if ok and ts and ts > 0 then opts.beforeDate = ts end
                local verText = (f.BuilderVersionEditBox and f.BuilderVersionEditBox:GetText() and f.BuilderVersionEditBox:GetText():match("^%s*(.-)%s*$")) or ""
                local maj, mn, patch = verText:match("^(%d+)%.(%d+)%.(%d+)$") or verText:match("^(%d+)%.(%d+)$")
                if maj or mn or patch then
                    opts.beforeVersion = string.format("%d.%d.%d", tonumber(maj) or 0, tonumber(mn) or 0, tonumber(patch) or 0)
                end
                opts.mode = (f.BuilderModeDD and f.BuilderModeDD.selectedValue) or "points"
            end
            f.pendingActions[#f.pendingActions + 1] = { type = t, opts = opts }
            ReckoningAchievementManage_RefreshPendingList(f)
        end)
        y = y - 32

        local listLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        listLabel:SetPoint("TOPLEFT", 16, y)
        listLabel:SetText("Queued actions:")
        y = y - 18
        local listFrame = CreateFrame("Frame", nil, f)
        listFrame:SetPoint("TOPLEFT", 16, y)
        listFrame:SetPoint("BOTTOM", 0, 52)
        listFrame:SetWidth(368)
        f.PendingListFrame = listFrame

        local applyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        applyBtn:SetSize(100, 24)
        applyBtn:SetPoint("BOTTOMRIGHT", -18, 16)
        applyBtn:SetText("Apply")
        applyBtn:SetScript("OnClick", function()
            local aid = f.achievementId
            if not aid or #f.pendingActions == 0 then f:Hide() return end
            local priv = Private or Reckoning.Private
            local correctionSync = priv and priv.CorrectionSyncUtils
            if not correctionSync or not correctionSync.CreateCorrection or not correctionSync.BroadcastCorrection then
                f:Hide()
                return
            end
            for _, act in ipairs(f.pendingActions) do
                local c = correctionSync:CreateCorrection(aid, act.type, act.opts)
                if c then correctionSync:BroadcastCorrection(c) end
            end
            f.pendingActions = {}
            ReckoningAchievementManage_RefreshPendingList(f)
            f:Hide()
            local frame = ReckoningAchievementFrame
            if frame and ReckoningAdminActions_Refresh then ReckoningAdminActions_Refresh(frame) end
            if frame and ReckoningAdminLog_Refresh then ReckoningAdminLog_Refresh(frame) end
            if ReckoningAchievementFrame_SelectTab then ReckoningAchievementFrame_SelectTab(3) end
            if ReckoningAdmin_SelectSubTab and frame and frame.Admin then ReckoningAdmin_SelectSubTab(frame, "actions") end
        end)
        f.ApplyBtn = applyBtn

        local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancelBtn:SetSize(100, 24)
        cancelBtn:SetPoint("RIGHT", applyBtn, "LEFT", -8, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function()
            f.pendingActions = {}
            f:Hide()
        end)

        MANAGE_ACHIEVEMENT_DIALOG = f
    end

    function ReckoningAchievementManage_RefreshPendingList(f)
        if not f or not f.PendingListFrame then return end
        local listFrame = f.PendingListFrame
        for i = 1, 30 do
            local r = listFrame["row" .. i]
            if r then r:Hide() end
        end
        local y = 0
        for i, act in ipairs(f.pendingActions or {}) do
            local row = listFrame["row" .. i]
            if not row then
                row = CreateFrame("Frame", nil, listFrame)
                listFrame["row" .. i] = row
                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.label:SetPoint("LEFT", 0, 0)
                row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.remove:SetSize(50, 18)
                row.remove:SetPoint("RIGHT", 0, 0)
                row.remove:SetText("Remove")
            end
            row:SetPoint("TOPLEFT", 0, y)
            row:SetSize(368, 20)
            local typeName = (act.type == "full_invalidate" and "Invalidate (all)") or (act.type == "invalidate_from_date" and "Invalid from date") or (act.type == "revalidate" and "Revalidate") or (act.type == "reset" and "Reset") or act.type
            row.label:SetText(typeName)
            row.remove.idx = i
            row.remove:SetScript("OnClick", function(self)
                table.remove(f.pendingActions, self.idx)
                ReckoningAchievementManage_RefreshPendingList(f)
            end)
            row:Show()
            y = y - 22
        end
        if f.ApplyBtn then f.ApplyBtn:SetEnabled(#(f.pendingActions or {}) > 0) end
    end

    local f = MANAGE_ACHIEVEMENT_DIALOG
    f.achievementId = achievementId
    f.pendingActions = {}
    local achievement = Data and Data._achievements and Data._achievements[achievementId]
    local name = achievement and achievement.name or ("Achievement #" .. tostring(achievementId))
    if f.Title then f.Title:SetText("Manage: " .. name) end
    local nowT = (type(date) == "function") and date("*t") or nil
    if f.BuilderYearDD and f.BuilderMonthDD and f.BuilderDayDD then
        local yr = 2026
        local mo, da = 1, 1
        if nowT and nowT.year then yr = math.max(2025, math.min(2031, nowT.year)) mo = nowT.month or 1 da = nowT.day or 1 end
        f.BuilderYearDD:SetSelectedValue(yr)
        f.BuilderMonthDD:SetSelectedValue(mo)
        f.BuilderDayDD:SetSelectedValue(da)
    end
    local verStr = (Private and Private.constants and Private.constants.ADDON_VERSION) or "1.0.0"
    if f.BuilderVersionEditBox then
        f.BuilderVersionEditBox:SetText(verStr)
    end
    ReckoningAchievementManage_RefreshPendingList(f)
    if f.UpdateBuilderVisibility then f.UpdateBuilderVisibility(f) end
    f:Show()
end

function ReckoningAchievementManage_DoAction(achievementId, actionType, opts)
    print(string.format("[Reckoning:Manage] DoAction called achievementId=%s actionType=%s", tostring(achievementId), tostring(actionType)))
    local priv = Private or Reckoning.Private
    local correctionSync = priv and priv.CorrectionSyncUtils
    local addon = priv and priv.Addon
    if not correctionSync or not correctionSync.CreateCorrection or not correctionSync.BroadcastCorrection then
        print("[Reckoning:Manage] DoAction early return: correction system not available")
        if addon and addon.Print then addon:Print("Correction system not available.") end
        return
    end
    opts = opts or {}
    if actionType == "invalidate_from_date" and not opts.fromDate then
        opts.fromDate = time()
    end
    if actionType == "revalidate" then
        opts.addonVersion = (priv and priv.constants and priv.constants.ADDON_VERSION) or "preview"
        opts.effectiveAt = time()
    end
    local c = correctionSync:CreateCorrection(achievementId, actionType, opts)
    if not c then
        print("[Reckoning:Manage] DoAction CreateCorrection returned nil")
        return
    end
    print(string.format("[Reckoning:Manage] DoAction correction created id=%s broadcasting...", tostring(c.id)))
    correctionSync:BroadcastCorrection(c)
    if addon and addon.Print then
        addon:Print("Your action will be broadcast to the guild.")
    end
    local frame = ReckoningAchievementFrame
    if not frame then
        print("[Reckoning:Manage] DoAction no ReckoningAchievementFrame ref")
        return
    end
    print("[Reckoning:Manage] DoAction switching to Admin tab (3)...")
    if ReckoningAchievementFrame_SelectTab then
        ReckoningAchievementFrame_SelectTab(3)
    end
    print("[Reckoning:Manage] DoAction SelectSubTab actions...")
    if ReckoningAdmin_SelectSubTab then
        ReckoningAdmin_SelectSubTab(frame, "actions")
    end
    print("[Reckoning:Manage] DoAction calling Actions_Refresh and Log_Refresh...")
    if ReckoningAdminActions_Refresh then
        ReckoningAdminActions_Refresh(frame)
    end
    if ReckoningAdminLog_Refresh then
        ReckoningAdminLog_Refresh(frame)
    end
    print("[Reckoning:Manage] DoAction done")
end

function ReckoningAchievementButton_OnClick(button, mouseButton)
    local frame = GetAchievementFrame()
    if not frame or not button.achievementId then
        return
    end

    if mouseButton == "RightButton" then
        if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then
            return
        end
        EnsureBugReportDialog()
        local dd = EnsureBugReportDropDown()
        dd.achievementId = button.achievementId
        ToggleDropDownMenu(1, nil, dd, "cursor", 0, 0)
        return
    end

    -- Check if achievement has progress data (only expand if it has progress or criteria)
    local achievement = Data._achievements[button.achievementId]
    if achievement then
        local hasProgress = type(achievement.current) == "number" and type(achievement.total) == "number" and
            achievement.total > 0 and not achievement.completed
        local hasCriteria = achievement.criteria and type(achievement.criteria) == "table" and #achievement.criteria > 0 and
            not achievement.completed
        if not hasProgress and not hasCriteria then
            -- No progress to show, don't expand
            return
        end
    end

    -- Toggle selection (expand/collapse)
    if frame.selectedAchievementId == button.achievementId then
        -- Collapse
        frame.selectedAchievementId = nil
        button.selected = false
        button.collapsed = true
        ReckoningAchievementButton_Collapse(button)
    else
        -- Collapse previously selected button
        if frame.selectedAchievementId then
            local scrollFrame = frame.achievementsContainer
            if scrollFrame and scrollFrame.buttons then
                for _, btn in ipairs(scrollFrame.buttons) do
                    if btn.achievementId == frame.selectedAchievementId then
                        btn.collapsed = true
                        btn.selected = false
                        ReckoningAchievementButton_Collapse(btn)
                        break
                    end
                end
            end
        end
        -- Expand this button
        frame.selectedAchievementId = button.achievementId
        button.selected = true
        button.collapsed = false
        ReckoningAchievementButton_Expand(button)
    end

    ReckoningAchievementFrame_UpdateAchievements(frame)
    PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or "igMainMenuOptionCheckBoxOn")
end

function ReckoningAchievementButton_Collapse(button)
    button.collapsed = true
    button:SetHeight(ACHIEVEMENTBUTTON_COLLAPSEDHEIGHT)
    if button.background then
        button.background:SetTexCoord(0, 1, 1 - (ACHIEVEMENTBUTTON_COLLAPSEDHEIGHT / 256), 1)
    end
end

function ReckoningAchievementButton_Expand(button)
    button.collapsed = false

    -- Start with collapsed height
    local height = ACHIEVEMENTBUTTON_COLLAPSEDHEIGHT

    -- Add height for progress bar if visible (appears in expanded area below description)
    if button.progressBar and button.progressBar:IsShown() then
        height = height + 25 -- Add space for progress bar in expanded area
    end

    -- Add height for criteria list if visible
    if button.criteriaList and button.criteriaList:IsShown() then
        local numCriteria = button.criteriaList.numCriteria or 0
        if numCriteria > 0 then
            height = height + (numCriteria * 16) + 5 -- 16px per criteria line + 5px spacing
        end
    end

    -- Clamp to max height
    height = math.min(height, ACHIEVEMENTBUTTON_MAXHEIGHT)

    button:SetHeight(height)
    if button.background then
        button.background:SetTexCoord(0, 1, math.max(0, 1 - (height / 256)), 1)
    end
end

function ReckoningAchievementButton_OnEnter(button)
    if not button.achievementId then
        return
    end
    local achievement = Data._achievements[button.achievementId]
    if not achievement then
        return
    end

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(achievement.name or "", 1, 1, 1)
    if achievement.description then
        GameTooltip:AddLine(achievement.description, 0.9, 0.9, 0.9, true)
    end
    local progress = FormatProgress(achievement)
    if progress then
        GameTooltip:AddLine("Progress: " .. progress, 0.7, 0.7, 0.7, true)
    end
    if achievement.points then
        local const = Private and Private.constants
        local pointsName = const and const.DISPLAY and const.DISPLAY.POINTS_NAME or "Points"
        local counts = button.countsForThisPlayer
        if counts == nil then
            local priv = Private or Reckoning.Private
            local correctionSync = priv and priv.CorrectionSyncUtils
            local db = (priv and priv.Addon and priv.Addon.Database) or nil
            local completedData = db and db.completed
            local completedAt, addonVersion = nil, nil
            if completedData and achievement.id and completedData[achievement.id] then
                completedAt = completedData[achievement.id].completedAt
                addonVersion = completedData[achievement.id].addonVersion and tostring(completedData[achievement.id].addonVersion) or nil
            else
                completedAt = time()
                addonVersion = (priv and priv.constants and priv.constants.ADDON_VERSION) and tostring(priv.constants.ADDON_VERSION) or nil
            end
            counts = (not correctionSync or not correctionSync.ShouldCountAchievementPoints) or
                correctionSync:ShouldCountAchievementPoints(achievement.id, completedAt, addonVersion)
        end
        if counts then
            GameTooltip:AddLine(pointsName .. ": " .. achievement.points, 1, 0.82, 0)
        else
            GameTooltip:AddLine(pointsName .. ": 0 (does not count)", 0.8, 0.4, 0.4)
            GameTooltip:AddLine("Invalidated or version restricted.", 0.65, 0.5, 0.5, true)
        end
    end
    GameTooltip:Show()
end

function ReckoningAchievementButton_OnLeave(button)
    GameTooltip:Hide()
end

function ReckoningAchievementButton_UpdateCriteriaList(button, criteriaData)
    if not button.criteriaList then
        return
    end

    -- Create or update criteria text strings
    if not button.criteriaList.criteriaStrings then
        button.criteriaList.criteriaStrings = {}
    end

    local strings = button.criteriaList.criteriaStrings
    local numCriteria = #criteriaData

    -- Create font strings as needed
    for i = 1, numCriteria do
        if not strings[i] then
            strings[i] = button.criteriaList:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            strings[i]:SetJustifyH("LEFT")
            strings[i]:SetPoint("TOPLEFT", button.criteriaList, "TOPLEFT", 5, -(i - 1) * 16)
            strings[i]:SetPoint("TOPRIGHT", button.criteriaList, "TOPRIGHT", -5, -(i - 1) * 16)
        end

        local criteria = criteriaData[i]
        local text = criteria.name or ""

        if criteria.completed then
            -- Green for completed
            strings[i]:SetText("|cff00ff00- " .. text .. "|r")
        else
            -- Grey for incomplete
            strings[i]:SetText("|cff808080- " .. text .. "|r")
        end
        strings[i]:Show()
    end

    -- Hide unused strings
    for i = numCriteria + 1, #strings do
        strings[i]:Hide()
    end

    button.criteriaList.numCriteria = numCriteria
end

function ReckoningAchievementFrame_UpdateSearchResults(frame)
    if not frame.SearchResults then
        return
    end

    local searchText = frame.searchText or ""

    if searchText == "" then
        frame.SearchResults:Hide()
        return
    end

    local results = Data:SearchAllAchievements(searchText)

    if #results == 0 then
        frame.SearchResults:Hide()
        return
    end

    -- Create or update result buttons
    if not frame.SearchResults.buttons then
        frame.SearchResults.buttons = {}
    end

    local buttons = frame.SearchResults.buttons
    local numResults = #results

    -- Create buttons as needed
    for i = 1, numResults do
        if not buttons[i] then
            local button = CreateFrame("Button", nil, frame.SearchResults)
            button:SetSize(206, 27)

            -- Normal texture (using atlas)
            local normal = button:CreateTexture(nil, "BACKGROUND")
            normal:SetAllPoints()
            normal:SetAtlas("_search-rowbg")
            button:SetNormalTexture(normal)

            -- Pushed texture (using atlas)
            local pushed = button:CreateTexture(nil, "BACKGROUND")
            pushed:SetAllPoints()
            pushed:SetAtlas("_search-rowbg")
            button:SetPushedTexture(pushed)

            -- Highlight texture (using atlas)
            local highlight = button:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetAtlas("search-highlight")
            button:SetHighlightTexture(highlight)

            -- Icon frame (using atlas)
            local iconFrame = button:CreateTexture(nil, "OVERLAY", nil, 2)
            iconFrame:SetSize(21, 21)
            iconFrame:SetPoint("LEFT", 5, 1)
            iconFrame:SetAtlas("search-iconframe-large")
            button.iconFrame = iconFrame

            -- Icon
            local icon = button:CreateTexture(nil, "OVERLAY")
            icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -2)
            icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
            button.icon = icon

            -- Text (artifact color)
            local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            text:SetPoint("RIGHT", -5, 0)
            text:SetJustifyH("LEFT")
            text:SetTextColor(0.96875, 0.8984375, 0.578125, 1)
            button.text = text

            if i == 1 then
                button:SetPoint("TOPLEFT", frame.SearchResults, "TOPLEFT", 2, -2)
            else
                button:SetPoint("TOPLEFT", buttons[i - 1], "BOTTOMLEFT", 0, 0)
            end

            button:SetScript("OnClick", function(self)
                if self.achievementId then
                    -- Clear search BEFORE navigating
                    frame.SearchBox:SetText("")
                    frame.searchText = ""
                    ReckoningAchievementFrame_UpdateSearchResults(frame)
                    -- Jump to achievement the same way as clicking from summary
                    ReckoningAchievementFrame_SelectAchievement(self.achievementId)
                end
            end)

            -- No tooltip on hover - just like official UI
            button:SetScript("OnEnter", nil)
            button:SetScript("OnLeave", nil)

            buttons[i] = button
        end

        local achievement = results[i]
        buttons[i].achievementId = achievement.id
        buttons[i].icon:SetTexture(achievement.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        buttons[i].text:SetText(achievement.name or "Unknown Achievement")
        buttons[i]:Show()
    end

    -- Hide unused buttons
    for i = numResults + 1, #buttons do
        buttons[i]:Hide()
    end

    -- Resize results frame and adjust border to last button
    local height = numResults * 27
    frame.SearchResults:SetHeight(height)

    -- Adjust border anchor to last visible button (with extra spacing)
    if frame.SearchResults.BorderAnchor and numResults > 0 then
        local lastButton = buttons[numResults]
        frame.SearchResults.BorderAnchor:ClearAllPoints()
        frame.SearchResults.BorderAnchor:SetPoint("LEFT", frame.SearchResults, "LEFT", -7, 0)
        frame.SearchResults.BorderAnchor:SetPoint("BOTTOM", lastButton, "BOTTOM", 0, -8)
    end

    frame.SearchResults:Show()
end

-------------------------------------------------------------------------------
-- Category List Update
-------------------------------------------------------------------------------

function ReckoningAchievementFrame_UpdateCategories(frame)
    local scrollFrame = frame.categoriesContainer
    if not scrollFrame or not scrollFrame.buttons then
        return
    end

    local buttons = scrollFrame.buttons
    local categories = frame.categoryList or {}
    local offset = HybridScrollFrame_GetOffset(scrollFrame)
    local buttonHeight = 20

    -- Build list of visible categories (skip hidden ones)
    local visibleCategories = {}
    for _, category in ipairs(categories) do
        if not category.hidden then
            visibleCategories[#visibleCategories + 1] = category
        end
    end

    -- Update buttons
    for i = 1, #buttons do
        local index = i + offset
        local button = buttons[i]
        local category = visibleCategories[index]

        if category then
            button:Show()
            button.categoryId = category.id
            button.element = category

            -- Set width based on whether it's a sub-category
            -- Sub-categories have parent as a number, parent categories have parent = true or nil
            if type(category.parent) == "number" then
                -- Sub-category: narrower width for indent effect
                button:SetWidth(150) -- narrower than parent
                button.label:SetFontObject("GameFontHighlightSmall")
            else
                -- Parent category: full width
                button:SetWidth(165)
                button.label:SetFontObject("GameFontNormal")
            end

            button.label:SetText(category.name)

            -- Highlight selected category
            if frame.selectedCategoryId == category.id then
                button.label:SetFontObject("GameFontHighlight")
                if button.background then
                    button.background:SetVertexColor(1, 1, 1, 1)
                end
                if button.highlight then
                    button.highlight:Show()
                end
            else
                if button.background then
                    if type(category.parent) == "number" then
                        button.background:SetVertexColor(0.6, 0.6, 0.6, 1)
                    else
                        button.background:SetVertexColor(0.8, 0.8, 0.8, 1)
                    end
                end
                if button.highlight then
                    button.highlight:Hide()
                end
            end
        else
            button:Hide()
            button.categoryId = nil
            button.element = nil
        end
    end

    HybridScrollFrame_Update(scrollFrame, #visibleCategories * buttonHeight, scrollFrame:GetHeight())
end

-------------------------------------------------------------------------------
-- Summary Panel Update
-------------------------------------------------------------------------------

-- Summary category button handlers
function ReckoningSummaryCategoryButton_OnClick(self, button, down)
    local statusBar = self:GetParent()
    if statusBar and statusBar.categoryId then
        local frame = GetAchievementFrame()
        if frame then
            local categoryId = statusBar.categoryId
            local categories = frame.categoryList

            -- Find the category element
            local targetElement = nil
            for _, cat in ipairs(categories) do
                if cat.id == categoryId then
                    targetElement = cat
                    break
                end
            end

            -- If this is a parent category with children, expand it
            if targetElement and targetElement.parent == true then
                -- Expand this parent, collapse all others
                for _, cat in ipairs(categories) do
                    if cat.parent == categoryId then
                        -- Show children of this parent
                        cat.hidden = false
                    elseif cat.parent == true then
                        -- Collapse other parent categories
                        cat.collapsed = true
                    elseif type(cat.parent) == "number" and cat.parent ~= categoryId then
                        -- Hide children of other parents
                        cat.hidden = true
                    end
                end
                targetElement.collapsed = false

                -- If this category has no direct achievements, select first subcategory
                local directAchievements = Data._achievementsByCategory[categoryId] or {}
                if #directAchievements == 0 then
                    for _, cat in ipairs(categories) do
                        if cat.parent == categoryId and not cat.hidden then
                            categoryId = cat.id
                            break
                        end
                    end
                end
            end

            frame.selectedCategoryId = categoryId
            ReckoningAchievementFrame_UpdateCategories(frame)
            ReckoningAchievementFrame_UpdateAchievements(frame)
            PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or "igMainMenuOptionCheckBoxOn")
        end
    end
end

function ReckoningSummaryCategoryButton_OnEnter(self)
    local highlight = self.highlight or self:GetParent().highlight
    if highlight then
        highlight:Show()
    end
end

function ReckoningSummaryCategoryButton_OnLeave(self)
    local highlight = self.highlight or self:GetParent().highlight
    if highlight then
        highlight:Hide()
    end
end

function ReckoningAchievementFrame_UpdateSummary(frame)
    local summary = frame.Summary
    if not summary then return end

    -- Update the overall completion status bar
    local categoriesProgress = summary.CategoriesProgress
    if categoriesProgress then
        local statusBar = categoriesProgress.StatusBar
        if statusBar then
            local completed = Data:GetCompletedAchievementCount()
            local total = Data:GetTotalAchievementCount()
            statusBar:SetMinMaxValues(0, math.max(total, 1))
            statusBar:SetValue(completed)
            if statusBar.Text then
                statusBar.Text:SetText(completed .. " / " .. total)
            end
        end

        -- Get the parent categories (not sub-categories) for the 8 category bars
        local parentCategories = {}
        for _, cat in pairs(Data._categories) do
            if not cat.parentId then
                parentCategories[#parentCategories + 1] = cat
            end
        end
        -- Sort by order
        table.sort(parentCategories, function(a, b)
            local ao = a.order or a.id
            local bo = b.order or b.id
            if ao ~= bo then return ao < bo end
            return a.name < b.name
        end)

        -- Update category status bars (up to 8)
        for i = 1, 8 do
            local categoryBar = categoriesProgress["Category" .. i]
            if categoryBar then
                local category = parentCategories[i]
                if category then
                    categoryBar:Show()
                    categoryBar.categoryId = category.id
                    local catCompleted, catTotal = Data:GetCategoryProgress(category.id)
                    categoryBar:SetMinMaxValues(0, math.max(catTotal, 1))
                    categoryBar:SetValue(catCompleted)
                    if categoryBar.label then
                        categoryBar.label:SetText(category.name)
                    end
                    if categoryBar.text then
                        categoryBar.text:SetText(catCompleted .. "/" .. catTotal)
                    end
                else
                    categoryBar:Hide()
                end
            end
        end
    end

    -- Update recent achievements section
    local achievementsSection = summary.Achievements
    if achievementsSection then
        local recentAchievements = Data:GetRecentCompletedAchievements(4)
        local hasRecent = #recentAchievements > 0

        -- Show/hide empty text based on whether we have recent achievements
        if achievementsSection.EmptyText then
            achievementsSection.EmptyText:SetShown(not hasRecent)
        end
        if achievementsSection.Placeholder then
            achievementsSection.Placeholder:SetShown(not hasRecent)
        end

        -- Create or update achievement buttons
        if not achievementsSection.buttons then
            achievementsSection.buttons = {}
        end

        -- Create buttons as needed
        for i = 1, 4 do
            if not achievementsSection.buttons[i] then
                local button = CreateFrame("Frame", "ReckoningAchievementFrameSummaryAchievement" .. i,
                    achievementsSection, "ReckoningRecentAchievementTemplate")

                if i == 1 then
                    button:SetPoint("TOPLEFT", achievementsSection.Header, "BOTTOMLEFT", 18, 2)
                    button:SetPoint("TOPRIGHT", achievementsSection.Header, "BOTTOMRIGHT", -18, 2)
                else
                    local anchorTo = achievementsSection.buttons[i - 1]
                    button:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, 3)
                    button:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, 3)
                end

                achievementsSection.buttons[i] = button
            end
        end

        -- Update or hide buttons
        for i = 1, 4 do
            local button = achievementsSection.buttons[i]
            if i <= #recentAchievements then
                local achievement = recentAchievements[i]
                button.Icon.Texture:SetTexture(achievement.icon or "Interface\\Icons\\Achievement_BG_winWSG")
                button.Title:SetText(achievement.name or "Unknown Achievement")
                button.Description:SetText(achievement.description or "")
                button.Shield.Points:SetText(achievement.points or 0)
                button.achievementId = achievement.id
                button:Show()
            else
                button:Hide()
            end
        end
    end
end

function ReckoningAchievementFrame_SelectAchievement(achievementId)
    if not achievementId then
        return
    end

    local frame = ReckoningAchievementFrame
    if not frame then
        return
    end

    -- Get the category for this achievement
    local categoryId = Data:GetAchievementCategory(achievementId)
    if not categoryId then
        return
    end

    -- Hide summary panel, show achievements panel
    if frame.Summary then
        frame.Summary:Hide()
    end
    if frame.Achievements then
        frame.Achievements:Show()
    end

    -- Switch to the category
    frame.selectedCategoryId = categoryId

    -- Select the achievement
    frame.selectedAchievementId = achievementId

    ReckoningAchievementFrame_UpdateCategories(frame)

    -- Update achievements display
    ReckoningAchievementFrame_UpdateAchievements(frame)

    -- Scroll to the achievement
    local scrollFrame = frame.achievementsContainer
    if scrollFrame then
        local filter = frame.currentFilter or ACHIEVEMENT_FILTER_ALL
        local searchText = frame.searchText or ""
        local achievements = Data:GetAchievements(categoryId, filter, searchText)

        -- Find the index of the achievement
        local achievementIndex = nil
        for i, achievement in ipairs(achievements) do
            if achievement.id == achievementId then
                achievementIndex = i
                break
            end
        end

        if achievementIndex then
            -- Scroll to show the achievement (offset starts at 0)
            local targetOffset = achievementIndex - 1
            local maxOffset = math.max(0,
                #achievements - math.floor(scrollFrame:GetHeight() / ACHIEVEMENTBUTTON_COLLAPSEDHEIGHT))
            targetOffset = math.min(targetOffset, maxOffset)

            HybridScrollFrame_SetOffset(scrollFrame, targetOffset)
            scrollFrame.scrollBar:SetValue(targetOffset * ACHIEVEMENTBUTTON_COLLAPSEDHEIGHT)

            -- Force update to show the change
            ReckoningAchievementFrame_UpdateAchievements(frame)
        end
    end
end

function ReckoningAchievementFrame_UpdateAchievements(frame)
    local categoryId = frame.selectedCategoryId

    -- Check if Summary category is selected (id = -1)
    if categoryId == -1 then
        -- Show Summary, hide Achievements
        if frame.Summary then
            frame.Summary:Show()
            ReckoningAchievementFrame_UpdateSummary(frame)
        end
        if frame.Achievements then
            frame.Achievements:Hide()
        end
        -- Hide filter dropdown on summary page (but keep search box visible)
        if frame.FilterDropDown then
            frame.FilterDropDown:Hide()
        end
        if frame.Header and frame.Header.LeftDDLInset then
            frame.Header.LeftDDLInset:Hide()
        end
        -- Keep RightDDLInset visible for search bar
        -- Hide achievements panel background
        if frame.Achievements and frame.Achievements.Background then
            frame.Achievements.Background:Hide()
        end
        if frame.Achievements and frame.Achievements.BackgroundBlackCover then
            frame.Achievements.BackgroundBlackCover:Hide()
        end
        return
    else
        -- Show Achievements, hide Summary
        if frame.Summary then
            frame.Summary:Hide()
        end
        if frame.Achievements then
            frame.Achievements:Show()
        end
        -- Show filter dropdown on achievement pages
        if frame.FilterDropDown then
            frame.FilterDropDown:Show()
        end
        if frame.Header and frame.Header.LeftDDLInset then
            frame.Header.LeftDDLInset:Show()
        end
        if frame.Header and frame.Header.RightDDLInset then
            frame.Header.RightDDLInset:Show()
        end
        -- Show achievements panel background
        if frame.Achievements and frame.Achievements.Background then
            frame.Achievements.Background:Show()
        end
        if frame.Achievements and frame.Achievements.BackgroundBlackCover then
            frame.Achievements.BackgroundBlackCover:Show()
        end
    end

    local scrollFrame = frame.achievementsContainer
    if not scrollFrame or not scrollFrame.buttons then
        return
    end

    local buttons = scrollFrame.buttons
    local filter = frame.currentFilter or ACHIEVEMENT_FILTER_ALL
    local searchText = frame.searchText or ""
    local achievements = categoryId and Data:GetAchievements(categoryId, filter, searchText) or {}
    local offset = HybridScrollFrame_GetOffset(scrollFrame)
    local priv = Private or Reckoning.Private
    local correctionSync = priv and priv.CorrectionSyncUtils
    local addon = priv and priv.Addon
    local db = addon and addon.Database
    local completedData = db and db.completed

    -- Calculate total height with variable button heights
    local totalHeight = 0
    local expandedButtonHeight = 0
    for idx, achievement in ipairs(achievements) do
        if achievement.id == frame.selectedAchievementId then
            expandedButtonHeight = ACHIEVEMENTBUTTON_COLLAPSEDHEIGHT + 40 -- Approximate expanded height
            totalHeight = totalHeight + expandedButtonHeight
        else
            totalHeight = totalHeight + ACHIEVEMENTBUTTON_COLLAPSEDHEIGHT
        end
    end

    for i = 1, #buttons do
        local index = i + offset
        local button = buttons[i]
        local achievement = achievements[index]

        if achievement then
            button:Show()
            button.achievementId = achievement.id
            button.selected = (frame.selectedAchievementId == achievement.id)
            button.collapsed = not button.selected

            -- Whether this achievement counts for points (corrections + version gating)
            local completedAt, addonVersion = nil, nil
            if completedData and achievement.id and completedData[achievement.id] then
                completedAt = completedData[achievement.id].completedAt
                addonVersion = completedData[achievement.id].addonVersion and tostring(completedData[achievement.id].addonVersion) or nil
            else
                completedAt = time()
                addonVersion = (priv and priv.constants and priv.constants.ADDON_VERSION) and tostring(priv.constants.ADDON_VERSION) or nil
            end
            local countsForThisPlayer = true
            if correctionSync and correctionSync.ShouldCountAchievementPoints then
                countsForThisPlayer = correctionSync:ShouldCountAchievementPoints(achievement.id, completedAt, addonVersion)
            end
            button.countsForThisPlayer = countsForThisPlayer

            -- Set text
            if button.label then
                button.label:SetText(achievement.name or "")
            end
            if button.description then
                button.description:SetText(achievement.description or "")
            end

            -- Set icon
            if button.icon and button.icon.texture then
                button.icon.texture:SetTexture(achievement.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            end

            -- Set points on shield (0 if invalid)
            if button.shield and button.shield.points then
                if countsForThisPlayer then
                    button.shield.points:SetText(achievement.points and tostring(achievement.points) or "")
                else
                    button.shield.points:SetText("0")
                end
            end

            -- Hide check mark (we use visual styling instead)
            if button.check then
                button.check:Hide()
            end

            -- Update highlight
            if button.highlight then
                button.highlight:SetShown(button.selected)
            end

            -- Update visual style based on completion (Blizzard style)
            if achievement.completed then
                -- SATURATED (Completed) - Full color, vibrant look
                if button.background then
                    button.background:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal")
                    button.background:SetVertexColor(1, 1, 1, 1)
                end
                if button.titleBar then
                    button.titleBar:SetTexCoord(0, 1, 0.66015625, 0.73828125)
                    button.titleBar:SetAlpha(0.8)
                end
                if button.glow then
                    button.glow:SetVertexColor(1.0, 1.0, 1.0)
                end
                if button.icon then
                    if button.icon.texture then
                        button.icon.texture:SetVertexColor(1, 1, 1, 1)
                    end
                    if button.icon.frame then
                        button.icon.frame:SetVertexColor(1, 1, 1, 1)
                    end
                end
                if button.shield then
                    if button.shield.icon then
                        button.shield.icon:SetTexCoord(0, 0.5, 0, 0.5) -- Left half - gold shield
                    end
                    if button.shield.points then
                        button.shield.points:SetVertexColor(1, 1, 1, 1)
                    end
                end
                if button.label then
                    button.label:SetVertexColor(1, 1, 1, 1)
                end
                if button.description then
                    button.description:SetTextColor(0, 0, 0, 1)
                    button.description:SetShadowOffset(0, 0)
                end
                if button.SetBackdropBorderColor then
                    local color = Reckoning_Achievements.RED_BORDER_COLOR
                    if color and color.GetRGB then
                        button:SetBackdropBorderColor(color:GetRGB())
                    end
                end
            else
                -- DESATURATED (Incomplete) - Greyed out, muted look
                if button.background then
                    button.background:SetTexture(
                        "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal-Desaturated")
                    button.background:SetVertexColor(1, 1, 1, 1)
                end
                if button.titleBar then
                    button.titleBar:SetTexCoord(0, 1, 0.91796875, 0.99609375)
                    button.titleBar:SetAlpha(0.8)
                end
                if button.glow then
                    button.glow:SetVertexColor(0.22, 0.17, 0.13)
                end
                if button.icon then
                    if button.icon.texture then
                        button.icon.texture:SetVertexColor(0.55, 0.55, 0.55, 1)
                    end
                    if button.icon.frame then
                        button.icon.frame:SetVertexColor(0.75, 0.75, 0.75, 1)
                    end
                end
                if button.shield then
                    if button.shield.icon then
                        button.shield.icon:SetTexCoord(0.5, 1, 0, 0.5) -- Right half - grey shield
                    end
                    if button.shield.points then
                        button.shield.points:SetVertexColor(0.65, 0.65, 0.65, 1)
                    end
                end
                if button.label then
                    button.label:SetVertexColor(0.65, 0.65, 0.65, 1)
                end
                if button.description then
                    button.description:SetTextColor(1, 1, 1, 1)
                    button.description:SetShadowOffset(1, -1)
                end
                if button.SetBackdropBorderColor then
                    button:SetBackdropBorderColor(0.5, 0.5, 0.5)
                end
            end

            -- Override: invalid (does not count for points) - reddish grey tint
            if not countsForThisPlayer then
                if button.background then
                    button.background:SetTexture(
                        "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal-Desaturated")
                    button.background:SetVertexColor(0.85, 0.5, 0.5, 1)
                end
                if button.icon then
                    if button.icon.texture then
                        button.icon.texture:SetVertexColor(0.7, 0.4, 0.4, 1)
                    end
                    if button.icon.frame then
                        button.icon.frame:SetVertexColor(0.75, 0.5, 0.5, 1)
                    end
                end
                if button.shield and button.shield.points then
                    button.shield.points:SetVertexColor(0.8, 0.4, 0.4, 1)
                end
                if button.label then
                    button.label:SetVertexColor(0.85, 0.5, 0.5, 1)
                end
                if button.SetBackdropBorderColor then
                    local color = Reckoning_Achievements.RED_BORDER_COLOR
                    if color and color.GetRGB then
                        button:SetBackdropBorderColor(color:GetRGB())
                    else
                        button:SetBackdropBorderColor(0.7, 0.15, 0.05)
                    end
                end
            end

            -- Check if achievement has expandable progress
            local hasProgress = type(achievement.current) == "number" and type(achievement.total) == "number" and
                achievement.total > 0 and not achievement.completed
            local hasCriteria = achievement.criteria and type(achievement.criteria) == "table" and
                #achievement.criteria > 0

            -- Update progress bar (only show when expanded)
            if button.progressBar then
                if button.selected and hasProgress then
                    button.progressBar:Show()
                    button.progressBar:SetMinMaxValues(0, achievement.total)
                    button.progressBar:SetValue(math.min(achievement.current, achievement.total))
                    if button.progressBar.text then
                        button.progressBar.text:SetText(string.format("%d/%d", achievement.current, achievement.total))
                    end
                else
                    button.progressBar:Hide()
                end
            end

            -- Update criteria list (only show when expanded)
            if button.criteriaList then
                if button.selected and hasCriteria and not achievement.completed then
                    ReckoningAchievementButton_UpdateCriteriaList(button, achievement.criteria)
                    button.criteriaList:Show()
                else
                    button.criteriaList:Hide()
                end
            end

            -- Apply collapsed/expanded state
            if button.selected then
                ReckoningAchievementButton_Expand(button)
            else
                ReckoningAchievementButton_Collapse(button)
            end
        else
            button:Hide()
            button.achievementId = nil
            button.selected = false
        end
    end

    HybridScrollFrame_Update(scrollFrame, totalHeight, scrollFrame:GetHeight())
end

-------------------------------------------------------------------------------
-- Compatibility Layer (for code that expects Blizzard API)
-------------------------------------------------------------------------------

if not GetCategoryList then
    function GetCategoryList()
        local out = {}
        for _, category in ipairs(Data:GetCategories()) do
            out[#out + 1] = category.id
        end
        return out
    end
end

if not GetCategoryInfo then
    function GetCategoryInfo(categoryID)
        local category = Data._categories and Data._categories[categoryID]
        if category then
            return category.name or "", category.parentId or -1, 0
        end
        return "", -1, 0
    end
end

if not GetCategoryNumAchievements then
    function GetCategoryNumAchievements(categoryID, includeAll)
        local total, completed, incompleted = 0, 0, 0
        local list = Data._achievementsByCategory and Data._achievementsByCategory[categoryID] or {}
        for _, achievement in pairs(list) do
            total = total + 1
            if achievement.completed then
                completed = completed + 1
            else
                incompleted = incompleted + 1
            end
        end
        return total, completed, incompleted
    end
end

if not GetAchievementInfo then
    function GetAchievementInfo(id, index)
        local achievement
        if index then
            local list = Data:GetAchievements(id)
            achievement = list and list[index] or nil
        else
            achievement = Data._achievements and Data._achievements[id] or nil
        end

        if not achievement then
            return 1, "", 0, false, nil, nil, nil, "", 0, "Interface\\Icons\\INV_Misc_QuestionMark", "", false, false,
                nil, false
        end

        local flags = 0
        if type(achievement.current) == "number" and type(achievement.total) == "number" then
            flags = bit and bit.bor and bit.bor(flags, 0x80) or flags
        end

        local completed = achievement.completed == true
        local earnedBy = completed and (UnitName and UnitName("player") or nil) or nil
        return achievement.id, achievement.name or "", achievement.points or 0, completed, nil, nil, nil,
            achievement.description or "", flags, (achievement.icon or "Interface\\Icons\\INV_Misc_QuestionMark"),
            "", false, completed, earnedBy, false
    end
end

if not GetTotalAchievementPoints then
    function GetTotalAchievementPoints()
        return Data:GetTotalPointsEarned()
    end
end

-------------------------------------------------------------------------------
-- Slash Command
-------------------------------------------------------------------------------

SLASH_RECKONINGACHIEVEMENTS1 = "/reckachievements"
SLASH_RECKONINGACHIEVEMENTS2 = "/reckach"
SlashCmdList["RECKONINGACHIEVEMENTS"] = function(msg)
    ReckoningAchievementFrame_Toggle()
end
