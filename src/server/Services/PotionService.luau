--!strict
--[[
	PotionService: Luck, Speed, Mutation and Cash potions (GDD §5.2).

	Price = max(minPrice, priceSeconds x base plot income), computed on the server
	from the placed treasures and rebirths only, so boosts can't make potions cheaper.
	Expiry is a wall-clock unix time: buying the same type adds 10 min to the
	remaining time, up to 60 min remaining. A purchase that would go past the cap
	is refused (no charge). Different types multiply each other.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Catalog = require(Shared.Catalog)
local EconomyMath = require(Shared.EconomyMath)
local PotionsConfig = require(Shared.Config.Potions) :: Types.PotionsConfig

local RemoteService = require(script.Parent.RemoteService)
local StateService = require(script.Parent.StateService)
local PlotService = require(script.Parent.PlotService)
local ShopService = require(script.Parent.ShopService)
local Guard = require(script.Parent.Parent.Util.Guard)

local PotionService = {}

function PotionService.price(profile: Types.Profile, potionId: string): number?
	local potion = Catalog.potionById[potionId]
	if potion == nil then
		return nil
	end
	return EconomyMath.potionPrice(potion, PlotService.basePlotIncome(profile))
end

--- Seconds of potion `potionId` still active at `now`.
function PotionService.remaining(profile: Types.Profile, potionId: string, now: number): number
	local expiry = (profile.potions :: any)[potionId]
	return if type(expiry) == "number" then math.max(0, expiry - now) else 0
end

--- Adds `count` doses (each durationSeconds). With clamp = false, refuses if the
--- result would exceed the 60-minute cap; with clamp = true, extra time is dropped.
function PotionService.add(player: Player, profile: Types.Profile, potionId: string, count: number, clamp: boolean): boolean
	local potion = Catalog.potionById[potionId]
	if potion == nil or count < 1 then
		return false
	end
	local now = os.time()
	local remaining = PotionService.remaining(profile, potionId, now) + potion.durationSeconds * count
	if remaining > PotionsConfig.maxRemainingSeconds then
		if not clamp then
			return false
		end
		remaining = PotionsConfig.maxRemainingSeconds
	end
	(profile.potions :: any)[potionId] = now + remaining
	StateService.markDirty(player, "potions")
	return true
end

function PotionService.buy(player: Player, profile: Types.Profile, potionId: string): boolean
	local price = PotionService.price(profile, potionId)
	if price == nil then
		return false
	end
	local potion = Catalog.potionById[potionId]
	if PotionService.remaining(profile, potionId, os.time()) + potion.durationSeconds > PotionsConfig.maxRemainingSeconds then
		ShopService.notify(player, "potion_max", { potionId = potionId })
		return false
	end
	if not ShopService.spend(player, profile, price) then
		ShopService.notify(player, "cant_afford", { price = price })
		return false
	end
	PotionService.add(player, profile, potionId, 1, false)
	ShopService.purchased:Fire(player, "Potion_" .. potionId, price)
	return true
end

function PotionService.init() end

function PotionService.start()
	RemoteService.on(Net.Shop_BuyPotion, 2, 4, function(player, profile, potionArg)
		local potionId = Guard.oneOf(potionArg, Catalog.potionById, 16)
		if potionId then
			PotionService.buy(player, profile, potionId)
		end
	end)
end

return PotionService
