--!strict
--[[
	Config/Segments/Pets: GDD §4.1 (segment row), §4.2 (treasure pool), §5.1 (Whistles).
	Original designs only. Adding a segment = a new module like this one + an area
	in Workspace.World.Segments with a SearchZone part (attribute SegmentId).
]]

local Types = require(script.Parent.Parent.Parent.Types)

local Pets: Types.Segment = {
	id = "pets",
	name = "Pets",
	area = "Pawprint Meadow",
	theme = "Sunny rolling meadow with giant flower bushes, hollow logs, picket fences and a pet-bowl fountain.",
	order = 1,
	unlockCost = 0,
	incomeMult = 1,
	toolPriceMult = 1,
	toolLine = "Whistles",
	tools = {
		{ tier = 1, id = "pets_t1", name = "Tin Whistle" },
		{ tier = 2, id = "pets_t2", name = "Wooden Whistle" },
		{ tier = 3, id = "pets_t3", name = "Brass Whistle" },
		{ tier = 4, id = "pets_t4", name = "Silver Whistle" },
		{ tier = 5, id = "pets_t5", name = "Amber Whistle" },
		{ tier = 6, id = "pets_t6", name = "Opal Whistle" },
		{ tier = 7, id = "pets_t7", name = "Starlight Whistle" },
		{ tier = 8, id = "pets_t8", name = "Aurora Whistle" },
	},
	treasures = {
		{
			id = "pets_dust_bunny",
			name = "Dust Bunny",
			rarity = 1,
			weight = 1,
			model = "DustBunny",
			description = "Fluffy grey bunny shaped like a puff of dust, button nose, tiny stub feet",
		},
		{
			id = "pets_pebble_pup",
			name = "Pebble Pup",
			rarity = 1,
			weight = 1,
			model = "PebblePup",
			description = "Round puppy with a smooth river-stone spotted coat and floppy ears",
		},
		{
			id = "pets_sprout_kitten",
			name = "Sprout Kitten",
			rarity = 2,
			weight = 1,
			model = "SproutKitten",
			description = "Green-tabby kitten with a two-leaf sprout growing from its head",
		},
		{
			id = "pets_puddle_duckling",
			name = "Puddle Duckling",
			rarity = 2,
			weight = 1,
			model = "PuddleDuckling",
			description = "Yellow duckling with a tiny rain cloud hovering above, dripping on it",
		},
		{
			id = "pets_toasty_corgi",
			name = "Toasty Corgi",
			rarity = 3,
			weight = 1,
			model = "ToastyCorgi",
			description = "Corgi whose body is a golden loaf of toast with a butter-pat saddle",
		},
		{
			id = "pets_ember_fox",
			name = "Ember Fox",
			rarity = 4,
			weight = 1,
			model = "EmberFox",
			description = "Orange fox with a faceted low-poly flame tail and ash-grey paws",
		},
		{
			id = "pets_storm_pony",
			name = "Storm Pony",
			rarity = 5,
			weight = 1,
			model = "StormPony",
			description = "Chubby pony with a thundercloud mane and lightning-bolt hooves",
		},
		{
			id = "pets_crystal_dragonling",
			name = "Crystal Dragonling",
			rarity = 6,
			weight = 1,
			model = "CrystalDragonling",
			description = "Baby dragon with faceted gem spines and stubby translucent wings",
		},
		{
			id = "pets_halo_owl",
			name = "Halo Owl",
			rarity = 7,
			weight = 1,
			model = "HaloOwl",
			description = "Snow-white owl with a floating golden halo and light-feather wing tips",
		},
		{
			id = "pets_starlight_stag",
			name = "Starlight Stag",
			rarity = 8,
			weight = 1,
			model = "StarlightStag",
			description = "Midnight-blue fawn with constellation-dot antlers that glow",
		},
		{
			id = "pets_galaxy_axolotl",
			name = "Galaxy Axolotl",
			rarity = 9,
			weight = 1,
			model = "GalaxyAxolotl",
			description = "Axolotl with swirling purple-pink galaxy skin and star-tipped gills",
		},
		{
			id = "pets_eclipse_griffin",
			name = "Eclipse Griffin",
			rarity = 10,
			weight = 1,
			model = "EclipseGriffin",
			description = "Small griffin, half sun-gold and half night-violet feathers, an eclipse ring behind its head",
		},
	},
}

return Pets
