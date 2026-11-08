--!strict
--[[
	RebirthService (GDD §7).

	Cost: $400M x 12^R while the build has one segment ($2.5B x 12^R after that).
	Resets: cash, vault, tools (back to T1), segment unlocks, plot slots (back to 6).
	Keeps: every treasure (decision 2026-11-04), Index, pity, potions, codes,
	streak, stats. Slots 7+ empty out; Place Best then fills slots 1-6.
	Reward: +50% cash and +10% luck per rebirth (applied by EconomyMath).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Catalog = require(Shared.Catalog)
local EconomyMath = require(Shared.EconomyMath)
local Signal = require(Shared.Util.Signal)
local Config = Shared.Config
local Economy = require(Config.Economy) :: Types.EconomyConfig
local Upgrades = require(Config.Upgrades) :: Types.UpgradesConfig

local RemoteService = require(script.Parent.RemoteService)
local StateService = require(script.Parent.StateService)
local PlotService = require(script.Parent.PlotService)

local RebirthService = {
	-- (player, newRebirthCount, cashWiped)
	reborn = Signal.new() :: Signal.Signal<Player, number, number>,
}

function RebirthService.cost(profile: Types.Profile): number
	return EconomyMath.rebirthCost(profile.rebirths, #Catalog.segments)
end

function RebirthService.rebirth(player: Player, profile: Types.Profile): boolean
	local cost = RebirthService.cost(profile)
	if not EconomyMath.isFinite(cost) or profile.cash < cost then
		return false
	end
	local wiped = profile.cash
	profile.rebirths += 1
	profile.cash = Economy.startingCash
	profile.vault = 0
	for segmentId, tool in profile.tools do
		tool.owned = 1
		tool.equipped = 1
		profile.tools[segmentId] = tool
	end
	for _, segment in Catalog.segments do
		profile.segments[segment.id] = segment.unlockCost == 0
	end
	profile.plot.slots = Upgrades.slots.start
	PlotService.placeBest(player, profile) -- slots 7+ empty out, best 6 placed
	StateService.markDirty(player, "rebirths", "cash", "vault", "tools", "segments", "plot")
	RemoteService.fire(Net.Notify, player, { kind = "rebirth", count = profile.rebirths })
	RebirthService.reborn:Fire(player, profile.rebirths, wiped)
	return true
end

function RebirthService.init() end

function RebirthService.start()
	RemoteService.on(Net.Rebirth_Request, 0.5, 1, function(player, profile)
		RebirthService.rebirth(player, profile)
	end)
end

return RebirthService
