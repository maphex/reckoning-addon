---@type AddonPrivate
local Private = select(2, ...)
local aUtils = Private.AchievementUtils
local Enums = Private.Enums
local const = Private.constants

local OUTLAND_ZONES = {
	["Hellfire Peninsula"] = true,
	["Zangarmarsh"] = true,
	["Terokkar Forest"] = true,
	["Nagrand"] = true,
	["Blade's Edge Mountains"] = true,
	["Netherstorm"] = true,
	["Shadowmoon Valley"] = true,
}

-------------------------------------------------------------------------------
-- Category Registration
-- Categories based on Reckoning.csv structure
-------------------------------------------------------------------------------

aUtils:RegisterCategories({
	{
		id = 1,
		name = "Dungeons",
		subCategories = {
			{ id = 10, name = "Heroic" },
			{ id = 11, name = "Normal" }
		}
	},
	{
		id = 2,
		name = "Raids",
		subCategories = {
			{ id = 20, name = "Karazhan" },
			{ id = 21, name = "Tier 4" },
			{ id = 22, name = "Tier 5" },
			{ id = 23, name = "Tier 6" }
		}
	},
	{
		id = 3,
		name = "PvP",
		subCategories = {
			{ id = 30, name = "Battlegrounds" },
			{ id = 31, name = "Arena" },
			{ id = 32, name = "World PvP" }
		}
	},
	{
		id = 4,
		name = "Professions",
		subCategories = {
			{ id = 40, name = "Crafting" },
			{ id = 41, name = "Gathering" }
		}
	},
	{
		id = 5,
		name = "Milestones",
		subCategories = {
			{ id = 50, name = "Quests" },
			{ id = 51, name = "Reputation" },
			{ id = 52, name = "Exploration" }
		}
	},
	{
		id = 6,
		name = "Open World",
		subCategories = {
			{ id = 60, name = "Weekly" }
		}
	},
})

-------------------------------------------------------------------------------
-- Achievement Registration
-------------------------------------------------------------------------------

