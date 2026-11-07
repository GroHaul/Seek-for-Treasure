--!strict
--[[
	TelemetryService: AnalyticsService funnel and economy events (GDD §14).

	Onboarding funnel (once per player per session; Roblox counts each step once):
	  1 Loaded, 2 EnteredSearchZone, 3 FirstFind, 4 FirstRarePlus, 5 FirstPlaced,
	  6 FirstCollect, 7 FirstToolBought, 8 FirstPotion, 9 Session5Min, 10 Session10Min
	Economy ("Cash"): sources Collect / Offline / Sell / Code, sinks Tool / Potion /
	Slot / Segment / Rebirth. Collects and sells are summed per player and sent
	every 30 s, so standing on the pad doesn't spam the API.
	Custom: RareFind (Mythic+), PityTriggered, Mutation, Rebirth, IndexMilestone.
	Every call is pcall'd: analytics must never break gameplay.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)

local DataService = require(script.Parent.DataService)
local SearchService = require(script.Parent.SearchService)
local PlotService = require(script.Parent.PlotService)
local ShopService = require(script.Parent.ShopService)
local RebirthService = require(script.Parent.RebirthService)
local CodeService = require(script.Parent.CodeService)
local IndexService = require(script.Parent.IndexService)
local InventoryService = require(script.Parent.InventoryService)

local CURRENCY = "Cash"
local FLUSH_SECONDS = 30
local FUNNEL = {
	"Loaded",
	"EnteredSearchZone",
	"FirstFind",
	"FirstRarePlus",
	"FirstPlaced",
	"FirstCollect",
	"FirstToolBought",
	"FirstPotion",
	"Session5Min",
	"Session10Min",
}

local TelemetryService = {
	-- for tests: counts of events attempted this session by name
	counts = {} :: { [string]: number },
}

type Pending = { collect: number, sell: number }
local funnelDone: { [Player]: { [number]: boolean } } = {}
local pending: { [Player]: Pending } = {}

local function count(name: string)
	TelemetryService.counts[name] = (TelemetryService.counts[name] or 0) + 1
end

local function safe(name: string, fn: () -> ())
	count(name)
	local ok, err = pcall(fn :: any)
	if not ok then
		warn(`[Telemetry] {name} failed: {err}`)
	end
end

local function balance(player: Player): number
	local profile = DataService.getProfile(player)
	return if profile then profile.cash else 0
end

function TelemetryService.funnel(player: Player, step: number)
	local done = funnelDone[player]
	if done == nil or done[step] then
		return
	end
	done[step] = true
	safe("Funnel_" .. FUNNEL[step], function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, FUNNEL[step])
	end)
end

local function economy(player: Player, flow: Enum.AnalyticsEconomyFlowType, amount: number, transactionType: string, sku: string)
	if amount <= 0 then
		return
	end
	safe("Economy_" .. sku, function()
		AnalyticsService:LogEconomyEvent(player, flow, CURRENCY, amount, balance(player), transactionType, sku)
	end)
end

local function custom(player: Player, name: string, value: number?, fields: { [string]: any }?)
	safe("Custom_" .. name, function()
		AnalyticsService:LogCustomEvent(player, name, value, fields)
	end)
end

local function pendingFor(player: Player): Pending
	local p = pending[player]
	if p == nil then
		p = { collect = 0, sell = 0 }
		pending[player] = p
	end
	return p
end

local function flush(player: Player)
	local p = pending[player]
	if p == nil then
		return
	end
	pending[player] = nil
	economy(player, Enum.AnalyticsEconomyFlowType.Source, math.floor(p.collect), "Gameplay", "Collect")
	economy(player, Enum.AnalyticsEconomyFlowType.Source, math.floor(p.sell), "Gameplay", "Sell")
end

function TelemetryService.init() end

function TelemetryService.start()
	DataService.loaded:Connect(function(player)
		funnelDone[player] = {}
		TelemetryService.funnel(player, 1)
		task.delay(300, function()
			if player.Parent then
				TelemetryService.funnel(player, 9)
			end
		end)
		task.delay(600, function()
			if player.Parent then
				TelemetryService.funnel(player, 10)
			end
		end)
	end)
	DataService.releasing:Connect(function(player)
		flush(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		funnelDone[player] = nil
		pending[player] = nil
	end)

	SearchService.activeChanged:Connect(function(player, segmentId)
		if segmentId then
			TelemetryService.funnel(player, 2)
		end
	end)
	SearchService.found:Connect(function(player, info)
		TelemetryService.funnel(player, 3)
		if info.rarity >= 3 then
			TelemetryService.funnel(player, 4)
		end
		if info.rarity >= 6 then
			custom(player, "RareFind", info.rarity, { segment = info.segmentId, treasure = info.treasure.id })
		end
		if info.floor > 1 and info.rarity >= info.floor and info.searchNumber > 8 then
			custom(player, "PityTriggered", info.floor)
		end
		for _, id in info.mutation do
			local m = Catalog.mutationById[id]
			if m then
				custom(player, "Mutation", m.mult, { family = m.family, id = m.id })
			end
		end
	end)
	PlotService.placed:Connect(function(player)
		TelemetryService.funnel(player, 5)
	end)
	PlotService.collected:Connect(function(player, amount)
		TelemetryService.funnel(player, 6)
		pendingFor(player).collect += amount
	end)
	PlotService.offlineGranted:Connect(function(player, amount)
		economy(player, Enum.AnalyticsEconomyFlowType.Source, amount, "TimedReward", "Offline")
	end)
	InventoryService.removed:Connect(function(player, _, _, cash)
		pendingFor(player).sell += cash
	end)
	ShopService.purchased:Connect(function(player, sku, price)
		if string.sub(sku, 1, 5) == "Tool_" then
			TelemetryService.funnel(player, 7)
		elseif string.sub(sku, 1, 7) == "Potion_" then
			TelemetryService.funnel(player, 8)
		end
		economy(player, Enum.AnalyticsEconomyFlowType.Sink, price, "Shop", sku)
	end)
	RebirthService.reborn:Connect(function(player, rebirths, wiped)
		economy(player, Enum.AnalyticsEconomyFlowType.Sink, wiped, "Gameplay", "Rebirth_" .. rebirths)
		custom(player, "Rebirth", rebirths)
	end)
	CodeService.redeemed:Connect(function(player, code, reward)
		if reward.cash then
			economy(player, Enum.AnalyticsEconomyFlowType.Source, reward.cash, "TimedReward", "Code_" .. code)
		end
		custom(player, "CodeRedeemed", nil, { code = code })
	end)
	IndexService.milestone:Connect(function(player, segmentId, milestone)
		custom(player, "IndexMilestone", milestone, { segment = segmentId })
	end)

	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			for player in pending do
				flush(player)
			end
		end
	end)
end

return TelemetryService
