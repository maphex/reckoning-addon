-------------------------------------------------------------------------------
-- Key Bindings
-------------------------------------------------------------------------------

-- Called by Bindings.xml (Key Bindings). Must be global.
function Reckoning_ToggleAchievementsBinding()
    if type(ReckoningAchievementFrame_Toggle) == "function" then
        ReckoningAchievementFrame_Toggle()
    end
end
