# RasuForge-Settings

Helpers for building Settings UI in World of Warcraft (Retail) using Blizzard's modern Settings API. It wraps common patterns so you can quickly register a category and add controls like checkboxes, sliders, dropdowns, headers, buttons, custom panels, and subcategories with minimal boilerplate.

- Top-level and nested settings categories
- Ready-to-use element creators: Checkbox, Slider, Dropdown, Button, Header
- Custom panel areas inside your category (for complex UIs)
- Optional search tags for better discoverability in Settings
- Open programmatically to your category or a specific element

## Requirements

- LibStub (bundled in most addon lib folders)
- Load order must ensure this library is loaded before your addon accesses it

## Installation

You can vendor the library or use it as a Git submodule. Example folder structure used by many addons:

```
YourAddon/
	YourAddon.toc
	Libs/
		LibStub/LibStub.lua
		RasuForge-Settings/
			lib.xml
			RasuForge-Settings.lua
		libs.xml
```

1) Add/keep an aggregate `libs.xml` that includes this library:

```xml
<!-- Libs/libs.xml -->
<Ui xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.blizzard.com/wow/ui/" xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\\FrameXML\\UI.xsd">
	<Script file="LibStub/LibStub.lua"/>
	<Include file="RasuForge-Settings/lib.xml"/>
</Ui>
```

2) Reference `Libs/libs.xml` from your TOC so the library loads before your addon code:

```
Libs/libs.xml
YourAddon.lua
```

3) Using as a Git submodule (recommended):

```bash
# from your addon repo root
git submodule add https://github.com/Larsj02/RasuForge-Settings Libs/RasuForge-Settings
```

If you use CI to package releases, ensure the checkout fetches submodules (for GitHub Actions):

```yaml
- uses: actions/checkout@v4
	with:
		fetch-depth: 0
		submodules: recursive
```

## Quick Start

```lua
-- Get the library
local RFSettings = LibStub("RasuForge-Settings")

-- Create a top-level category in Settings
local category = RFSettings:NewCategory("My Addon")

-- SavedVariables helpers
local function getEnabled() return MyAddonDB.enabled == true end
local function setEnabled(v) MyAddonDB.enabled = v and true or false end

-- Checkbox
category:CreateCheckbox(
	"MYADDON_ENABLED",           -- variable key (unique in this category)
	"boolean",                   -- SettingsVariableType: "boolean"|"number"|"string"
	"Enable My Addon",           -- display name
	false,                        -- default value
	getEnabled,                   -- getter (reads from your DB)
	setEnabled,                   -- setter (writes to your DB)
	"Turns the addon on or off"  -- tooltip (string or function returning string)
)

-- Slider
category:CreateSlider(
	"MYADDON_SPEED",
	"number",
	"Speed",
	5,
	function() return MyAddonDB.speed or 5 end,
	function(v) MyAddonDB.speed = v end,
	1, 10, 1,                      -- min, max, step
	"How fast should it go?"
)

-- Dropdown (options may be a static table or a function returning entries)
local options = {
	{ label = "Normal", value = "normal", text = "Normal", tooltip = "Normal Option" },
	{ label = "Hard",   value = "hard",   text = "Hard",   tooltip = "Hard Option"   },
}
category:CreateDropdown(
	"MYADDON_MODE",
	"string",
	"Mode",
	"normal",
	function() return MyAddonDB.mode or "normal" end,
	function(v) MyAddonDB.mode = v end,
	options,
	"Choose how the addon behaves"
)

-- Button
category:CreateButton(
	"Reload UI",                     -- title
	"Reload",                        -- button text
	function() C_UI.Reload() end,
	"Reload the User Interface",
	true                              -- add search tags
)

-- Section header
category:CreateHeader("Advanced Settings", "Misc advanced options", {"advanced", "pro"})

-- Optional: open Settings to your category (or a specific element name)
-- category:Open("MYADDON_ENABLED")
```

## Subcategories

You can nest subcategories under your main category. Use a canvas frame for more complex layouts or omit it for a simple vertical list.

```lua
local sub = category:CreateSubCategory("Profiles") -- or: CreateSubCategory("Profiles", SomeFrame)
sub:CreateCheckbox("USE_ACCOUNT_WIDE", "boolean", "Account-wide settings", false,
	function() return MyAddonDB.accountWide end,
	function(v) MyAddonDB.accountWide = v end,
	"Apply settings across characters"
)
```

## Custom Panels inside a Category

Create a panel area that you control completely (great for advanced UI). The library wires in defaulting events so you can respond when the user clicks "Restore Defaults".

```lua
local panel = category:CreatePanel(
	"advanced-panel",                                -- identifier for your panel
	function(frame, data)                             -- onInit(frame, data)
		-- Build your custom UI inside "frame"
		-- Example: local child = CreateFrame("Frame", nil, frame)
	end,
	{ any = "data you want" },                        -- optional data passed to onInit
	nil,                                              -- template (defaults to "BackdropTemplate")
	300,                                              -- height
	function() print("Defaults applied for this category") end, -- onDefaulted
	{"advanced", "panel"}                             -- search tags
)
```

## API Reference (short)

- RFSettings:NewCategory(name[, canvasFrame]) -> RF-Settings
	- Registers and returns a top-level settings category for your addon. If you pass a canvas frame the category uses a canvas layout, otherwise vertical layout.

- RF-Settings methods
	- CreateCheckbox(variable, variableType, name, defaultValue, getValue, setValue[, tooltip])
	- CreateSlider(variable, variableType, name, defaultValue, getValue, setValue[, min, max, step, tooltip])
	- CreateDropdown(variable, variableType, name, defaultValue, getValue, setValue, options[, tooltip])
		- options: table or function returning a list of entries like `{ label = string, value = any, text = string }`
	- CreateButton(name, buttonText, onClick[, tooltip, addSearchTags])
	- CreateHeader(name[, tooltip, searchTags])
	- CreatePanel(identifier, onInit[, data, template, height, onDefaulted, searchTags]) -> panelInitializer
		- panelInitializer has: `SetHeight(number)`, `SetOnInit(fn)`, `SetOnDefaulted(fn)`
	- CreateSubCategory(name[, canvasFrame]) -> RF-Settings
	- AddInitializer(initializer)
	- Open([scrollToElementName])

- Types
	- SettingsVariableType: "boolean" | "number" | "string"

- Versioning
	- The library registers via `LibStub:NewLibrary("RasuForge-Settings", 100)`.
	- Consumers retrieve the instance with `LibStub("RasuForge-Settings")` (no version needed).

## Notes and Tips

- Your getter/setter are the source of truth; Blizzard Settings will call these to read/write values. This means you can store your data anywhere (SavedVariables, RasuForge-Database, etc.).
- Tooltips accept either a string or a function returning a string, which is handy if the help text changes dynamically.
- The library listens to `Settings.Defaulted` and `Settings.CategoryDefaulted` and triggers your `onDefaulted` callback for panels automatically.

## License

MIT — © 2025 Larsj02. See the root addon license for details.

## Links

- Source: https://github.com/Larsj02/RasuForge-Settings
- Example usage: see Legion Remix Helper for a practical integration pattern.