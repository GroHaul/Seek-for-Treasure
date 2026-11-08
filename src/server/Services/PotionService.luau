--!strict
--[[
	PotionService: potions (GDD §5.2, §15.3).

	Buying (Shop_BuyPotion, at the Potions stall): only potions in the current
	restock's stock (StockMath, same for the whole server), at most `stock`
	of each per player per restock. Price = max(minPrice, priceSeconds x base plot
	income), computed here. The potion goes into the player's bag.

	Drinking (Potion_Use, from the hotbar): takes one from the bag and adds its
	duration to that potion's timer. Expiry is a wall-clock unix time; a drink
	that would go past 60 min remaining is refused and the potion stays in the bag.
	Different types multiply each other.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Catalog = require(Shared.Catalog)
local EconomyMath = require(Shared.EconomyMath)
local StockMath = require(Shared.StockMath)
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

--- Adds `count` doses of active time (each durationSeconds). With clamp = false,
--- refuses if the result would exceed the 60-minute cap; with clamp = true, extra
--- time is dropped.
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

--- Puts `count` potions into the bag (codes, Robux packs). Extra above the bag limit is dropped.
function PotionService.give(player: Player, profile: Types.Profile, potionId: string, count: number): number
	if Catalog.potionById[potionId] == nil or count < 1 then
		return 0
	end
	local held = profile.potionBag[potionId] or 0
	local added = math.clamp(math.floor(count), 0, PotionsConfig.bagMax - held)
	profile.potionBag[potionId] = held + added
	StateService.markDirty(player, "potionBag")
	return added
end

--- This restock's purchases for the player (resets when the window changes).
local function boughtThisRestock(profile: Types.Profile, cycle: number): { [string]: number }
	if profile.potionStock.cycle ~= cycle then
		profile.potionStock = { cycle = cycle, bought = {} }
	end
	return profile.potionStock.bought
end

--- Stall purchase: in stock, under the player's limit for this restock, affordable.
function PotionService.buy(player: Player, profile: Types.Profile, potionId: string): boolean
	local price = PotionService.price(profile, potionId)
	if price == nil then
		return false
	end
	local cycle = StockMath.cycle(os.time())
	local stock = StockMath.stock(cycle)[potionId] or 0
	local bought = boughtThisRestock(profile, cycle)
	if (bought[potionId] or 0) >= stock then
		ShopService.notify(player, "sold_out", { potionId = potionId })
		return false
	end
	if (profile.potionBag[potionId] or 0) >= PotionsConfig.bagMax then
		ShopService.notify(player, "bag_full", { potionId = potionId })
		return false
	end
	if not ShopService.spend(player, profile, price) then
		ShopService.notify(player, "cant_afford", { price = price })
		return false
	end
	bought[potionId] = (bought[potionId] or 0) + 1
	PotionService.give(player, profile, potionId, 1)
	StateService.markDirty(player, "potionStock")
	ShopService.purchased:Fire(player, "Potion_" .. potionId, price)
	ShopService.notify(player, "bought_potion", { potionId = potionId })
	return true
end

--- Drink one potion from the bag.
function PotionService.use(player: Player, profile: Types.Profile, potionId: string): boolean
	local held = profile.potionBag[potionId] or 0
	if held < 1 then
		return false
	end
	local potion = Catalog.potionById[potionId]
	if PotionService.remaining(profile, potionId, os.time()) + potion.durationSeconds > PotionsConfig.maxRemainingSeconds then
		ShopService.notify(player, "potion_max", { potionId = potionId })
		return false
	end
	profile.potionBag[potionId] = held - 1
	StateService.markDirty(player, "potionBag")
	PotionService.add(player, profile, potionId, 1, false)
	ShopService.notify(player, "potion_used", { potionId = potionId })
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
	RemoteService.on(Net.Potion_Use, 3, 5, function(player, profile, potionArg)
		local potionId = Guard.oneOf(potionArg, Catalog.potionById, 16)
		if potionId then
			PotionService.use(player, profile, potionId)
		end
	end)
end

return PotionService
