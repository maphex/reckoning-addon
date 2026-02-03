-- Reckoning Achievement Frame
-- A custom achievement UI for private servers without the Blizzard Achievement API

-- Create addon namespace
Reckoning = Reckoning or {}
Reckoning.Achievements = Reckoning.Achievements or {}

local Reckoning_Achievements = Reckoning.Achievements

-- Get Private namespace (set by Init.lua)
local Private = Reckoning.Private

-------------------------------------------------------------------------------
-- Frame Registration
-------------------------------------------------------------------------------

UIPanelWindows = UIPanelWindows or {}
UIPanelWindows["ReckoningAchievementFrame"] = { area = "doublewide", pushable = 0, xoffset = 80, whileDead = 1 }

-- Register for ESC close
UISpecialFrames = UISpecialFrames or {}
do
    local found = false
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == "ReckoningAchievementFrame" then
            found = true
            break
        end
    end
    if not found then
        UISpecialFrames[#UISpecialFrames + 1] = "ReckoningAchievementFrame"
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
    local total = 0
    for _, achievement in pairs(self._achievements) do
        if IsAchievementAvailable(achievement) and achievement.completed then
            total = total + (achievement.points or 0)
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
-- Toggle Function
-------------------------------------------------------------------------------

function ReckoningAchievementFrame_Toggle()
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

    -- Select Achievements tab by default
    ReckoningAchievementFrame_SelectTab(1)
end

function ReckoningAchievementFrame_OnShow(self)
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

    -- Update tab visuals now that textures are fully initialized
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

function ReckoningAchievementFrame_SelectTab(tabNum)
    local frame = ReckoningAchievementFrame

    -- Update tab button states manually (ReckoningAchievementFrameTabButtonTemplate doesn't use PanelTemplates)
    -- Access textures using _G since they're named regions, not parentKey properties
    local tab1Name = "ReckoningAchievementFrameTab1"
    local tab2Name = "ReckoningAchievementFrameTab2"

    local tab1 = _G[tab1Name]
    local tab2 = _G[tab2Name]

    -- Check if textures exist (they might not be created yet during OnLoad)
    local tab1Left = _G[tab1Name .. "Left"]
    if not tab1Left then
        -- Textures not created yet, skip visual update
        -- This can happen during OnLoad before template is fully initialized
    else
        if tabNum == 1 then
            -- Tab 1 selected (show disabled/raised textures)
            _G[tab1Name .. "Left"]:Hide()
            _G[tab1Name .. "Middle"]:Hide()
            _G[tab1Name .. "Right"]:Hide()
            _G[tab1Name .. "LeftDisabled"]:Show()
            _G[tab1Name .. "MiddleDisabled"]:Show()
            _G[tab1Name .. "RightDisabled"]:Show()

            -- Set tab 1 as selected, white text
            if tab1 then
                tab1.isSelected = true
                if tab1.text then
                    tab1.text:SetTextColor(1, 1, 1) -- White
                end
                -- Hide highlights on selected tab
                if tab1.leftHighlight then
                    tab1.leftHighlight:Hide()
                    tab1.middleHighlight:Hide()
                    tab1.rightHighlight:Hide()
                end
            end

            -- Tab 2 unselected (show normal/flat textures)
            _G[tab2Name .. "Left"]:Show()
            _G[tab2Name .. "Middle"]:Show()
            _G[tab2Name .. "Right"]:Show()
            _G[tab2Name .. "LeftDisabled"]:Hide()
            _G[tab2Name .. "MiddleDisabled"]:Hide()
            _G[tab2Name .. "RightDisabled"]:Hide()

            -- Set tab 2 as unselected, yellow text
            if tab2 then
                tab2.isSelected = false
                if tab2.text then
                    tab2.text:SetTextColor(1, 0.82, 0) -- Yellow (GameFontNormal)
                end
            end
        else
            -- Tab 2 selected (show disabled/raised textures)
            _G[tab1Name .. "Left"]:Show()
            _G[tab1Name .. "Middle"]:Show()
            _G[tab1Name .. "Right"]:Show()
            _G[tab1Name .. "LeftDisabled"]:Hide()
            _G[tab1Name .. "MiddleDisabled"]:Hide()
            _G[tab1Name .. "RightDisabled"]:Hide()

            -- Set tab 1 as unselected, yellow text
            if tab1 then
                tab1.isSelected = false
                if tab1.text then
                    tab1.text:SetTextColor(1, 0.82, 0) -- Yellow
                end
            end

            -- Tab 2 selected
            _G[tab2Name .. "Left"]:Hide()
            _G[tab2Name .. "Middle"]:Hide()
            _G[tab2Name .. "Right"]:Hide()
            _G[tab2Name .. "LeftDisabled"]:Show()
            _G[tab2Name .. "MiddleDisabled"]:Show()
            _G[tab2Name .. "RightDisabled"]:Show()

            -- Set tab 2 as selected, white text
            if tab2 then
                tab2.isSelected = true
                if tab2.text then
                    tab2.text:SetTextColor(1, 1, 1) -- White
                end
                -- Hide highlights on selected tab
                if tab2.leftHighlight then
                    tab2.leftHighlight:Hide()
                    tab2.middleHighlight:Hide()
                    tab2.rightHighlight:Hide()
                end
            end
        end
    end
    frame.Achievements:Hide()
    frame.Summary:Hide()
    frame.SearchBox:Hide()
    frame.SearchResults:Hide()
    frame.Guild:Hide()
    frame.Categories:Hide()

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
    button:RegisterForClicks("LeftButtonUp")

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

        -- Set click handler to jump to achievement
        button:SetScript("OnClick", function(self)
            if self.achievementId then
                -- Switch to Achievements tab first
                ReckoningAchievementFrame_SelectTab(1)

                -- Use the existing function that handles category switching and scrolling
                ReckoningAchievementFrame_SelectAchievement(self.achievementId)

                PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or "igMainMenuOptionCheckBoxOn")
            end
        end)
    end

    -- Set up sync button text
    if parentEvents and parentEvents.Header and parentEvents.Header.SyncButton then
        parentEvents.Header.SyncButton:SetText("Sync")
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
    button.Version = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    button.Version:SetPoint("LEFT", 260, 0)
    button.LastSeen = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    button.LastSeen:SetPoint("LEFT", 360, 0)

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
    button:RegisterForClicks("LeftButtonUp")
    button.collapsed = true
    -- Set backdrop color to transparent to avoid grey overlay
    if button.SetBackdropColor then
        button:SetBackdropColor(0, 0, 0, 0)
    end
end

function ReckoningAchievementButton_OnClick(button)
    local frame = GetAchievementFrame()
    if not frame or not button.achievementId then
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
        GameTooltip:AddLine(pointsName .. ": " .. achievement.points, 1, 0.82, 0)
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

            -- Set points on shield
            if button.shield and button.shield.points then
                button.shield.points:SetText(achievement.points and tostring(achievement.points) or "")
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
