-------------------------------------------------------------------------------
-- Achievement Micro Button
-------------------------------------------------------------------------------

-- Global function for keybind
function ToggleReckoningAchievementFrame()
    ReckoningAchievementFrame:SetShown(not ReckoningAchievementFrame:IsShown())
end

function ReckoningAchievementMicroButton_OnLoad(self)
    self:RegisterEvent("UPDATE_BINDINGS")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.tooltipText = MicroButtonTooltipText("Achievements", "TOGGLEACHIEVEMENT")
    self.newbieText = NEWBIE_TOOLTIP_ACHIEVEMENT

    LoadMicroButtonTextures(self, "Achievement");
    ReckoningAchievementMicroButton:SetPoint("TOPLEFT", HelpMicroButton, "TOPRIGHT", -3, 0)
    ReckoningAchievementMicroButton:SetPoint("BOTTOMLEFT", HelpMicroButton, "BOTTOMRIGHT", -3, 0)
end

function ReckoningAchievementMicroButton_OnEvent(self, event, ...)
    if event == "UPDATE_BINDINGS" then
        self.tooltipText = MicroButtonTooltipText("Achievements", "TOGGLEACHIEVEMENT")
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateMicroButtons()
    end
end

function ReckoningAchievementMicroButton_SetPushed()
    ReckoningAchievementMicroButton:SetButtonState("PUSHED", true)
end

function ReckoningAchievementMicroButton_SetNormal()
    ReckoningAchievementMicroButton:SetButtonState("NORMAL")
end

function ReckoningAchievementMicroButton_UpdateIcon()
    if ReckoningAchievementFrame and ReckoningAchievementFrame:IsShown() then
        ReckoningAchievementMicroButton_SetPushed()
    else
        ReckoningAchievementMicroButton_SetNormal()
    end
end
