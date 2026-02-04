local Private = select(2, ...)

local Reckoning_Achievements = Reckoning.Achievements
local Data = Reckoning_Achievements

local constants = Private.constants

-------------------------------------------------------------------------------
-- Achievement Alert (Toast) System
-------------------------------------------------------------------------------

local alertQueue = {}
local isShowing = false

function ReckoningAchievementAlert_OnLoad(self)
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    self.animatingIn = false
    self.animatingOut = false
    self.fadeTimer = nil
    self.hideTimer = nil
    self.isPaused = false
    self.remainingTime = 0
end

function ReckoningAchievementAlert_OnClick(self, button)
    if button == "RightButton" then
        -- Right-click: Dismiss immediately
        if self.fadeTimer then
            self.fadeTimer:Cancel()
        end
        if self.hideTimer then
            self.hideTimer:Cancel()
        end
        self:Hide()
        self:SetAlpha(1)
        self.glow:Hide()
        self.shine:Hide()
        isShowing = false
        ReckoningAchievementAlert_ShowNext()
    elseif self.achievementId then
        -- Left-click: Open achievement frame and jump to achievement
        if not ReckoningAchievementFrame:IsShown() then
            ReckoningAchievementFrame:Show()
        end
        ReckoningAchievementFrame_SelectAchievement(self.achievementId)
    end
end

function ReckoningAchievementAlert_OnEnter(self)
    -- Pause the fade timer on hover
    if self.fadeTimer and not self.isPaused then
        self.isPaused = true
        self.fadeTimer:Cancel()
        -- Reset to full opacity
        UIFrameFade(self, { mode = "IN", timeToFade = 0.2, startAlpha = self:GetAlpha(), endAlpha = 1.0 })
    end
end

function ReckoningAchievementAlert_OnLeave(self)
    -- Resume the fade timer on leave
    if self.isPaused then
        self.isPaused = false
        -- Start immediate fade out
        self.fadeTimer = C_Timer.NewTimer(0.5, function()
            if not self:IsVisible() then
                isShowing = false
                ReckoningAchievementAlert_ShowNext()
                return
            end

            -- Fade out over 1 second
            UIFrameFadeOut(self, 1.0, 1, 0)

            -- Hide completely and show next after fade
            self.hideTimer = C_Timer.NewTimer(1.1, function()
                self:Hide()
                self:SetAlpha(1)
                self.glow:Hide()
                self.shine:Hide()
                isShowing = false
                ReckoningAchievementAlert_ShowNext()
            end)
        end)
    end
end

local function AnimateAlert(frame, onComplete)
    -- Show frame immediately
    frame:SetAlpha(1)
    frame:Show()
    frame.glow:Hide()
    frame.shine:Hide()

    -- Show glow with fade animation
    frame.glow:SetAlpha(1)
    frame.glow:Show()
    UIFrameFadeOut(frame.glow, 0.7, 1, 0)

    -- Show shine
    frame.shine:SetAlpha(1)
    frame.shine:Show()

    -- Schedule hide shine after 1 second
    C_Timer.NewTimer(1.0, function()
        if frame.shine then
            frame.shine:Hide()
        end
    end)

    -- Schedule fade out after 5 seconds
    frame.isPaused = false
    frame.fadeTimer = C_Timer.NewTimer(5.0, function()
        if not frame:IsVisible() or frame.isPaused then
            return
        end

        -- Fade out over 1 second
        UIFrameFadeOut(frame, 1.0, 1, 0)

        -- Hide completely and show next after fade
        frame.hideTimer = C_Timer.NewTimer(1.1, function()
            frame:Hide()
            frame:SetAlpha(1)
            frame.glow:Hide()
            frame.shine:Hide()
            isShowing = false
            if onComplete then
                onComplete()
            end
            ReckoningAchievementAlert_ShowNext()
        end)
    end)
end

function ReckoningAchievementAlert_Show(achievementId)
    local achievement = Data._achievements[achievementId]
    if not achievement then
        return
    end

    -- Queue the alert
    table.insert(alertQueue, achievementId)

    -- Show if not currently showing
    if not isShowing then
        ReckoningAchievementAlert_ShowNext()
    end
end

function ReckoningAchievementAlert_ShowNext()
    if #alertQueue == 0 or isShowing then
        return
    end

    local achievementId = table.remove(alertQueue, 1)
    local achievement = Data._achievements[achievementId]
    if not achievement then
        ReckoningAchievementAlert_ShowNext()
        return
    end

    isShowing = true

    local frame = ReckoningAchievementAlertFrame
    frame.achievementId = achievementId

    -- Set up the alert
    frame.Name:SetText(achievement.name or "Unknown Achievement")
    frame.Icon.Texture:SetTexture(achievement.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    frame.Shield.Points:SetText(achievement.points or 0)
    frame.Unlocked:SetText("ACHIEVEMENT UNLOCKED")

    -- Play achievement earned sound (12891 is the achievement earned sound)
    PlaySoundFile(constants.MEDIA.SOUNDS.ACHIEVEMENT_EARNED)

    -- Animate
    AnimateAlert(frame)
end

-------------------------------------------------------------------------------
-- Debug Command
-------------------------------------------------------------------------------

SLASH_RECKTEST1 = "/recktest"
SlashCmdList["RECKTEST"] = function(msg)
    -- Get first achievement for testing
    local testAchievementId = nil
    for id, achievement in pairs(Data._achievements) do
        testAchievementId = id
        break
    end

    if testAchievementId then
        ReckoningAchievementAlert_Show(testAchievementId)
        print("Reckoning: Showing test achievement toast for achievement ID " .. testAchievementId)
    else
        print("Reckoning: No achievements found for testing")
    end
end
