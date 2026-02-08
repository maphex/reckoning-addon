-------------------------------------------------------------------------------
-- Y Key Binding (hardcoded, no customization)
-------------------------------------------------------------------------------

-- Create a hidden button that triggers the toggle
local button = CreateFrame("Button", "ReckoningYKeyButton", UIParent, "SecureActionButtonTemplate")
button:Hide()
button:SetScript("OnClick", function()
    if ToggleReckoningAchievementFrame then
        ToggleReckoningAchievementFrame()
    end
end)

-- Set Y key to trigger this button on login
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    -- This works globally without Bindings.xml
    SetBindingClick("Y", "ReckoningYKeyButton")
end)
