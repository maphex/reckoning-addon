-------------------------------------------------------------------------------
-- Minimap Button
-------------------------------------------------------------------------------

-- Global function for keybind
function ToggleReckoningAchievementFrame()
    if ReckoningAchievementFrame_Toggle then
        ReckoningAchievementFrame_Toggle()
    end
end

---@class AddonPrivate
local Private = select(2, ...)

---@class MinimapButton
local MinimapButton = {}
Private.MinimapButton = MinimapButton

local addon = nil
local LDB = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub("LibDBIcon-1.0", true)

function MinimapButton:Init()
    addon = Private.Addon

    if not LDB or not LDBIcon then
        addon:Print("Error: Minimap button libraries not loaded")
        return
    end

    -- Get or initialize saved variables for minimap button
    if not addon.Database.minimap then
        addon.Database.minimap = {
            hide = false,
            minimapPos = 220,
            lock = false,
        }
    end

    -- Create LibDataBroker data object
    local dataObj = LDB:NewDataObject("Reckoning", {
        type = "launcher",
        icon = "Interface\\AddOns\\Reckoning\\Media\\Textures\\logo",
        OnClick = function()
            self:OnClick()
        end,
        OnTooltipShow = function(tooltip)
            self:OnTooltipShow(tooltip)
        end,
    })

    -- Register with LibDBIcon
    LDBIcon:Register("Reckoning", dataObj, addon.Database.minimap)

    -- Store reference
    self.icon = LDBIcon
end

function MinimapButton:OnClick()
    -- Toggle achievement frame using proper toggle function
    if ReckoningAchievementFrame_Toggle then
        ReckoningAchievementFrame_Toggle()
    end
end

function MinimapButton:OnTooltipShow(tooltip)
    if not tooltip then return end

    tooltip:AddLine("|cff00ff00Reckoning|r")
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffffffClick|r to toggle achievements")
end

function MinimapButton:Show()
    if self.icon then
        self.icon:Show("Reckoning")
    end
end

function MinimapButton:Hide()
    if self.icon then
        self.icon:Hide("Reckoning")
    end
end

function MinimapButton:Toggle()
    if self.icon then
        if addon.Database.minimap.hide then
            self:Show()
            addon.Database.minimap.hide = false
        else
            self:Hide()
            addon.Database.minimap.hide = true
        end
    end
end
