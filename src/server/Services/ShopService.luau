--!strict
--[[
	ShopService: tools, plot slots, segment unlocks (GDD §5.1, §5.4, §4.1).
	Every price is computed here from Config; the client only names what it wants.

	Shop_BuyTool(toolId)     exactly the next tier of an unlocked segment's line
	Shop_EquipTool(toolId)   any owned tier (cosmetic; stats use the highest owned)
	Shop_BuySlot()           next slot, 6 -> 20 (24 with the +4 Plot Slots pass), price 1,000 x 2.25^n
	These are sold at the Tools and Upgrades stalls; the Shop menu is Robux-only.
	Segment_Unlock(segId)    exactly the next locked segment in order
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Catalog = require(Shared.Catalog)
local EconomyMath = require(Shared.EconomyMath)
local Boosts = require(Shared.Boosts)
local Signal = require(Shared.Util.Signal)
local Upgrades = require(Shared.Config.Upgrades) :: Types.UpgradesConfig

local RemoteService = require(script.Parent.RemoteService)
local StateService = require(script.Parent.StateService)
local PlotService = require(script.Parent.PlotService)
local Guard = require(script.Parent.Parent.Util.Guard)

local ShopService = {
	-- (player, sku, price) for every successful cash purchase
	purchased = Signal.new() :: Signal.Signal<Player, string, number>,
}

--- Spend cash if affordable. Returns false (and spends nothing) otherwise.
function ShopService.spend(player: Player, profile: Types.Profile, price: number): boolean
	if not EconomyMath.isFinite(price) or price < 0 or profile.cash < price then
		return false
	end
	profile.cash -= price
	StateService.markDirty(player, "cash")
	return true
end

local function notify(player: Player, kind: string, data: { [string]: any }?)
	local payload: { [string]: any } = if data then data else {}
	payload.kind = kind
	RemoteService.fire(Net.Notify, player, payload)
end
ShopService.notify = notify

function ShopService.buyTool(player: Player, profile: Types.Profile, toolId: string): boolean
	local tool = Catalog.toolById[toolId]
	if tool == nil or profile.segments[tool.segmentId] ~= true then
		return false
	end
	local owned = profile.tools[tool.segmentId]
	if owned == nil or tool.tier ~= owned.owned + 1 then
		return false
	end
	if not ShopService.spend(player, profile, tool.price) then
		notify(player, "cant_afford", { price = tool.price })
		return false
	end
	owned.owned = tool.tier
	owned.equipped = tool.tier
	StateService.markDirty(player, "tools")
	ShopService.purchased:Fire(player, "Tool_" .. tool.id, tool.price)
	notify(player, "bought_tool", { toolId = tool.id })
	return true
end

function ShopService.equipTool(player: Player, profile: Types.Profile, toolId: string): boolean
	local tool = Catalog.toolById[toolId]
	local owned = if tool then profile.tools[tool.segmentId] else nil
	if tool == nil or owned == nil or tool.tier > owned.owned then
		return false
	end
	owned.equipped = tool.tier
	StateService.markDirty(player, "tools")
	return true
end

--- Most slots this player can unlock: 20, or 24 with the +4 Plot Slots pass.
function ShopService.maxSlots(player: Player): number
	return Upgrades.slots.max + (if Boosts.hasPass(player, "plotSlots") then Upgrades.slots.passExtra else 0)
end

function ShopService.buySlot(player: Player, profile: Types.Profile): boolean
	local slots = profile.plot.slots
	if slots >= ShopService.maxSlots(player) then
		return false
	end
	local price = EconomyMath.slotPrice(slots)
	if not ShopService.spend(player, profile, price) then
		notify(player, "cant_afford", { price = price })
		return false
	end
	profile.plot.slots = slots + 1
	PlotService.fillEmptySlots(player, profile)
	ShopService.purchased:Fire(player, "Slot_" .. tostring(slots + 1), price)
	return true
end

function ShopService.unlockSegment(player: Player, profile: Types.Profile, segmentId: string): boolean
	-- the next segment is the first one (in order) that isn't unlocked yet
	local nextSegment: Types.Segment? = nil
	for _, segment in Catalog.segments do
		if profile.segments[segment.id] ~= true then
			nextSegment = segment
			break
		end
	end
	if nextSegment == nil or nextSegment.id ~= segmentId then
		return false
	end
	if not ShopService.spend(player, profile, nextSegment.unlockCost) then
		notify(player, "cant_afford", { price = nextSegment.unlockCost })
		return false
	end
	profile.segments[segmentId] = true
	StateService.markDirty(player, "segments")
	ShopService.purchased:Fire(player, "Segment_" .. segmentId, nextSegment.unlockCost)
	return true
end

function ShopService.init() end

function ShopService.start()
	RemoteService.on(Net.Shop_BuyTool, 2, 4, function(player, profile, toolArg)
		local toolId = Guard.oneOf(toolArg, Catalog.toolById, 32)
		if toolId then
			ShopService.buyTool(player, profile, toolId)
		end
	end)
	RemoteService.on(Net.Shop_EquipTool, 2, 4, function(player, profile, toolArg)
		local toolId = Guard.oneOf(toolArg, Catalog.toolById, 32)
		if toolId then
			ShopService.equipTool(player, profile, toolId)
		end
	end)
	RemoteService.on(Net.Shop_BuySlot, 2, 4, function(player, profile)
		ShopService.buySlot(player, profile)
	end)
	RemoteService.on(Net.Segment_Unlock, 1, 2, function(player, profile, segmentArg)
		local segmentId = Guard.oneOf(segmentArg, Catalog.segmentById, 32)
		if segmentId then
			ShopService.unlockSegment(player, profile, segmentId)
		end
	end)
end

return ShopService
