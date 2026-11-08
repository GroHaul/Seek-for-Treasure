--!strict
--[[
	Config/Mutations: GDD §3. Two independent families per find; at most one
	Finish and one Aura. mutationMultiplier = min(totalCap, finish.mult * aura.mult).
	Chance per family = baseChance * tool mutation stat * Mutation Potion, capped at chanceCap.
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Mutations: Types.MutationsConfig = {
	totalCap = 10,
	families = {
		{
			id = "finish",
			name = "Finish",
			baseChance = 0.04,
			chanceCap = 0.5,
			entries = {
				{
					id = "golden",
					name = "Golden",
					family = "finish",
					mult = 2,
					weight = 55,
					bit = 1,
					visual = { material = "Metal", color = "#FFC93C", reflectance = 0.3, particles = { preset = "sparkle_gold", rate = 4 } },
				},
				{
					id = "crystal",
					name = "Crystal",
					family = "finish",
					mult = 3,
					weight = 25,
					bit = 2,
					visual = { material = "Glass", color = "#9FF3FF", transparency = 0.25, particles = { preset = "glint_white", rate = 3 } },
				},
				{
					id = "rainbow",
					name = "Rainbow",
					family = "finish",
					mult = 5,
					weight = 12,
					bit = 4,
					visual = { material = "Neon", hueCycleSeconds = 6, trail = "rainbow" },
				},
				{
					id = "shadow",
					name = "Shadow",
					family = "finish",
					mult = 7,
					weight = 6,
					bit = 8,
					visual = { material = "SmoothPlastic", color = "#16121F", highlightColor = "#8E5CFF", particles = { preset = "smoke_dark", rate = 6 } },
				},
				{
					id = "prismatic",
					name = "Prismatic",
					family = "finish",
					mult = 10,
					weight = 2,
					bit = 16,
					visual = { material = "Glass", highlightHueCycle = true, beams = { preset = "light_rays", count = 4 } },
				},
			},
		},
		{
			id = "aura",
			name = "Aura",
			baseChance = 0.015,
			chanceCap = 0.5,
			entries = {
				{
					id = "glowing",
					name = "Glowing",
					family = "aura",
					mult = 1.5,
					weight = 50,
					bit = 32,
					visual = { lightRange = 8, particles = { preset = "halo_ring", rate = 2 } },
				},
				{
					id = "blazing",
					name = "Blazing",
					family = "aura",
					mult = 2,
					weight = 30,
					bit = 64,
					visual = { particles = { preset = "flame_orange", rate = 10, lifetime = 0.8 } },
				},
				{
					id = "electric",
					name = "Electric",
					family = "aura",
					mult = 2.5,
					weight = 15,
					bit = 128,
					visual = { particles = { preset = "spark_blue", rate = 6 }, beams = { preset = "arc_blue", count = 2 } },
				},
				{
					id = "starlit",
					name = "Starlit",
					family = "aura",
					mult = 3,
					weight = 5,
					bit = 256,
					visual = { particles = { preset = "star_orbit", rate = 5 } },
				},
			},
		},
	},
}

return DeepFreeze(Mutations)
