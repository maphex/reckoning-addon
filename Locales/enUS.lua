---@class AddonPrivate
local Private = select(2, ...)

local locales = Private.Locales or {}
Private.Locales = locales
local L = {
    -- UI/Components/Dropdown.lua
    ["Components.Dropdown.SelectOption"] = "Select an option",

    -- Utils/CommandUtils.lua
    ["CommandUtils.UnknownCommand"] =
[[Unknown Command!
Usage: /R or /Reckoning <subCommand>
Subcommands:
    achievements (a) - Open the Achievements tab.
    settings (s) - Open the settings menu.
Example: /R s]],
    ["CommandUtils.CollectionsCommand"] = "achievements",
    ["CommandUtils.CollectionsCommandShort"] = "a",
    ["CommandUtils.SettingsCommand"] = "settings",
    ["CommandUtils.SettingsCommandShort"] = "s",

    -- Utils/UpdateUtils.lua
    ["UpdateUtils.PatchNotesMessage"] = "Your Version changed from %s to Version %s.",
    ["UpdateUtils.NilVersion"] = "N/A",

    -- Utils/UXUtils.lua
    ["UXUtils.SettingsCategoryPrefix"] = "General Settings",
    ["UXUtils.SettingsCategoryTooltip"] = "General Addon Settings",
}
locales["enUS"] = L
