---@class AddonPrivate
local Private = select(2, ...)

local Enums = Private.Enums

-------------------------------------------------------------------------------
-- Achievement Utils
-------------------------------------------------------------------------------

---@class AchievementCategory
---@field id number
---@field name string
---@field subCategories? AchievementSubCategory[]

---@class AchievementSubCategory
---@field id number
---@field name string

---@class AchievementTrigger
---@field event string
---@field conditions? table<string, any>
---@field criteriaSet? table[]

---@class AchievementProgress
---@field type "count"|"criteria"|"meta"
---@field required? number
---@field criteriaKey? string Payload field name for unique criteria (e.g. "instance", "zone")
---@field subCategory? number For type "meta", count completed achievements in this subCategory
---@field reset? "match" Reset progress when a match starts (e.g., battleground-only)

---@class AchievementFailCondition
---@field event string
---@field conditions? table<string, any>

---@class Achievement
---@field id number
---@field name string
---@field description string
---@field points number
---@field category number
---@field subCategory? number
---@field icon number|string
---@field cadence number
---@field startWeek? number
---@field endWeek? number
---@field trigger AchievementTrigger
---@field progress? AchievementProgress
---@field failCondition? AchievementFailCondition

---@class AchievementUtils
local achievementUtils = {
    ---@type table<number, AchievementCategory>
    categories = {},
    ---@type table<number, AchievementSubCategory>
    subCategories = {},
    ---@type table<number, Achievement>
    achievements = {},
    ---@type table<string, Achievement[]>
    achievementsByEvent = {},
    ---@type table<string, Achievement[]>
    achievementsByFailEvent = {},
    ---@type number
    currentWeek = 1,
}
Private.AchievementUtils = achievementUtils

-------------------------------------------------------------------------------
-- Category Registration
-------------------------------------------------------------------------------

---Register categories and subcategories
---@param categories AchievementCategory[]
function achievementUtils:RegisterCategories(categories)
    local Data = Reckoning and Reckoning.Achievements

    for _, category in ipairs(categories) do
        -- Store in our lookup
        self.categories[category.id] = category

        -- Register with UI system
        if Data then
            Data:RegisterCategory(category.id, category.name, nil, category.id)
        end

        -- Register subcategories
        if category.subCategories then
            for _, subCat in ipairs(category.subCategories) do
                self.subCategories[subCat.id] = subCat
                self.subCategories[subCat.id].parentId = category.id

                if Data then
                    Data:RegisterCategory(subCat.id, subCat.name, category.id, subCat.id)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Achievement Registration
-------------------------------------------------------------------------------

---Register achievements
---@param achievements Achievement[]
function achievementUtils:RegisterAchievements(achievements)
    local Data = Reckoning and Reckoning.Achievements

    for _, achievement in ipairs(achievements) do
        -- Validate required fields
        assert(achievement.id, "Achievement missing required field: id")
        assert(achievement.name, "Achievement missing required field: name")
        assert(achievement.description, "Achievement missing required field: description")
        assert(achievement.points, "Achievement missing required field: points")
        assert(achievement.category, "Achievement missing required field: category")
        assert(achievement.icon, "Achievement missing required field: icon")
        assert(achievement.cadence, "Achievement missing required field: cadence")
        assert(achievement.trigger, "Achievement missing required field: trigger")
        assert(achievement.trigger.event, "Achievement trigger missing required field: event")

        -- Default startWeek to 1
        achievement.startWeek = achievement.startWeek or 1

        -- Store achievement
        self.achievements[achievement.id] = achievement

        -- Index by trigger event
        local event = achievement.trigger.event
        self.achievementsByEvent[event] = self.achievementsByEvent[event] or {}
        table.insert(self.achievementsByEvent[event], achievement)

        -- Index by fail condition event
        if achievement.failCondition and achievement.failCondition.event then
            local failEvent = achievement.failCondition.event
            self.achievementsByFailEvent[failEvent] = self.achievementsByFailEvent[failEvent] or {}
            table.insert(self.achievementsByFailEvent[failEvent], achievement)
        end

        -- Determine categoryId for UI (use subCategory if specified, else category)
        local categoryId = achievement.subCategory or achievement.category

        -- Register with UI system
        if Data then
            Data:RegisterAchievement(achievement.id, categoryId, {
                name = achievement.name,
                description = achievement.description,
                points = achievement.points,
                icon = achievement.icon,
                current = 0,
                total = achievement.progress and achievement.progress.required or 1,
                completed = false,
                startWeek = achievement.startWeek,
                cadence = achievement.cadence,
            })
        end
    end
end

-------------------------------------------------------------------------------
-- Achievement Queries
-------------------------------------------------------------------------------

---Get achievement by ID
---@param id number
---@return Achievement|nil
function achievementUtils:GetAchievement(id)
    return self.achievements[id]
end

---Get all achievements for an event
---@param event string
---@return Achievement[]
function achievementUtils:GetAchievementsForEvent(event)
    return self.achievementsByEvent[event] or {}
end

---Get all achievements with a specific fail event
---@param event string
---@return Achievement[]
function achievementUtils:GetAchievementsForFailEvent(event)
    return self.achievementsByFailEvent[event] or {}
end

---Get all achievement IDs in a subCategory (for meta progress)
---@param subCategory number
---@return number[]
function achievementUtils:GetAchievementIdsInSubCategory(subCategory)
    local ids = {}
    for id, achievement in pairs(self.achievements) do
        if achievement.subCategory == subCategory then
            table.insert(ids, id)
        end
    end
    return ids
end

---Check if an achievement is available based on current week
---Week 0 (pre-launch) is treated as unavailable for all time-limited achievements.
---If endWeek is set (OneTime cadence), achievement is only available when currentWeek is in [startWeek, endWeek].
---@param achievement Achievement
---@return boolean
function achievementUtils:IsAchievementAvailable(achievement)
    local week = self.currentWeek
    local startWeek = achievement.startWeek or 1

    -- Pre-launch: no time-limited availability
    if week <= 0 then
        return false
    end

    if week < startWeek then
        return false
    end

    local endWeek = achievement.endWeek
    if endWeek and week > endWeek then
        return false
    end

    return true
end

---Set the current server week
---@param week number
function achievementUtils:SetCurrentWeek(week)
    self.currentWeek = week
end

---Get current server week
---@return number
function achievementUtils:GetCurrentWeek()
    return self.currentWeek
end