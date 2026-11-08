--!strict
--[[
	ProfileTemplate: a fresh profile (GDD §11.1). new() returns a brand-new
	table every call, so players never share nested tables.
	Schema 2 (2026-11-08) adds diamonds, upgrades, potionBag, potionStock and the
	Diamond Potion timer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = Shared.Config
local Economy = require(Config.Economy) :: Types.EconomyConfig
local Upgrades = require(Config.Upgrades) :: Types.UpgradesConfig
local Segments = require(Config.Segments) :: { Types.Segment }

local CURRENT_SCHEMA = 2

local ProfileTemplate = {
	CURRENT_SCHEMA = CURRENT_SCHEMA,
}

function ProfileTemplate.new(): Types.Profile
	local tools: { [string]: { owned: number, equipped: number } } = {}
	local segments: { [string]: boolean } = {}
	for _, segment in Segments do
		tools[segment.id] = { owned = 1, equipped = 1 }
		segments[segment.id] = segment.unlockCost == 0
	end
	return {
		schema = CURRENT_SCHEMA,
		cash = Economy.startingCash,
		vault = 0,
		lifetimeEarned = 0,
		rebirths = 0,
		inventory = {},
		nextUid = 1,
		plot = { slots = Upgrades.slots.start, layout = {} },
		tools = tools,
		segments = segments,
		potions = { luck = 0, speed = 0, mutation = 0, cash = 0, diamond = 0 },
		potionBag = {},
		potionStock = { cycle = 0, bought = {} },
		diamonds = 0,
		upgrades = {},
		pity = { epic = 0, legendary = 0, mythic = 0 },
		index = {},
		indexRewards = {},
		codes = {},
		streak = { day = 0, lastDay = 0 },
		stats = { searches = 0, playtime = 0, rarest = nil },
		purchases = {},
		settings = { reduceShake = false, music = true, sfx = true },
		flags = { tutorialDone = false },
		lastOnline = 0,
	}
end

return table.freeze(ProfileTemplate)