---@type Achievement[]
local ACHIEVEMENTS = {
	-------------------------------------------------------------------------------
	-- DUNGEON/HEROIC ACHIEVEMENTS (Category 1, SubCategory 10)
	-------------------------------------------------------------------------------
	{
		id = 1001,
		name = "Under Pressure",
		description = "Defeat the Black Stalker in Underbog on Heroic Difficulty in 25 minutes",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 134530,
		cadence = Enums.Cadence.AllTime,
		startWeek = 1,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = {
				instance = "The Underbog",
				difficulty = Enums.Difficulty.Heroic,
				duration = function(d) return d <= 1500 end
			}
		}
	},
	{
		id = 1002,
		name = "Clean Water Act",
		description = "Defeat Hydromancer Thespia in Heroic Steamvault without anyone being hit by Lightning Cloud",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 136050,
		cadence = Enums.Cadence.AllTime,
		startWeek = 1,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Hydromancer Thespia",
				instance = "The Steamvault",
				difficulty = Enums.Difficulty.Heroic
			}
		},
		failCondition = {
			event = "DUNGEON_MECHANIC_FAILED",
			conditions = { mechanicName = "Lightning Cloud" }
		}
	},
	{
		id = 1003,
		name = "No Crypt for me",
		description = "Defeat Exarch Maladaar in heroic Auchenai Crypts without anyone dying the whole Dungeon",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 135383,
		cadence = Enums.Cadence.AllTime,
		startWeek = 1,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = {
				instanceName = "Auchenai Crypts",
				difficulty = Enums.Difficulty.Heroic,
				totalDeaths = 0
			}
		}
	},
	{
		id = 1004,
		name = "Anti-Magic Zone",
		description = "Defeat Pandemonius in Heroic Mana tombs without reflecting any damage",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 136221,
		cadence = Enums.Cadence.AllTime,
		startWeek = 1,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Pandemonius",
				instance = "Mana-Tombs",
				difficulty = Enums.Difficulty.Heroic
			}
		},
		failCondition = {
			event = "DUNGEON_MECHANIC_FAILED",
			conditions = { mechanicName = "Dark Shell" }
		}
	},
	{
		id = 1005,
		name = "Prison Riot",
		description = "Kill Warchief Kargath Bladefist in Heroic Shattered halls without anyone dying to Blade Dance",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 134530,
		cadence = Enums.Cadence.AllTime,
		startWeek = 1,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Warchief Kargath Bladefist",
				instance = "The Shattered Halls",
				difficulty = Enums.Difficulty.Heroic
			}
		},
		failCondition = {
			event = "DUNGEON_MECHANIC_FAILED",
			conditions = { mechanicName = "Blade Dance" }
		}
	},
	{
		id = 1006,
		name = "Syth Lord",
		description = "Defeat Darkweaver Syth in Heroic Sethekk Halls within 70 seconds of starting the encounter",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 132598,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Darkweaver Syth",
				instance = "Sethekk Halls",
				difficulty = Enums.Difficulty.Heroic,
				duration = function(d) return d <= 70 end
			}
		}
	},
	{
		id = 1007,
		name = "Quag is a Hag",
		description = "Defeat Quagmirran in Heroic Slave pens within 40 Seconds of starting the encounter",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 134126,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Quagmirran",
				instance = "The Slave Pens",
				difficulty = Enums.Difficulty.Heroic,
				duration = function(d) return d <= 40 end
			}
		}
	},
	{
		id = 1008,
		name = "Not Today, Herald",
		description = "Defeat Nazan & Vazruden the Herald in Heroic Hellfire ramparts in 20 minutes of starting the dungeon",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 133839,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = {
				instance = "Hellfire Ramparts",
				difficulty = Enums.Difficulty.Heroic,
				duration = function(d) return d <= 1200 end
			}
		}
	},
	{
		id = 1009,
		name = "Chrono Champion",
		description = "Defeat Aeonus in Heroic Black Morass with Medivh's Shield at 100%",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 135226,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Aeonus",
				instance = "The Black Morass",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1010,
		name = "Badge Runner",
		description = "Collect 50 Badges of Justice",
		points = 15,
		category = 1,
		subCategory = 10,
		icon = 135884,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BADGE_EARNED",
			conditions = { badgeType = "Badge of Justice" }
		},
		progress = { type = "count", required = 50 }
	},
	{
		id = 1011,
		name = "Energy Efficient",
		description = "Defeat Mechano-Lord Capacitus in Heroic Mechanar without anyone triggering a polarity explosion",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 135737,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Mechano-Lord Capacitus",
				instance = "The Mechanar",
				difficulty = Enums.Difficulty.Heroic
			}
		},
		failCondition = {
			event = "DUNGEON_MECHANIC_FAILED",
			conditions = { mechanicName = "Polarity Shift" }
		}
	},
	{
		id = 1012,
		name = "Weed Whacker",
		description = "Defeat Laj in Heroic Botanica without killing any Thorn Flayers or Thorn Lashers",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 133941,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Laj",
				instance = "The Botanica",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1013,
		name = "Into the Tombs",
		description = "Defeat Nexus-Prince Shaffar in Heroic Mana tombs without killing any Ethereal Beacons",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 136170,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Nexus-Prince Shaffar",
				instance = "Mana-Tombs",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1014,
		name = "Big Boom",
		description = "Kill Murmur in heroic Shadow Labyrinth without anyone being hit by Sonic Boom",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 136099,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Murmur",
				instance = "Shadow Labyrinth",
				difficulty = Enums.Difficulty.Heroic
			}
		},
		failCondition = {
			event = "DUNGEON_MECHANIC_FAILED",
			conditions = { mechanicName = "Sonic Boom" }
		}
	},
	{
		id = 1015,
		name = "Hero of the Storm",
		description = "Complete 75 Heroic Dungeons",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 136111,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = { difficulty = Enums.Difficulty.Heroic }
		},
		progress = { type = "count", required = 75 }
	},
	{
		id = 1016,
		name = "Badge Collector",
		description = "Collect 150 Badges of Justice",
		points = 25,
		category = 1,
		subCategory = 10,
		icon = 135979,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BADGE_EARNED",
			conditions = { badgeType = "Badge of Justice" }
		},
		progress = { type = "count", required = 150 }
	},
	{
		id = 1017,
		name = "Repeat and Rewind",
		description = "Complete any Heroic 5 times",
		points = 10,
		category = 1,
		subCategory = 10,
		icon = 132770,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = { difficulty = Enums.Difficulty.Heroic }
		},
		progress = { type = "count", required = 5 }
	},
	{
		id = 1018,
		name = "No One Dies Tonight",
		description = "Finish any Heroic without a single Party Death",
		points = 15,
		category = 1,
		subCategory = 10,
		icon = 135928,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = {
				difficulty = Enums.Difficulty.Heroic,
				totalDeaths = 0
			}
		}
	},
	{
		id = 1019,
		name = "Time is Against Us",
		description = "Collect the Key of Time",
		points = 10,
		category = 1,
		subCategory = 10,
		icon = 134238,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "KEY_OBTAINED",
			conditions = { keyName = "Key of Time" }
		}
	},
	{
		id = 1020,
		name = "Drop it Lower",
		description = "Collect the Auchenai Key",
		points = 10,
		category = 1,
		subCategory = 10,
		icon = 134245,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "KEY_OBTAINED",
			conditions = { keyName = "Auchenai Key" }
		}
	},
	{
		id = 1021,
		name = "Warping the Mind",
		description = "Collect the Warpforged Key",
		points = 10,
		category = 1,
		subCategory = 10,
		icon = 134244,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "KEY_OBTAINED",
			conditions = { keyName = "Warpforged Key" }
		}
	},
	{
		id = 1022,
		name = "Shattered Hopes",
		description = "Collect the Shattered Halls Key",
		points = 10,
		category = 1,
		subCategory = 10,
		icon = 134240,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "KEY_OBTAINED",
			conditions = { keyName = "Shattered Halls Key" }
		}
	},
	{
		id = 1023,
		name = "Key to Hell",
		description = "Collect the Flamewrought Key",
		points = 10,
		category = 1,
		subCategory = 10,
		icon = 134247,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "KEY_OBTAINED",
			conditions = { keyName = "Flamewrought Key" }
		}
	},
	{
		id = 1024,
		name = "Key down Under",
		description = "Collect the Reservoir Key",
		points = 10,
		category = 1,
		subCategory = 10,
		icon = 134247,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "KEY_OBTAINED",
			conditions = { keyName = "Reservoir Key" }
		}
	},
	{
		id = 1025,
		name = "Dungeon Master",
		description = "Complete every Dungeon on Normal",
		points = 15,
		category = 1,
		subCategory = 11,
		icon = 135289,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = { difficulty = Enums.Difficulty.Normal }
		},
		progress = {
			type = "criteria",
			required = 16
		}
	},
	{
		id = 1026,
		name = "Heroic Master",
		description = "Complete every Heroic Dungeon",
		points = 60,
		category = 1,
		subCategory = 10,
		icon = 135331,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = { difficulty = Enums.Difficulty.Heroic }
		},
		progress = {
			type = "criteria",
			required = 16
		}
	},
	{
		id = 1027,
		name = "Undying Arcatraz",
		description = "Defeat Heroic Arcatraz with 0 deaths",
		points = 20,
		category = 1,
		subCategory = 10,
		icon = 135752,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = {
				instance = "The Arcatraz",
				difficulty = Enums.Difficulty.Heroic,
				totalDeaths = 0
			}
		}
	},
	-- One-time Heroic achievements (time-limited)
	{
		id = 1028,
		name = "Shadow Lab Sweep",
		description = "Defeat Murmur in the Shadow Labyrinth on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 135863,
		cadence = Enums.Cadence.OneTime,
		startWeek = 1,
		endWeek = 2,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Murmur",
				instance = "Shadow Labyrinth",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1029,
		name = "Steam Runner",
		description = "Defeat Warlord Kalithresh in the Steamvaults on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 134301,
		cadence = Enums.Cadence.OneTime,
		startWeek = 2,
		endWeek = 3,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Warlord Kalithresh",
				instance = "The Steamvault",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1030,
		name = "Pen Pals",
		description = "Defeat Quagmirran in the Slave pens on heroic difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 134300,
		cadence = Enums.Cadence.OneTime,
		startWeek = 2,
		endWeek = 3,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Quagmirran",
				instance = "The Slave Pens",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1031,
		name = "Shattered Resolve",
		description = "Defeat Warchief Kargath Bladefist in the shattered halls on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 134170,
		cadence = Enums.Cadence.OneTime,
		startWeek = 3,
		endWeek = 4,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Warchief Kargath Bladefist",
				instance = "The Shattered Halls",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1032,
		name = "Respect the Mechanar",
		description = "Defeat Pathaleon the Calculator in the Mechanar on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 133002,
		cadence = Enums.Cadence.OneTime,
		startWeek = 3,
		endWeek = 4,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Pathaleon the Calculator",
				instance = "The Mechanar",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1033,
		name = "Breaking the Chains",
		description = "Defeat Keli'dan the Breaker in Blood Furnace on Heroic Difficulty",
		points = 50,
		category = 1,
		subCategory = 10,
		icon = 135794,
		cadence = Enums.Cadence.OneTime,
		startWeek = 4,
		endWeek = 5,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Keli'dan the Breaker",
				instance = "The Blood Furnace",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1034,
		name = "I Need More Mana",
		description = "Defeat Nexus-Prince Shaffar in Mana tombs on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 135730,
		cadence = Enums.Cadence.OneTime,
		startWeek = 4,
		endWeek = 5,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Nexus-Prince Shaffar",
				instance = "Mana-Tombs",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1035,
		name = "Dark Portal Escape",
		description = "Defeat Aeonus in Black Morass on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 134234,
		cadence = Enums.Cadence.OneTime,
		startWeek = 5,
		endWeek = 6,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Aeonus",
				instance = "The Black Morass",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1036,
		name = "Birds of a Feather",
		description = "Defeat Talon King Ikiss in Sethekk Halls on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 133707,
		cadence = Enums.Cadence.OneTime,
		startWeek = 5,
		endWeek = 6,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Talon King Ikiss",
				instance = "Sethekk Halls",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1037,
		name = "Botanica Boom",
		description = "Defeat Warp Splinter in the Botanica on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 134183,
		cadence = Enums.Cadence.OneTime,
		startWeek = 6,
		endWeek = 7,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Warp Splinter",
				instance = "The Botanica",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1038,
		name = "Back to the Future",
		description = "Defeat Epoch Hunter in Old Hillsbrad Foothills on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 136106,
		cadence = Enums.Cadence.OneTime,
		startWeek = 7,
		endWeek = 8,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Epoch Hunter",
				instance = "Old Hillsbrad Foothills",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1039,
		name = "Arcatraz Breakout",
		description = "Defeat Harbinger Skyriss in The Arcatraz on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 135731,
		cadence = Enums.Cadence.OneTime,
		startWeek = 8,
		endWeek = 9,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Harbinger Skyriss",
				instance = "The Arcatraz",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1040,
		name = "Restless Spirits",
		description = "Defeat Exarch Maladaar in Auchenai Crypts on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 135983,
		cadence = Enums.Cadence.OneTime,
		startWeek = 9,
		endWeek = 10,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Exarch Maladaar",
				instance = "Auchenai Crypts",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1041,
		name = "Swamp Thing",
		description = "Defeat the Black stalker in The underbog on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 134530,
		cadence = Enums.Cadence.OneTime,
		startWeek = 10,
		endWeek = 11,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "The Black Stalker",
				instance = "The Underbog",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},
	{
		id = 1042,
		name = "Through the Fire and the Fe",
		description = "Defeat Nazan in Hellfire Ramparts on Heroic Difficulty",
		points = 40,
		category = 1,
		subCategory = 10,
		icon = 135820,
		cadence = Enums.Cadence.OneTime,
		startWeek = 11,
		endWeek = 12,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Vazruden the Herald",
				instance = "Hellfire Ramparts",
				difficulty = Enums.Difficulty.Heroic
			}
		}
	},

	-------------------------------------------------------------------------------
	-- DUNGEON NORMAL ACHIEVEMENTS (Category 1, SubCategory 11)
	-------------------------------------------------------------------------------
	{
		id = 1100,
		name = "Shadow Labs",
		description = "Defeat Murmur in the Shadow Labyrinth on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 135161,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Murmur",
				instance = "Shadow Labyrinth",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1101,
		name = "SteamVault",
		description = "Defeat Warlord Kalithresh in the Steamvaults on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 134308,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Warlord Kalithresh",
				instance = "The Steamvault",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1102,
		name = "Slave Pens",
		description = "Defeat Quagmirran in the Slave pens on Normal difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 132322,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Quagmirran",
				instance = "The Slave Pens",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1103,
		name = "Shattered Halls",
		description = "Defeat Warchief Kargath Bladefist in the shattered halls on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 134170,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Warchief Kargath Bladefist",
				instance = "The Shattered Halls",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1104,
		name = "Mechanar",
		description = "Defeat Pathaleon the Calculator in the Mechanar on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 134066,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Pathaleon the Calculator",
				instance = "The Mechanar",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1105,
		name = "Blood Furnace",
		description = "Defeat Keli'dan the Breaker in Blood Furnace on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 133009,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Keli'dan the Breaker",
				instance = "The Blood Furnace",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1106,
		name = "Mana Tombs",
		description = "Defeat Nexus-Prince Shaffar in Mana tombs on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 132782,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Nexus-Prince Shaffar",
				instance = "Mana-Tombs",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1107,
		name = "Black Morass",
		description = "Defeat Aeonus in Black Morass on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 134154,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Aeonus",
				instance = "The Black Morass",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1108,
		name = "Sethekk Halls",
		description = "Defeat Talon King Ikiss in Sethekk Halls on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 132832,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Talon King Ikiss",
				instance = "Sethekk Halls",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1109,
		name = "Botanica",
		description = "Defeat Warp Splinter in the Botanica on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 134219,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Warp Splinter",
				instance = "The Botanica",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1110,
		name = "Old Hillsbrad",
		description = "Defeat Epoch Hunter in Old Hillsbrad Foothills on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 134156,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Epoch Hunter",
				instance = "Old Hillsbrad Foothills",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1111,
		name = "Auchenai Crypts",
		description = "Defeat Exarch Maladaar in Auchenai Crypts on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 135974,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Exarch Maladaar",
				instance = "Auchenai Crypts",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1112,
		name = "Underbog",
		description = "Defeat the Black stalker in The underbog on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 132371,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "The Black Stalker",
				instance = "The Underbog",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1113,
		name = "Hellfire Ramparts",
		description = "Defeat Nazan in Hellfire Ramparts on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 135794,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Vazruden the Herald",
				instance = "Hellfire Ramparts",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},
	{
		id = 1114,
		name = "Arcatraz Breakout",
		description = "Defeat Harbinger Skyriss in The Arcatraz on Normal Difficulty",
		points = 5,
		category = 1,
		subCategory = 11,
		icon = 135737,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = "Harbinger Skyriss",
				instance = "The Arcatraz",
				difficulty = Enums.Difficulty.Normal
			}
		}
	},

	-------------------------------------------------------------------------------
	-- MILESTONES ACHIEVEMENTS (Category 5)
	-------------------------------------------------------------------------------
	{
		id = 5001,
		name = "Nagrand Slam",
		description = "Complete 75 quests in Nagrand",
		points = 10,
		category = 5,
		subCategory = 50,
		icon = 132267,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "QUEST_COMPLETED",
			conditions = { zone = "Nagrand" }
		},
		progress = { type = "count", required = 75 }
	},
	{
		id = 5002,
		name = "Terror of Terrokar",
		description = "Complete 68 quests in Terrokar Forest",
		points = 10,
		category = 5,
		subCategory = 50,
		icon = 136060,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "QUEST_COMPLETED",
			conditions = { zone = "Terokkar Forest" }
		},
		progress = { type = "count", required = 68 }
	},
	{
		id = 5003,
		name = "Exalt More",
		description = "Earn Exalted Reputation with 2 Outland Factions",
		points = 25,
		category = 5,
		subCategory = 51,
		icon = 134475,
		cadence = Enums.Cadence.AllTime,
		-- Outland factions only (TBC); progress = unique factions at Exalted
		trigger = {
			event = "REPUTATION_GAINED",
			conditions = {
				standing = "Exalted",
				faction = {
					"Cenarion Expedition",
					"The Consortium",
					"Honor Hold",
					"Thrallmar",
					"Kurenai",
					"The Mag'har",
					"Lower City",
					"The Sha'tar",
					"The Aldor",
					"The Scryers",
					"Keepers of Time",
					"The Violet Eye"
				}
			}
		},
		progress = { type = "criteria", criteriaKey = "faction", required = 2 }
	},
	{
		id = 5004,
		name = "Aldor Ascended",
		description = "Reach Exalted with the Aldor",
		points = 15,
		category = 5,
		subCategory = 51,
		icon = 133832,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "REPUTATION_GAINED",
			conditions = { faction = "The Aldor", standing = "Exalted" }
		}
	},
	{
		id = 5005,
		name = "Scryer Supremacy",
		description = "Reach Exalted with the Scryers",
		points = 15,
		category = 5,
		subCategory = 51,
		icon = 133378,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "REPUTATION_GAINED",
			conditions = { faction = "The Scryers", standing = "Exalted" }
		}
	},
	{
		id = 5006,
		name = "Loremaster of Outland",
		description = "Complete all Outland Quest Achievements",
		points = 30,
		category = 5,
		subCategory = 50,
		icon = 894556,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ACHIEVEMENT_COMPLETED",
			conditions = { subCategory = 50 }
		},
		progress = { type = "meta", subCategory = 50, required = 9 }
	},
	{
		id = 5007,
		name = "Explore Outland",
		description = "Explore every zone in Outland",
		points = 10,
		category = 5,
		subCategory = 52,
		icon = 132226,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ZONE_EXPLORED",
			conditions = {
				zone = function(z) return z and OUTLAND_ZONES[z] end
			}
		},
		progress = { type = "criteria", required = 7 }
	},
	{
		id = 5008,
		name = "Key Collector",
		description = "Collect 3 Heroic Keys",
		points = 15,
		category = 5,
		icon = 134238,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "KEY_OBTAINED",
			conditions = {}
		},
		progress = { type = "count", required = 3 }
	},
	{
		id = 5009,
		name = "Hand of the Reckoning",
		description = "Complete all T5 raid bosses at least once (SSC & TK)",
		points = 75,
		category = 5,
		icon = 134468,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { instance = { "Serpentshrine Cavern", "Tempest Keep" } }
		},
		progress = { type = "criteria", required = 10 }
	},
	{
		id = 5010,
		name = "Keymaster of Outland",
		description = "Obtain all 5 Heroic keys",
		points = 40,
		category = 5,
		icon = 136058,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "KEY_OBTAINED",
			conditions = {}
		},
		progress = { type = "count", required = 5 }
	},
	{
		id = 5011,
		name = "Tycoon of Shattrath",
		description = "Collect 10,000 Gold",
		points = 10,
		category = 5,
		icon = 134113,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "GOLD_MILESTONE",
			conditions = { amount = function(g) return g >= 10000 end }
		}
	},
	{
		id = 5012,
		name = "Mercilessly Dedicated",
		description = "Win 100 Ranked Arena Matches",
		points = 40,
		category = 5,
		icon = 135901,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ARENA_MATCH_END",
			conditions = { result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 5013,
		name = "Reach Level 70",
		description = "Reach Level 70",
		points = 10,
		category = 5,
		icon = 133783,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "LEVEL_UP",
			conditions = { level = 70 }
		}
	},
	{
		id = 5014,
		name = "Violet Eye",
		description = "Earn Exalted with the Violet Eye",
		points = 30,
		category = 5,
		subCategory = 51,
		icon = 133404,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "REPUTATION_GAINED",
			conditions = { faction = "The Violet Eye", standing = "Exalted" }
		}
	},
	{
		id = 5015,
		name = "To Hellfire and Back",
		description = "Complete 84 quests in Hellfire Peninsula",
		points = 10,
		category = 5,
		subCategory = 50,
		icon = 135830,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "QUEST_COMPLETED",
			conditions = { zone = "Hellfire Peninsula" }
		},
		progress = { type = "count", required = 84 }
	},
	{
		id = 5016,
		name = "Stormrage",
		description = "Complete all 120 Quests in Netherstorm",
		points = 10,
		category = 5,
		subCategory = 50,
		icon = 132784,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "QUEST_COMPLETED",
			conditions = { zone = "Netherstorm" }
		},
		progress = { type = "count", required = 120 }
	},
	{
		id = 5017,
		name = "Mysteries of the Marsh",
		description = "Complete 52 quests in Zangarmarsh",
		points = 10,
		category = 5,
		subCategory = 50,
		icon = 134531,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "QUEST_COMPLETED",
			conditions = { zone = "Zangarmarsh" }
		},
		progress = { type = "count", required = 52 }
	},
	{
		id = 5018,
		name = "On the Blade's Edge",
		description = "Complete 86 quests in Blade's Edge Mountains",
		points = 10,
		category = 5,
		subCategory = 50,
		icon = 135244,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "QUEST_COMPLETED",
			conditions = { zone = "Blade's Edge Mountains" }
		},
		progress = { type = "count", required = 86 }
	},
	{
		id = 5019,
		name = "Treasure of the Naaru",
		description = "Collect 20 treasure chests in Outland",
		points = 10,
		category = 5,
		icon = 132594,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "TREASURE_CHEST_LOOTED",
			conditions = {
				zone = function(z) return z and OUTLAND_ZONES[z] end
			}
		},
		progress = { type = "count", required = 20 }
	},
	{
		id = 5020,
		name = "Shadow of Betrayer",
		description = "Complete 90 Quests in Shadowmoon Valley",
		points = 10,
		category = 5,
		subCategory = 50,
		icon = 135793,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "QUEST_COMPLETED",
			conditions = { zone = "Shadowmoon Valley" }
		},
		progress = { type = "count", required = 90 }
	},
	{
		id = 5021,
		name = "Ring of Blood",
		description = "Complete the Ring of Blood questline in Nagrand",
		points = 5,
		category = 5,
		subCategory = 50,
		icon = 132334,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "QUEST_COMPLETED",
			conditions = { questId = 9977 }
		}
	},
	{
		id = 5022,
		name = "Feathered Fur",
		description = "Kill Anzu (Druid boss) for the Raven Lord",
		points = 15,
		category = 5,
		icon = 132372,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Anzu" }
		}
	},
	{
		id = 5023,
		name = "Stern Durn",
		description = "Kill Durn the Hungerer",
		points = 10,
		category = 5,
		icon = 135871,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "CREATURE_KILLED",
			conditions = { creatureName = "Durn the Hungerer" }
		}
	},
	{
		id = 5024,
		name = "Hills like White Elekk",
		description = "Complete all Hemet Nesingwary quests in Nagrand including the ultimate bloodsport",
		points = 10,
		category = 5,
		subCategory = 50,
		icon = 133033,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "QUEST_COMPLETED",
			conditions = { questId = 9852 }
		}
	},
	{
		id = 5025,
		name = "We're Flying Peter",
		description = "Learn the Artisan Riding skill (Epic Flying)",
		points = 20,
		category = 5,
		icon = 132239,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.Riding, newLevel = 300 }
		}
	},
	{
		id = 5026,
		name = "Greedy",
		description = "Win a Greed roll on a superior or better item above Level 60",
		points = 5,
		category = 5,
		icon = 133786,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "LOOT_ROLL_WON",
			conditions = { rollType = "greed" }
		}
	},
	{
		id = 5027,
		name = "Needy",
		description = "Win a Need roll on a Superior or better item by rolling 100",
		points = 5,
		category = 5,
		icon = 133785,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "LOOT_ROLL_WON",
			conditions = { rollType = "need", rollValue = 100 }
		}
	},
	{
		id = 5028,
		name = "Epics Jimmy Epics!",
		description = "Equip all epic-quality gear slots with an ilvl of at least 103",
		points = 15,
		category = 5,
		icon = 134164,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "EPIC_GEAR_EQUIPPED",
			conditions = { quality = 4 }
		},
		progress = { type = "criteria", required = 16 }
	},
	{
		id = 5029,
		name = "Been Through the Flames",
		description = "Earn Exalted with Thrallmar",
		points = 30,
		category = 5,
		subCategory = 51,
		icon = 134504,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "REPUTATION_GAINED",
			conditions = { faction = "Thrallmar", standing = "Exalted" }
		}
	},
	{
		id = 5030,
		name = "Lower than my Credit Score",
		description = "Earn Exalted with Lower City",
		points = 30,
		category = 5,
		subCategory = 51,
		icon = 132929,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "REPUTATION_GAINED",
			conditions = { faction = "Lower City", standing = "Exalted" }
		}
	},
	{
		id = 5031,
		name = "Underwater Gardening",
		description = "Earn Exalted with Cenarion Expedition",
		points = 30,
		category = 5,
		subCategory = 51,
		icon = 132265,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "REPUTATION_GAINED",
			conditions = { faction = "Cenarion Expedition", standing = "Exalted" }
		}
	},
	{
		id = 5032,
		name = "Into the Nether",
		description = "Earn Exalted with The Sha'tar",
		points = 30,
		category = 5,
		subCategory = 51,
		icon = 133378,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "REPUTATION_GAINED",
			conditions = { faction = "The Sha'tar", standing = "Exalted" }
		}
	},
	{
		id = 5033,
		name = "Warp Speed",
		description = "Earn Exalted with The Consortium",
		points = 30,
		category = 5,
		subCategory = 51,
		icon = 134517,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "REPUTATION_GAINED",
			conditions = { faction = "The Consortium", standing = "Exalted" }
		}
	},
	{
		id = 5034,
		name = "That's Hot",
		description = "Loot a Gigantique Bag",
		points = 10,
		category = 5,
		icon = 133660,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_LOOTED",
			conditions = { itemName = "Gigantique Bag" }
		}
	},
	{
		id = 5035,
		name = "The Reaver Whisperer",
		description = "/roar at a Fel Reaver",
		points = 5,
		category = 5,
		icon = 136156,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "EMOTE_SENT",
			conditions = { emoteType = "roar", targetName = "Fel Reaver" }
		}
	},
	{
		id = 5036,
		name = "Monster Hunter",
		description = "Kill 5,000 Monsters of any type",
		points = 10,
		category = 5,
		icon = 135363,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "CREATURE_KILLED",
			conditions = {}
		},
		progress = { type = "count", required = 5000 }
	},
	{
		id = 5037,
		name = "Fel Down",
		description = "Kill a Fel Reaver",
		points = 10,
		category = 5,
		icon = 135799,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "CREATURE_KILLED",
			conditions = { creatureName = "Fel Reaver" }
		}
	},
	{
		id = 5038,
		name = "Turn back Time",
		description = "Earn Exalted with Keepers of Time",
		points = 30,
		category = 5,
		subCategory = 51,
		icon = 134476,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "REPUTATION_GAINED",
			conditions = { faction = "Keepers of Time", standing = "Exalted" }
		}
	},

	-------------------------------------------------------------------------------
	-- OPEN WORLD WEEKLY ACHIEVEMENTS (Category 6, SubCategory 60)
	-------------------------------------------------------------------------------
	{
		id = 6001,
		name = "Cooking Carnival",
		description = "Cook 40 Warp Burgers, Golden Fishsticks, or Spicy Crawdads",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 133904,
		cadence = Enums.Cadence.Weekly,
		startWeek = 1,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Cooking,
				itemName = { "Warp Burger", "Golden Fish Sticks", "Spicy Crawdad" }
			}
		},
		progress = { type = "count", required = 40 }
	},
	{
		id = 6002,
		name = "Primal Procurer (Shadow)",
		description = "Loot 5 Primal Shadow (or 15 Mote of Shadow) in Outland",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 132851,
		cadence = Enums.Cadence.Weekly,
		startWeek = 1,
		trigger = {
			event = "PRIMAL_LOOTED",
			conditions = { itemName = { "Primal Shadow", "Mote of Shadow" } }
		},
		progress = { type = "either", required = 15 }
	},
	{
		id = 6003,
		name = "Smoother than silk",
		description = "Craft 3 Primal Mooncloth, Spellcloth, or Shadowcloth",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 132897,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Tailoring,
				itemName = { "Primal Mooncloth", "Spellcloth", "Shadowcloth" }
			}
		},
		progress = { type = "count", required = 3 }
	},
	{
		id = 6004,
		name = "Full life",
		description = "Gather 100 herbs in Outland",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 132848,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { gatherType = Enums.GatherType.Herbalism }
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 6005,
		name = "Playing with Fire",
		description = "Loot 5 Primal Fire (or 15 Mote of Fire) in Outland",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 132847,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "PRIMAL_LOOTED",
			conditions = { itemName = { "Primal Fire", "Mote of Fire" } }
		},
		progress = { type = "either", required = 15 }
	},
	{
		id = 6006,
		name = "Air Ball",
		description = "Kill 25 Air Elementals in Outland",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 132845,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "CREATURE_KILLED",
			conditions = { creatureName = function(n) return n and n:find("Air") and n:find("Elemental") end }
		},
		progress = { type = "count", required = 25 }
	},
	{
		id = 6007,
		name = "Salt of the Earth",
		description = "Mine 100 ore in Outland",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 132846,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { gatherType = Enums.GatherType.Mining }
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 6008,
		name = "Mana Matters",
		description = "Loot 5 Primal Mana (or 15 Mote of Mana) in Netherstorm",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 132849,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "PRIMAL_LOOTED",
			conditions = { itemName = { "Primal Mana", "Mote of Mana" }, zone = "Netherstorm" }
		},
		progress = { type = "either", required = 15 }
	},
	{
		id = 6009,
		name = "Line and Sinker",
		description = "Catch 100 Fish",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 133921,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "FISH_CAUGHT",
			conditions = {}
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 6010,
		name = "Terocone Who",
		description = "Collect 40 Terocone",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 134223,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { itemName = "Terocone" }
		},
		progress = { type = "count", required = 40 }
	},
	{
		id = 6011,
		name = "I'm a Wizard Harry",
		description = "Disenchant 15 rare items above level 65",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 132881,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "ITEM_DISENCHANTED",
			-- TODO: Source item quality/level not available; resultItemLevel is a best-effort proxy.
			conditions = { resultItemLevel = function(l) return l and l >= 65 end }
		},
		progress = { type = "count", required = 15 }
	},
	{
		id = 6012,
		name = "Jeff Netherbloom",
		description = "Collect 40 Netherbloom",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 134216,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { itemName = "Netherbloom" }
		},
		progress = { type = "count", required = 40 }
	},
	{
		id = 6013,
		name = "Jewelcrafter's Eye",
		description = "Cut 20 rare gems",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 133252,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Jewelcrafting,
				itemQuality = Enums.ItemQuality.Rare
			}
		},
		progress = { type = "count", required = 20 }
	},
	{
		id = 6014,
		name = "Fel Lotus Fever",
		description = "Loot 10 Fel Lotus in Outland",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 134207,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { itemName = "Fel Lotus" }
		},
		progress = { type = "count", required = 10 }
	},
	{
		id = 6015,
		name = "Leather for Days",
		description = "Gather 40 Knothide Leather",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 134259,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { gatherType = Enums.GatherType.Skinning, itemName = "Knothide Leather" }
		},
		progress = { type = "count", required = 40 }
	},
	{
		id = 6016,
		name = "That's Tuff",
		description = "Craft 1 Cobrahide Leg Armor or Clefthoof Leg Armor",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 133619,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Leatherworking,
				itemName = { "Cobrahide Leg Armor", "Clefthoof Leg Armor" }
			}
		},
		progress = { type = "count", required = 1 }
	},
	{
		id = 6017,
		name = "Taking my Spirit",
		description = "Kill 20 Auchindoun dungeon bosses",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 133286,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				instance = { "Mana-Tombs", "Auchenai Crypts", "Sethekk Halls", "Shadow Labyrinth" }
			}
		},
		progress = { type = "count", required = 20 }
	},
	{
		id = 6018,
		name = "Burst of Destruction",
		description = "Craft 20 Haste or Destruction Potions",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 134730,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Alchemy,
				itemName = { "Haste Potion", "Destruction Potion" }
			}
		},
		progress = { type = "count", required = 20 }
	},
	{
		id = 6019,
		name = "Thread the Needle",
		description = "Craft 1 Runic, Silver, Mystic, or Golden Spellthread",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 136011,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Tailoring,
				itemName = { "Runic Spellthread", "Silver Spellthread", "Mystic Spellthread", "Golden Spellthread" }
			}
		},
		progress = { type = "count", required = 1 }
	},
	{
		id = 6020,
		name = "Potion Master",
		description = "Craft 15 Flasks or Elixirs",
		points = 10,
		category = 6,
		subCategory = 60,
		icon = 134740,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Alchemy,
				itemName = {
					-- TBC Flasks
					"Flask of Fortification",
					"Flask of Mighty Restoration",
					"Flask of Relentless Assault",
					"Flask of Blinding Light",
					"Flask of Pure Death",
					"Flask of Chromatic Wonder",
					-- TBC Battle Elixirs
					"Elixir of Major Shadow Power",
					"Fel Strength Elixir",
					"Elixir of Major Agility",
					"Elixir of Major Firepower",
					"Elixir of Major Frost Power",
					"Elixir of Healing Power",
					"Elixir of Mastery",
					"Elixir of Major Strength",
					"Adept's Elixir",
					"Onslaught Elixir",
					-- TBC Guardian Elixirs
					"Elixir of Empowerment",
					"Elixir of Major Mageblood",
					"Elixir of Major Defense",
					"Elixir of Ironskin",
					"Elixir of Draenic Wisdom",
					"Earthen Elixir",
					"Elixir of Major Fortitude"
				}
			}
		},
		progress = { type = "count", required = 15 }
	},
	{
		id = 6021,
		name = "Mining Madness",
		description = "Collect 50 Fel Iron Ore, Adamantite Ore, or Khorium Ore",
		points = 15,
		category = 6,
		subCategory = 60,
		icon = 134569,
		cadence = Enums.Cadence.Weekly,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = {
				gatherType = Enums.GatherType.Mining,
				itemName = { "Fel Iron Ore", "Adamantite Ore", "Khorium Ore" }
			}
		},
		progress = { type = "count", required = 50 }
	},

	-------------------------------------------------------------------------------
	-- PROFESSIONS ACHIEVEMENTS (Category 4)
	-------------------------------------------------------------------------------
	{
		id = 4001,
		name = "Bolt me up",
		description = "Craft 1000 Bolts of Netherweave",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 132899,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = { itemName = "Bolt of Netherweave" }
		},
		progress = { type = "count", required = 1000 }
	},
	{
		id = 4002,
		name = "Hunt and Gather",
		description = "Skin 5000 Beasts in Outland",
		points = 50,
		category = 4,
		subCategory = 41,
		icon = 134263,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { gatherType = Enums.GatherType.Skinning }
		},
		progress = { type = "count", required = 5000 }
	},
	{
		id = 4003,
		name = "Leather Lord",
		description = "Skin 1000 beasts in Outland",
		points = 10,
		category = 4,
		subCategory = 41,
		icon = 134363,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { gatherType = Enums.GatherType.Skinning }
		},
		progress = { type = "count", required = 1000 }
	},
	{
		id = 4004,
		name = "Medical Supplier",
		description = "Craft 250 Heavy Netherweave Bandages",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 133691,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = { itemName = "Heavy Netherweave Bandage" }
		},
		progress = { type = "count", required = 250 }
	},
	{
		id = 4005,
		name = "Transmutation",
		description = "Transmute 10 Primal Might",
		points = 30,
		category = 4,
		subCategory = 40,
		icon = 136050,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = { itemName = "Primal Might" }
		},
		progress = { type = "count", required = 10 }
	},
	{
		id = 4006,
		name = "I got the Potion",
		description = "Craft 500 Haste Potion, Destruction Potion, or Super Mana Potions",
		points = 30,
		category = 4,
		subCategory = 40,
		icon = 134730,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Alchemy,
				itemName = { "Haste Potion", "Destruction Potion", "Super Mana Potion" }
			}
		},
		progress = { type = "count", required = 500 }
	},
	{
		id = 4007,
		name = "Reckonings Apothecary",
		description = "Craft 700 Outland Flasks or Elixirs",
		points = 30,
		category = 4,
		subCategory = 40,
		icon = 134740,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Alchemy,
				itemName = {
					-- TBC Flasks
					"Flask of Fortification",
					"Flask of Mighty Restoration",
					"Flask of Relentless Assault",
					"Flask of Blinding Light",
					"Flask of Pure Death",
					"Flask of Chromatic Wonder",
					-- TBC Battle Elixirs
					"Elixir of Major Shadow Power",
					"Fel Strength Elixir",
					"Elixir of Major Agility",
					"Elixir of Major Firepower",
					"Elixir of Major Frost Power",
					"Elixir of Healing Power",
					"Elixir of Mastery",
					"Elixir of Major Strength",
					"Adept's Elixir",
					"Onslaught Elixir",
					"Elixir of Empowerment",
					-- TBC Guardian Elixirs
					"Elixir of Major Mageblood",
					"Elixir of Major Defense",
					"Elixir of Ironskin",
					"Elixir of Draenic Wisdom",
					"Earthen Elixir",
					"Elixir of Major Fortitude"
				}
			}
		},
		progress = { type = "count", required = 700 }
	},
	-- TODO: This is not currently trackable.
	{
		id = 4008,
		name = "The Collector of Glow",
		description = "Apply 50 Weapon Enchants to Different Items above Level 60",
		points = 25,
		category = 4,
		subCategory = 40,
		icon = 132881,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = { profession = Enums.Profession.Enchanting }
		},
		progress = { type = "count", required = 50 }
	},
	{
		id = 4009,
		name = "Shard Whisperer",
		description = "Disenchant 500 items above Level 60",
		points = 20,
		category = 4,
		subCategory = 40,
		icon = 132853,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_DISENCHANTED",
			-- TODO: Source item level not available; resultItemLevel is a best-effort proxy.
			conditions = { resultItemLevel = function(l) return l and l >= 60 end }
		},
		progress = { type = "count", required = 500 }
	},
	{
		id = 4010,
		name = "Kiss the ring",
		description = "Enchant Both Rings",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 132854,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "RING_ENCHANTED",
			conditions = {}
		},
		progress = { type = "count", required = 2 }
	},
	{
		id = 4011,
		name = "Lurker Above",
		description = "Fish up The Lurker Below in Serpentshrine Cavern",
		points = 50,
		category = 4,
		subCategory = 41,
		icon = 135844,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "FISH_CAUGHT",
			conditions = { fishName = "The Lurker Below" }
		}
	},
	{
		id = 4012,
		name = "Drum Machine",
		description = "Craft 60 Drums of Battle",
		points = 35,
		category = 4,
		subCategory = 40,
		icon = 133842,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = { itemName = "Drums of Battle" }
		},
		progress = { type = "count", required = 60 }
	},
	{
		id = 4013,
		name = "In the Bag",
		description = "Craft 120 Netherweave or Heavy Netherweave Bags",
		points = 30,
		category = 4,
		subCategory = 40,
		icon = 133692,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Tailoring,
				itemName = { "Netherweave Bag", "Heavy Netherweave Bag" }
			}
		},
		progress = { type = "count", required = 120 }
	},
	{
		id = 4014,
		name = "Boom or Bust",
		description = "Craft 200 Super Sapper Charges",
		points = 30,
		category = 4,
		subCategory = 40,
		icon = 133035,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = { itemName = "Super Sapper Charge" }
		},
		progress = { type = "count", required = 200 }
	},
	{
		id = 4015,
		name = "Rocket Scientist",
		description = "Craft your BOP Epic Goggles",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 133023,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Engineering,
				itemName = {
					"Deathblow X11 Goggles",
					"Furious Gizmatic Goggles",
					"Wonderheal XT68 Shades",
					"Hyper-Magnified Moon Specs",
					"Quad Deathblow X44 Goggles"
				}
			}
		}
	},
	{
		id = 4016,
		name = "Leather of the Wilds",
		description = "Craft one BoP epic Leatherworking pattern",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 132686,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Leatherworking,
				itemName = {
					"Cobrascale Gloves",
					"Cobrascale Hood",
					"Earthen Netherscale Boots",
					"Gloves of the Living Touch",
					"Hood of Primal Life",
					"Living Dragonscale Helm",
					"Netherdrake Gloves",
					"Netherdrake Helm",
					"Thick Netherscale Breastplate",
					"Windslayer Wraps",
					"Windscale Hood",
					"Windstrike Gloves"
				}
			}
		},
		progress = { type = "count", required = 1 }
	},
	{
		id = 4017,
		name = "Tailor of Style",
		description = "Craft one BOP epic Tailoring pattern",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 132897,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Tailoring,
				itemName = {
					-- Spellfire set
					"Spellfire Belt",
					"Spellfire Gloves",
					"Spellfire Robe",
					-- Frozen Shadoweave set
					"Frozen Shadoweave Shoulders",
					"Frozen Shadoweave Boots",
					"Frozen Shadoweave Robe",
					-- Primal Mooncloth set
					"Primal Mooncloth Belt",
					"Primal Mooncloth Shoulders",
					"Primal Mooncloth Robe"
				}
			}
		}
	},
	{
		id = 4018,
		name = "Skills of all Trades",
		description = "Obtain 375 Skill Points in 2 Primary Professions",
		points = 15,
		category = 4,
		icon = 133740,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = {
				newLevel = 375,
				profession = {
					Enums.Profession.Alchemy,
					Enums.Profession.Blacksmithing,
					Enums.Profession.Enchanting,
					Enums.Profession.Engineering,
					Enums.Profession.Herbalism,
					Enums.Profession.Jewelcrafting,
					Enums.Profession.Leatherworking,
					Enums.Profession.Mining,
					Enums.Profession.Skinning,
					Enums.Profession.Tailoring
				}
			}
		},
		progress = { type = "count", required = 2 }
	},
	{
		id = 4019,
		name = "Golden Standard",
		description = "Cut 100 rare gems",
		points = 20,
		category = 4,
		subCategory = 40,
		icon = 133269,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Jewelcrafting,
				itemQuality = Enums.ItemQuality.Rare
			}
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 4020,
		name = "Diamonds are Forever",
		description = "Cut 400 rare gems",
		points = 35,
		category = 4,
		subCategory = 40,
		icon = 133260,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Jewelcrafting,
				itemQuality = Enums.ItemQuality.Rare
			}
		},
		progress = { type = "count", required = 400 }
	},
	{
		id = 4021,
		name = "Master of Arms",
		description = "Craft your first epic weapon",
		points = 20,
		category = 4,
		subCategory = 40,
		icon = 133508,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = {
				profession = Enums.Profession.Blacksmithing,
				itemQuality = Enums.ItemQuality.Epic
			}
		}
	},
	-- TODO: This is not currently tracking item level.
	{
		id = 4022,
		name = "Forge of Reckoning",
		description = "Craft 150 weapons or armor pieces total above level 60",
		points = 30,
		category = 4,
		subCategory = 40,
		icon = 132736,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = { profession = Enums.Profession.Blacksmithing }
		},
		progress = { type = "count", required = 150 }
	},
	{
		id = 4023,
		name = "Herbal Hero",
		description = "Gather 500 Fel Lotus",
		points = 40,
		category = 4,
		subCategory = 41,
		icon = 134207,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { itemName = "Fel Lotus" }
		},
		progress = { type = "count", required = 500 }
	},
	{
		id = 4024,
		name = "Master of the Line",
		description = "Fish up 5000 Items",
		points = 50,
		category = 4,
		subCategory = 41,
		icon = 133927,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "FISH_CAUGHT",
			conditions = {}
		},
		progress = { type = "count", required = 5000 }
	},
	{
		id = 4025,
		name = "Rock Enjoyer",
		description = "Mine 5000 Ore in Outland",
		points = 50,
		category = 4,
		subCategory = 41,
		icon = 134709,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { gatherType = Enums.GatherType.Mining }
		},
		progress = { type = "count", required = 5000 }
	},
	{
		id = 4026,
		name = "Flower Enjoyer",
		description = "Gather 5,000 Herbs in Outland",
		points = 50,
		category = 4,
		subCategory = 41,
		icon = 134205,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { gatherType = Enums.GatherType.Herbalism }
		},
		progress = { type = "count", required = 5000 }
	},
	{
		id = 4027,
		name = "Flower picker",
		description = "Gather 1,000 Herbs in Outland",
		points = 10,
		category = 4,
		subCategory = 41,
		icon = 134218,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { gatherType = Enums.GatherType.Herbalism }
		},
		progress = { type = "count", required = 1000 }
	},
	{
		id = 4028,
		name = "Gourmet of the Legion",
		description = "Cook 500 Outland Food items",
		points = 30,
		category = 4,
		subCategory = 40,
		icon = 134040,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ITEM_CRAFTED",
			conditions = { profession = Enums.Profession.Cooking }
		},
		progress = { type = "count", required = 500 }
	},
	{
		id = 4029,
		name = "Mining Machine",
		description = "Mine 1000 Ore in Outland",
		points = 10,
		category = 4,
		subCategory = 41,
		icon = 134709,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "RESOURCE_GATHERED",
			conditions = { gatherType = Enums.GatherType.Mining }
		},
		progress = { type = "count", required = 1000 }
	},
	-- TODO: Filter to only count non-fish items.
	{
		id = 4030,
		name = "Catching Strays",
		description = "Fish up 1000 Items",
		points = 10,
		category = 4,
		subCategory = 41,
		icon = 132931,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "FISH_CAUGHT",
			conditions = {}
		},
		progress = { type = "count", required = 1000 }
	},
	{
		id = 4031,
		name = "Master Fisherman",
		description = "Reach 375 Fishing",
		points = 10,
		category = 4,
		subCategory = 41,
		icon = 136245,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.Fishing, newLevel = 375 }
		}
	},
	{
		id = 4032,
		name = "Master Cook",
		description = "Reach 375 Cooking",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 134004,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.Cooking, newLevel = 375 }
		}
	},
	{
		id = 4033,
		name = "Master Jewelcrafter",
		description = "Reach 375 Jewelcrafting",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 134071,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.Jewelcrafting, newLevel = 375 }
		}
	},
	{
		id = 4034,
		name = "Master Medic",
		description = "Reach 375 First Aid",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 133682,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.FirstAid, newLevel = 375 }
		}
	},
	{
		id = 4035,
		name = "Master Blacksmith",
		description = "Reach 375 Blacksmithing",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 136241,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.Blacksmithing, newLevel = 375 }
		}
	},
	{
		id = 4036,
		name = "Master Leatherworker",
		description = "Reach 375 Leatherworking",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 136247,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.Leatherworking, newLevel = 375 }
		}
	},
	{
		id = 4037,
		name = "Master Tailor",
		description = "Reach 375 Tailoring",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 136249,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.Tailoring, newLevel = 375 }
		}
	},
	{
		id = 4038,
		name = "Master Alchemist",
		description = "Reach 375 Alchemy",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 136240,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.Alchemy, newLevel = 375 }
		}
	},
	{
		id = 4039,
		name = "Master Engineer",
		description = "Reach 375 Engineering",
		points = 10,
		category = 4,
		subCategory = 40,
		icon = 136243,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.Engineering, newLevel = 375 }
		}
	},
	{
		id = 4040,
		name = "Master Herbalist",
		description = "Reach 375 Herbalism",
		points = 10,
		category = 4,
		subCategory = 41,
		icon = 136246,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.Herbalism, newLevel = 375 }
		}
	},
	{
		id = 4041,
		name = "Master Skinner",
		description = "Reach 375 Skinning",
		points = 10,
		category = 4,
		subCategory = 41,
		icon = 134366,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "SKILL_UP",
			conditions = { profession = Enums.Profession.Skinning, newLevel = 375 }
		}
	},

	-------------------------------------------------------------------------------
	-- PVP ACHIEVEMENTS (Category 3)
	-------------------------------------------------------------------------------
	-- Battlegrounds (SubCategory 30)
	{
		id = 3001,
		name = "10000 Honorable Kills",
		description = "Get 10000 Honorable kills (TBC only)",
		points = 50,
		category = 3,
		subCategory = 30,
		icon = 132339,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_KILL",
			conditions = {}
		},
		progress = { type = "count", required = 10000 }
	},
	{
		id = 3002,
		name = "5000 Honorable Kills",
		description = "Get 5000 Honorable kills (TBC only)",
		points = 25,
		category = 3,
		subCategory = 30,
		icon = 133728,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_KILL",
			conditions = {}
		},
		progress = { type = "count", required = 5000 }
	},
	{
		id = 3003,
		name = "Alterac Blitz",
		description = "Win an AV match in under 7 minutes",
		points = 15,
		category = 3,
		subCategory = 30,
		icon = 135463,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Alterac Valley", result = Enums.BattlegroundResult.Victory, duration = function(d) return d <= 420 end }
		}
	},
	{
		id = 3004,
		name = "Arathi Takeover",
		description = "Win an Arathi Basin Match in under 7 minutes",
		points = 15,
		category = 3,
		subCategory = 30,
		icon = 134144,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Arathi Basin", result = Enums.BattlegroundResult.Victory, duration = function(d) return d <= 420 end }
		}
	},
	{
		id = 3005,
		name = "Call to Arms",
		description = "Win 100 battlegrounds",
		points = 20,
		category = 3,
		subCategory = 30,
		icon = 134228,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 3006,
		name = "Disgracin the Basin",
		description = "Assault 3 bases in a single AB Battle",
		points = 10,
		category = 3,
		subCategory = 30,
		icon = 132487,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_OBJECTIVE_CAPTURED",
			conditions = { location = "Arathi Basin" }
		},
		progress = { type = "count", required = 3, reset = "match" }
	},
	{
		id = 3007,
		name = "Eye for an Eye",
		description = "Win 25 Eye of the Storm Matches",
		points = 20,
		category = 3,
		subCategory = 30,
		icon = 136032,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Eye of the Storm", result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 25 }
	},
	{
		id = 3008,
		name = "That Takes Class",
		description = "Get a Killing Blow on each class",
		points = 10,
		category = 3,
		subCategory = 30,
		icon = 132092,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_KILLING_BLOW",
			conditions = {}
		},
		progress = { type = "criteria", required = 9 }
	},
	{
		id = 3009,
		name = "Flag Frenzy",
		description = "Capture 3 Flags in a single WSG Match",
		points = 10,
		category = 3,
		subCategory = 30,
		icon = 132485,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_OBJECTIVE_CAPTURED",
			conditions = { location = "Warsong Gulch", objectiveType = Enums.ObjectiveType.Flag, isFlagReturn = false }
		},
		progress = { type = "count", required = 3, reset = "match" }
	},
	{
		id = 3010,
		name = "Flurry",
		description = "Win Eye of the Storm in under 6 minutes",
		points = 10,
		category = 3,
		subCategory = 30,
		icon = 236395,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Eye of the Storm", result = Enums.BattlegroundResult.Victory, duration = function(d) return d <= 360 end }
		}
	},
	{
		id = 3011,
		name = "Frenzied Defender",
		description = "Return 5 flags in a single battle of WSG",
		points = 10,
		category = 3,
		subCategory = 30,
		icon = 132486,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_OBJECTIVE_CAPTURED",
			conditions = { location = "Warsong Gulch", isFlagReturn = true }
		},
		progress = { type = "count", required = 5, reset = "match" }
	},
	{
		id = 3012,
		name = "We're still doing this?",
		description = "Complete 100 Alterac Valley Battles",
		points = 20,
		category = 3,
		subCategory = 30,
		icon = 133308,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Alterac Valley" }
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 3013,
		name = "Basin Veteran",
		description = "Win 25 Arathi Basin Matches",
		points = 15,
		category = 3,
		subCategory = 30,
		icon = 132484,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Arathi Basin", result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 25 }
	},
	{
		id = 3014,
		name = "Arathi General",
		description = "Complete 100 Arathi Basin Battles",
		points = 20,
		category = 3,
		subCategory = 30,
		icon = 133282,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Arathi Basin" }
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 3015,
		name = "Warsong Rider",
		description = "Complete 60 WSG Battles",
		points = 20,
		category = 3,
		subCategory = 30,
		icon = 134420,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Warsong Gulch" }
		},
		progress = { type = "count", required = 60 }
	},
	{
		id = 3016,
		name = "Smile through the Storm",
		description = "Complete 100 Eye of the Storm Battles",
		points = 20,
		category = 3,
		subCategory = 30,
		icon = 136032,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Eye of the Storm" }
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 3017,
		name = "The Executioner",
		description = "Deal the final blow on 500 enemies",
		points = 10,
		category = 3,
		subCategory = 30,
		icon = 135823,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_KILLING_BLOW",
			conditions = {}
		},
		progress = { type = "count", required = 500 }
	},
	{
		id = 3018,
		name = "Bloodstained Glory",
		description = "Get 10 killing blows in a single battleground",
		points = 10,
		category = 3,
		subCategory = 30,
		icon = 132284,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_KILLING_BLOW",
			conditions = {}
		},
		progress = { type = "count", required = 10, reset = "match" }
	},
	{
		id = 3019,
		name = "Grim Reaper",
		description = "Get 40 HKs in a Single Battleground",
		points = 10,
		category = 3,
		subCategory = 30,
		icon = 136157,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_KILL",
			conditions = {}
		},
		progress = { type = "count", required = 40, reset = "match" }
	},
	{
		id = 3020,
		name = "Death Note",
		description = "Get 100 HKs in a Single Battleground",
		points = 15,
		category = 3,
		subCategory = 30,
		icon = 136147,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_KILL",
			conditions = {}
		},
		progress = { type = "count", required = 100, reset = "match" }
	},
	{
		id = 3021,
		name = "Tower Keeper",
		description = "Defend a tower for one single battle for Alterac Valley and stay until it is over",
		points = 10,
		category = 3,
		subCategory = 30,
		icon = 132110,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_OBJECTIVE_CAPTURED",
			conditions = { location = "Alterac Valley", objectiveType = "tower_defense" }
		}
	},
	{
		id = 3022,
		name = "Stormtrooper",
		description = "Kill 5 Flag Carriers in a single EOTS battle",
		points = 10,
		category = 3,
		subCategory = 30,
		icon = 136014,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_KILLING_BLOW",
			conditions = { battleground = "Eye of the Storm", targetType = "flag_carrier" }
		},
		progress = { type = "count", required = 5, reset = "match" }
	},
	{
		id = 3023,
		name = "Wrecking Ball",
		description = "Get 20 KBs in a single BG without dying",
		points = 15,
		category = 3,
		subCategory = 30,
		icon = 136001,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_KILLING_BLOW",
			conditions = {}
		},
		progress = { type = "count", required = 20, reset = "match" },
		failCondition = {
			event = "PLAYER_DIED",
			conditions = { inBattleground = true }
		}
	},

	-- Arena (SubCategory 31)
	{
		id = 3050,
		name = "Arena Champion",
		description = "Earn a 1850 Rating in any arena Bracket",
		points = 50,
		category = 3,
		subCategory = 31,
		icon = 135381,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ARENA_RATING_MILESTONE",
			conditions = { rating = function(r) return r >= 1850 end }
		}
	},
	{
		id = 3051,
		name = "Mercilessly Dedicated",
		description = "Win 100 Ranked Arena Matches",
		points = 40,
		category = 3,
		subCategory = 31,
		icon = 135882,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ARENA_MATCH_END",
			conditions = { result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 3052,
		name = "Team make it Rain",
		description = "Win 5 3v3 matches in a row",
		points = 15,
		category = 3,
		subCategory = 31,
		icon = 135787,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ARENA_MATCH_END",
			conditions = { bracket = Enums.ArenaBracket.ThreeVThree, result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 5, reset = "loss" }
	},
	{
		id = 3053,
		name = "Reckoning Gladiator",
		description = "Earn a 2000 Rating in any arena Bracket",
		points = 100,
		category = 3,
		subCategory = 31,
		icon = 132147,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ARENA_RATING_MILESTONE",
			conditions = { rating = function(r) return r >= 2000 end }
		}
	},
	{
		id = 3054,
		name = "Arena Master",
		description = "Win 100 Arena Matches total",
		points = 50,
		category = 3,
		subCategory = 31,
		icon = 236325,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ARENA_MATCH_END",
			conditions = { result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 3055,
		name = "Threes's Company",
		description = "Earn 1550 Arena Rating in 3v3",
		points = 15,
		category = 3,
		subCategory = 31,
		icon = 236331,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ARENA_RATING_MILESTONE",
			conditions = { bracket = Enums.ArenaBracket.ThreeVThree, rating = function(r) return r >= 1550 end }
		}
	},
	{
		id = 3056,
		name = "Hot Streak",
		description = "Win ten ranked Arenas in a row",
		points = 10,
		category = 3,
		subCategory = 31,
		icon = 135819,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ARENA_MATCH_END",
			conditions = { result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 10, reset = "loss" }
	},
	{
		id = 3057,
		name = "Just the 2 of us",
		description = "Earn a 1700 Rating in 2v2 Arena",
		points = 30,
		category = 3,
		subCategory = 31,
		icon = 236329,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ARENA_RATING_MILESTONE",
			conditions = { bracket = Enums.ArenaBracket.TwoVTwo, rating = function(r) return r >= 1700 end }
		}
	},
	{
		id = 3058,
		name = "Reckoning's Finest",
		description = "Reach 1700+ arena rating in any bracket",
		points = 30,
		category = 3,
		subCategory = 31,
		icon = 135889,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ARENA_RATING_MILESTONE",
			conditions = { rating = function(r) return r >= 1700 end }
		}
	},

	-- World PvP (SubCategory 32)
	{
		id = 3080,
		name = "Halaa Conqueror",
		description = "Earn 100 Halaa Battle Tokens",
		points = 50,
		category = 3,
		subCategory = 32,
		icon = 134421,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_TOKEN_EARNED",
			conditions = { tokenType = "Halaa Battle Token" }
		},
		progress = { type = "count", required = 100 }
	},
	{
		id = 3081,
		name = "Hellfire Bandit",
		description = "Capture all 3 Towers in Hellfire Peninsula",
		points = 10,
		category = 3,
		subCategory = 32,
		icon = 134504,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_OBJECTIVE_CAPTURED",
			conditions = { zone = "Hellfire Peninsula" }
		},
		progress = { type = "criteria", required = 3 }
	},
	{
		id = 3082,
		name = "Outland Slayer",
		description = "Earn 1,000 HKs in Outland zones",
		points = 20,
		category = 3,
		subCategory = 32,
		icon = 255132,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "PVP_KILL",
			conditions = { zone = "Outland" }
		},
		progress = { type = "count", required = 1000 }
	},

	-- PVP One-Time Achievements
	{
		id = 3100,
		name = "Battleground Starter",
		description = "Win 10 battlegrounds",
		points = 40,
		category = 3,
		subCategory = 30,
		icon = 132356,
		cadence = Enums.Cadence.OneTime,
		startWeek = 1,
		endWeek = 2,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 10 }
	},
	{
		id = 3101,
		name = "The Reckoning Vanguard",
		description = "Win 1 of Each Battleground Type (WSG, AB, AV, EOTS)",
		points = 40,
		category = 3,
		subCategory = 30,
		icon = 132205,
		cadence = Enums.Cadence.OneTime,
		startWeek = 2,
		endWeek = 3,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "criteria", required = 4 }
	},
	{
		id = 3102,
		name = "Storm Glory",
		description = "Win 8 Eye of the Storm Matches",
		points = 40,
		category = 3,
		subCategory = 30,
		icon = 136032,
		cadence = Enums.Cadence.OneTime,
		startWeek = 3,
		endWeek = 4,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Eye of the Storm", result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 8 }
	},
	{
		id = 3103,
		name = "Hot Date",
		description = "Win 10 2v2 Arena Matches",
		points = 40,
		category = 3,
		subCategory = 31,
		icon = 133886,
		cadence = Enums.Cadence.OneTime,
		startWeek = 3,
		endWeek = 4,
		trigger = {
			event = "ARENA_MATCH_END",
			conditions = { bracket = Enums.ArenaBracket.TwoVTwo, result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 10 }
	},
	{
		id = 3104,
		name = "Unstoppable Duo",
		description = "Win 5 Consecutive 2v2 Matches",
		points = 40,
		category = 3,
		subCategory = 31,
		icon = 133174,
		cadence = Enums.Cadence.OneTime,
		startWeek = 4,
		endWeek = 5,
		trigger = {
			event = "ARENA_MATCH_END",
			conditions = { bracket = Enums.ArenaBracket.TwoVTwo, result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 5, reset = "loss" }
	},
	{
		id = 3105,
		name = "Can't Stop Us",
		description = "Improve your arena Rating by 200+ Rating in one week",
		points = 40,
		category = 3,
		subCategory = 31,
		icon = 136234,
		cadence = Enums.Cadence.OneTime,
		startWeek = 4,
		endWeek = 5,
		trigger = {
			event = "ARENA_RATING_MILESTONE",
			conditions = { ratingGain = function(g) return g >= 200 end }
		}
	},
	{
		id = 3106,
		name = "5v5 masta",
		description = "Win 10 3v3 Matches with a guild team",
		points = 40,
		category = 3,
		subCategory = 31,
		icon = 135026,
		cadence = Enums.Cadence.OneTime,
		startWeek = 5,
		endWeek = 6,
		trigger = {
			event = "ARENA_MATCH_END",
			conditions = { bracket = Enums.ArenaBracket.ThreeVThree, result = Enums.BattlegroundResult.Victory, guildTeam = true }
		},
		progress = { type = "count", required = 10 }
	},
	{
		id = 3107,
		name = "Chasin the Basin",
		description = "Complete 10 Arathi Basin Matches",
		points = 40,
		category = 3,
		subCategory = 30,
		icon = 133282,
		cadence = Enums.Cadence.OneTime,
		startWeek = 5,
		endWeek = 6,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Arathi Basin" }
		},
		progress = { type = "count", required = 10 }
	},
	{
		id = 3108,
		name = "Arena Ascendant",
		description = "Win 20 arena matches in one week",
		points = 40,
		category = 3,
		subCategory = 31,
		icon = 133188,
		cadence = Enums.Cadence.OneTime,
		startWeek = 6,
		endWeek = 6,
		trigger = {
			event = "ARENA_MATCH_END",
			conditions = { result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 20 }
	},
	{
		id = 3109,
		name = "Three's Company",
		description = "Win 10 5v5 Matches with a guild team",
		points = 60,
		category = 3,
		subCategory = 31,
		icon = 135026,
		cadence = Enums.Cadence.OneTime,
		startWeek = 6,
		endWeek = 7,
		trigger = {
			event = "ARENA_MATCH_END",
			conditions = { bracket = Enums.ArenaBracket.FiveVFive, result = Enums.BattlegroundResult.Victory, guildTeam = true }
		},
		progress = { type = "count", required = 10 }
	},
	{
		id = 3110,
		name = "Halaa Heavyweight",
		description = "Earn 25 Halaa Battle Tokens",
		points = 50,
		category = 3,
		subCategory = 32,
		icon = 134421,
		cadence = Enums.Cadence.OneTime,
		startWeek = 7,
		endWeek = 8,
		trigger = {
			event = "PVP_TOKEN_EARNED",
			conditions = { tokenType = "Halaa Battle Token" }
		},
		progress = { type = "count", required = 25 }
	},
	{
		id = 3111,
		name = "Holding Dominance",
		description = "Capture and hold Halaa for 30 minutes",
		points = 40,
		category = 3,
		subCategory = 32,
		icon = 134421,
		cadence = Enums.Cadence.OneTime,
		startWeek = 8,
		endWeek = 9,
		trigger = {
			event = "PVP_OBJECTIVE_CAPTURED",
			conditions = { zone = "Nagrand", objectiveType = "halaa" }
		}
	},
	{
		id = 3112,
		name = "Warsong Warrior",
		description = "Win 6 WSG Matches",
		points = 40,
		category = 3,
		subCategory = 30,
		icon = 134420,
		cadence = Enums.Cadence.OneTime,
		startWeek = 8,
		endWeek = 9,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { battleground = "Warsong Gulch", result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 6 }
	},
	{
		id = 3113,
		name = "Arena Come up!",
		description = "Earn 1600 Arena Rating in any Bracket",
		points = 50,
		category = 3,
		subCategory = 31,
		icon = 4006481,
		cadence = Enums.Cadence.OneTime,
		startWeek = 9,
		endWeek = 10,
		trigger = {
			event = "ARENA_RATING_MILESTONE",
			conditions = { rating = function(r) return r >= 1600 end }
		}
	},
	{
		id = 3114,
		name = "Battleground Hero",
		description = "Win 3 Battlegrounds in a row",
		points = 40,
		category = 3,
		subCategory = 30,
		icon = 135919,
		cadence = Enums.Cadence.OneTime,
		startWeek = 10,
		endWeek = 11,
		trigger = {
			event = "BATTLEGROUND_MATCH_END",
			conditions = { result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 3, reset = "loss" }
	},
	{
		id = 3115,
		name = "Arena Mayhem",
		description = "Win 10 Arena Matches in any Bracket",
		points = 40,
		category = 3,
		subCategory = 31,
		icon = 236334,
		cadence = Enums.Cadence.OneTime,
		startWeek = 11,
		endWeek = 12,
		trigger = {
			event = "ARENA_MATCH_END",
			conditions = { result = Enums.BattlegroundResult.Victory }
		},
		progress = { type = "count", required = 10 }
	},
	{
		id = 3116,
		name = "Honor Among Thieves",
		description = "Get 400 HKs in one week",
		points = 40,
		category = 3,
		subCategory = 30,
		icon = 136143,
		cadence = Enums.Cadence.OneTime,
		startWeek = 11,
		endWeek = 12,
		trigger = {
			event = "PVP_KILL",
			conditions = {}
		},
		progress = { type = "count", required = 400 }
	},

	-------------------------------------------------------------------------------
	-- RAID ACHIEVEMENTS (Category 2)
	-------------------------------------------------------------------------------
	-- Karazhan (SubCategory 20)
	{
		id = 2001,
		name = "Keeper of the Violet Seal",
		description = "Collect The Master's Key (Kara attunement)",
		points = 15,
		category = 2,
		subCategory = 20,
		icon = 134241,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "KEY_OBTAINED",
			conditions = { keyName = "The Master's Key" }
		}
	},
	{
		id = 2002,
		name = "Checkmate",
		description = "Defeat Chess event in under 2 minutes",
		points = 15,
		category = 2,
		subCategory = 20,
		icon = 134148,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Chess Event", duration = function(d) return d <= 120 end }
		}
	},
	{
		id = 2003,
		name = "True Love Denied",
		description = "Defeat Julianne & Romulo without any uninterrupted cast of Eternal Affection",
		points = 15,
		category = 2,
		subCategory = 20,
		icon = 135767,
		cadence = Enums.Cadence.AllTime,
		-- TODO: Implement fail tracking for uninterrupted Eternal Affection casts.
		-- Requires combat log parsing to track spell interrupts.
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Julianne" }
		}
	},
	{
		id = 2004,
		name = "A Night at the Opera",
		description = "Complete all three Opera events (Romulo & Julianne, Big Bad Wolf, Wizard of Oz) across multiple lockouts",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 135886,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = {
				bossName = {
					"Julianne",
					"The Big Bad Wolf",
					"The Crone"
				}
			}
		},
		progress = { type = "criteria", required = 3 }
	},
	{
		id = 2005,
		name = "Tower Conquerors",
		description = "Defeat Prince Malchezaar in Karazhan",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 136150,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Prince Malchezaar" }
		}
	},
	{
		id = 2006,
		name = "Moroes for Dinner",
		description = "Defeat Moroes in 80 seconds",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 134179,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Moroes", duration = function(d) return d <= 80 end }
		}
	},
	-- TODO: Not currently tracking looting of books.
	{
		id = 2007,
		name = "Books of Power",
		description = "Interact with all 12 readable books scattered throughout Karazhan",
		points = 15,
		category = 2,
		subCategory = 20,
		icon = 133733,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		trigger = {
			event = "QUEST_COMPLETED",
			conditions = {}
		},
		progress = { type = "criteria", required = 12 }
	},
	{
		id = 2008,
		name = "Just Dance",
		description = "Dance with a Spectral Performer inside Karazhan (/Dance)",
		points = 5,
		category = 2,
		subCategory = 20,
		icon = 133886,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		trigger = {
			event = "EMOTE_SENT",
			conditions = {
				emoteType = "dance",
				targetName = "Spectral Performer"
			}
		}
	},
	{
		id = 2009,
		name = "Runaway Little Girl",
		description = "Defeat Big Bad Wolf without anyone getting hit as Little Red Riding Hood",
		points = 15,
		category = 2,
		subCategory = 20,
		icon = 132224,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		-- TODO: Implement fail tracking for damage taken while polymorphed as Little Red Riding Hood.
		-- Requires combat log parsing to track damage events on players with specific debuff.
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "The Big Bad Wolf" }
		}
	},
	{
		id = 2010,
		name = "Barnes and Noble",
		description = "Have all raid members /cheer at Barnes in the Opera Event",
		points = 10,
		category = 2,
		subCategory = 20,
		icon = 136144,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		-- TODO: Currently only tracks when YOU cheer at Barnes. To fully implement,
		-- need to track all raid members cheering (may require guild communication/tracking).
		trigger = {
			event = "EMOTE_SENT",
			conditions = {
				emoteType = "cheer",
				targetName = "Barnes"
			}
		}
	},
	{
		id = 2011,
		name = "Wicked",
		description = "Defeat the Crone with no raid member getting hit by cyclone",
		points = 15,
		category = 2,
		subCategory = 20,
		icon = 136018,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "The Crone" }
		},
		failCondition = {
			event = "DUNGEON_MECHANIC_FAILED",
			conditions = { mechanicName = "Cyclone" }
		}
	},
	{
		id = 2012,
		name = "Nightbane Unchained",
		description = "Kill Nightbane in Karazhan",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 133839,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Nightbane" }
		}
	},
	{
		id = 2013,
		name = "Honey there's a Spider!",
		description = "Kill Hyakiss the Lurker",
		points = 15,
		category = 2,
		subCategory = 20,
		icon = 132196,
		cadence = Enums.Cadence.AllTime,
		startWeek = 5,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Hyakiss the Lurker" }
		}
	},
	{
		id = 2014,
		name = "Speed Demon",
		description = "Kill Prince Malchezaar under 2 Minutes",
		points = 25,
		category = 2,
		subCategory = 20,
		icon = 135788,
		cadence = Enums.Cadence.AllTime,
		startWeek = 5,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Prince Malchezaar", duration = function(d) return d <= 120 end }
		}
	},
	{
		id = 2015,
		name = "Curator Curated",
		description = "Defeat The Curator in 1 minute 30 seconds",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 135732,
		cadence = Enums.Cadence.AllTime,
		startWeek = 4,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "The Curator", duration = function(d) return d <= 90 end }
		}
	},
	{
		id = 2016,
		name = "Always Immortal",
		description = "0 Deaths on Karazhan Bosses",
		points = 100,
		category = 2,
		subCategory = 20,
		icon = 135981,
		cadence = Enums.Cadence.AllTime,
		startWeek = 6,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = { instanceName = "Karazhan", deaths = 0 }
		}
	},
	{
		id = 2017,
		name = "Strikes at Midnight",
		description = "Defeat Attumen the Huntsman in 70 seconds",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 132238,
		cadence = Enums.Cadence.AllTime,
		startWeek = 3,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Attumen the Huntsman", duration = function(d) return d <= 70 end }
		}
	},
	{
		id = 2018,
		name = "The Tower Unbroken",
		description = "Clear Karazhan with zero wipes",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 135981,
		cadence = Enums.Cadence.AllTime,
		startWeek = 3,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = { instanceName = "Karazhan", wipes = 0 }
		}
	},
	{
		id = 2019,
		name = "Lights Out",
		description = "Defeat Netherspite with no deaths",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 134155,
		cadence = Enums.Cadence.AllTime,
		startWeek = 4,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Netherspite", deaths = 0 }
		}
	},
	{
		id = 2020,
		name = "No shade",
		description = "Defeat Shade of Aran without anyone being hit by Flame Wreath",
		points = 15,
		category = 2,
		subCategory = 20,
		icon = 135926,
		cadence = Enums.Cadence.AllTime,
		startWeek = 4,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Shade of Aran" }
		},
		failCondition = {
			event = "DUNGEON_MECHANIC_FAILED",
			conditions = { mechanicName = "Flame Wreath" }
		}
	},
	{
		id = 2021,
		name = "Prince of the Tower",
		description = "Defeat Prince Malchezaar without anyone dying to Shadow Nova or Infernal crashes",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 135831,
		cadence = Enums.Cadence.AllTime,
		startWeek = 4,
		-- TODO: Implement fail tracking for deaths to Shadow Nova or Infernal crashes.
		-- Requires combat log parsing to track death events and their sources.
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Prince Malchezaar" }
		}
	},
	{
		id = 2022,
		name = "Maiden Virtous",
		description = "Defeat Maiden of Virtue in 45 seconds",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 135921,
		cadence = Enums.Cadence.AllTime,
		startWeek = 4,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Maiden of Virtue", duration = function(d) return d <= 45 end }
		}
	},
	{
		id = 2023,
		name = "Library Card Revoked",
		description = "Kill Shade of Aran with the raid taking 0 Frostbolt Damage",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 134390,
		cadence = Enums.Cadence.AllTime,
		startWeek = 5,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Shade of Aran" }
		},
		failCondition = {
			event = "DUNGEON_MECHANIC_FAILED",
			conditions = { mechanicName = "Frostbolt" }
		}
	},
	{
		id = 2024,
		name = "Karazhan Champion",
		description = "Finish all Karazhan Achievements",
		points = 80,
		category = 2,
		subCategory = 20,
		icon = 135958,
		cadence = Enums.Cadence.AllTime,
		trigger = {
			event = "ACHIEVEMENT_COMPLETED",
			conditions = { subCategory = 20 }
		},
		progress = { type = "meta", subCategory = 20, required = 23 }
	},
	{
		id = 2025,
		name = "Midnight Rush",
		description = "Clear Karazhan in under 85 minutes",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 132307,
		cadence = Enums.Cadence.AllTime,
		startWeek = 6,
		trigger = {
			event = "DUNGEON_CLEARED",
			conditions = { instanceName = "Karazhan", duration = function(d) return d <= 5100 end }
		}
	},
	{
		id = 2026,
		name = "DemonFall",
		description = "Defeat Terestian Illhoof without killing any imps",
		points = 20,
		category = 2,
		subCategory = 20,
		icon = 136218,
		cadence = Enums.Cadence.AllTime,
		startWeek = 5,
		-- TODO: Implement fail tracking for imp kills during encounter.
		-- Requires combat log parsing to track creature kills and identify imp deaths.
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Terestian Illhoof" }
		}
	},

	-- Tier 4 (SubCategory 21)
	{
		id = 2030,
		name = "Click that Cube!",
		description = "Defeat Magtheridon with taking 0 blast nova damage",
		points = 20,
		category = 2,
		subCategory = 21,
		icon = 135824,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Magtheridon" }
		},
		failCondition = {
			event = "DUNGEON_MECHANIC_FAILED",
			conditions = { mechanicName = "Blast Nova" }
		}
	},
	{
		id = 2031,
		name = "Shatterproof",
		description = "Defeat Gruul without any raid member dying to Shatter",
		points = 25,
		category = 2,
		subCategory = 21,
		icon = 135237,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		-- TODO: Currently tracks zero deaths. Ideally should track deaths specifically from Shatter.
		-- Requires combat log parsing to track death sources.
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Gruul the Dragonkiller", deaths = 0 }
		}
	},
	{
		id = 2032,
		name = "Killing the Dragonkiller",
		description = "Defeat Gruul the Dragonkiller",
		points = 20,
		category = 2,
		subCategory = 21,
		icon = 132451,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Gruul the Dragonkiller" }
		}
	},
	{
		id = 2033,
		name = "Mag",
		description = "Defeat Magtheridon",
		points = 20,
		category = 2,
		subCategory = 21,
		icon = 136219,
		cadence = Enums.Cadence.AllTime,
		startWeek = 2,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Magtheridon" }
		}
	},
	{
		id = 2034,
		name = "No Time for Ogres",
		description = "Defeat High King Maulgar in under 1 minute",
		points = 20,
		category = 2,
		subCategory = 21,
		icon = 133484,
		cadence = Enums.Cadence.AllTime,
		startWeek = 3,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "High King Maulgar", duration = function(d) return d <= 60 end }
		}
	},

	-- Tier 5 (SubCategory 22)
	{
		id = 2040,
		name = "Serpentshrine Cavern",
		description = "Defeat Lady Vashj in Serpentshrine Cavern",
		points = 150,
		category = 2,
		subCategory = 22,
		icon = 135862,
		cadence = Enums.Cadence.AllTime,
		startWeek = 6,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Lady Vashj" }
		}
	},
	{
		id = 2041,
		name = "Tempest Keep",
		description = "Defeat Kael'thas Sunstrider in Tempest Keep",
		points = 150,
		category = 2,
		subCategory = 22,
		icon = 135734,
		cadence = Enums.Cadence.AllTime,
		startWeek = 6,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Kael'thas Sunstrider" }
		}
	},
	{
		id = 2042,
		name = "There goes my Hero",
		description = "Fall 65 yards in Serpentshrine Cavern and Live",
		points = 15,
		category = 2,
		subCategory = 22,
		icon = 135992,
		cadence = Enums.Cadence.AllTime,
		startWeek = 6,
		trigger = {
			event = "FALL_SURVIVED",
			conditions = {
				zone = "Serpentshrine Cavern",
				duration = function(d) return d >= (const and const.FALLING and const.FALLING.MIN_SECONDS or 0) end
			}
		}
	},

	-- Tier 6 (SubCategory 23)
	{
		id = 2050,
		name = "Battle for Mount Hyjal",
		description = "Defeat Archimonde in the Battle for Mount Hyjal",
		points = 150,
		category = 2,
		subCategory = 23,
		icon = 136149,
		cadence = Enums.Cadence.AllTime,
		startWeek = 6,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Archimonde" }
		}
	},
	{
		id = 2051,
		name = "The Black Temple",
		description = "Defeat Illidan Stormrage in the Black Temple",
		points = 300,
		category = 2,
		subCategory = 23,
		icon = 135561,
		cadence = Enums.Cadence.AllTime,
		startWeek = 6,
		trigger = {
			event = "DUNGEON_BOSS_KILLED",
			conditions = { bossName = "Illidan Stormrage" }
		}
	},

}
aUtils:RegisterAchievements(ACHIEVEMENTS)

-------------------------------------------------------------------------------
-- Display Customization
-- Customize how achievements are displayed in the UI
-------------------------------------------------------------------------------

-- Points name customization
Private.constants.DISPLAY.POINTS_NAME = "Marks of Reckoning"
Private.constants.DISPLAY.POINTS_NAME_SINGULAR = "Mark of Reckoning"

-------------------------------------------------------------------------------
-- Announcement Settings
-- Control how achievement completions are announced
-------------------------------------------------------------------------------

-- Show chat link when YOU earn an achievement (default: true)
-- Private.constants.ANNOUNCEMENTS.SHOW_PERSONAL_MESSAGE = true

-- Broadcast your achievements to guild members with the addon (default: true)
-- Private.constants.ANNOUNCEMENTS.BROADCAST_TO_GUILD = true

-- Send your achievements to guild chat (default: true)
-- Private.constants.ANNOUNCEMENTS.SEND_GUILD_CHAT = true

-- Show messages when guild members earn achievements (default: true)
-- Private.constants.ANNOUNCEMENTS.SHOW_GUILD_MESSAGES = true