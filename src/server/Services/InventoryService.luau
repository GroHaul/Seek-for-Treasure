--!strict
--[[
	InventoryService: adds finds, sells items, enforces the 300-entry cap
	(GDD §11.2). Overflow: a find below Legendary is auto-sold; a Legendary+
	find sells the lowest-income unplaced item instead.
	Sell value = 10 s of the treasure's income before rebirth and boosts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Catalog = require(Shared.Catalog)
local EconomyMath = require(Shared.EconomyMath)
local Signal = require(Shared.Util.Signal)
local Economy = require(Shared.Config.Economy) :: Types.EconomyConfig

local StateService = require(script.Parent.StateService)

local InventoryService = {
	added = Signal.new() :: Signal.Signal<Player, string, Types.InventoryEntry>,
	removed = Signal.new() :: Signal.Signal<Player, string, Types.InventoryEntry, number>, -- uid, entry, cash gained
}

function InventoryService.count(profile: Types.Profile): number
	local n = 0
	for _ in profile.inventory do
		n += 1
	end
	return n
end

--- Slot key holding uid, or nil if the item isn't placed.
function InventoryService.placedSlot(profile: Types.Profile, uid: string): string?
	for slot, placedUid in profile.plot.layout do
		if placedUid == uid then
			return slot
		end
	end
	return nil
end

local function grantSale(player: Player, profile: Types.Profile, value: number)
	profile.cash += value
	profile.lifetimeEarned += value
	StateService.markDirty(player, "cash", "lifetimeEarned")
end

--- Removes an unplaced item and pays its sell value. Returns the cash paid, or nil.
function InventoryService.sell(player: Player, profile: Types.Profile, uid: string): number?
	local entry = profile.inventory[uid]
	if entry == nil or InventoryService.placedSlot(profile, uid) ~= nil then
		return nil
	end
	local value = EconomyMath.sellValue(entry)
	profile.inventory[uid] = nil
	grantSale(player, profile, value)
	StateService.invChanged(player, uid)
	InventoryService.removed:Fire(player, uid, entry, value)
	return value
end

local function lowestUnplaced(profile: Types.Profile): string?
	local placed: { [string]: boolean } = {}
	for _, uid in profile.plot.layout do
		placed[uid] = true
	end
	local bestUid: string? = nil
	local bestIncome = math.huge
	for uid, entry in profile.inventory do
		if not placed[uid] then
			local income = EconomyMath.treasureIncome(entry)
			if income < bestIncome then
				bestIncome = income
				bestUid = uid
			end
		end
	end
	return bestUid
end

--- Adds a find. Returns (uid, nil) when stored, or (nil, cashPaid) when auto-sold.
function InventoryService.add(player: Player, profile: Types.Profile, treasure: Types.Treasure, mutation: { string }): (string?, number?)
	local entry: Types.InventoryEntry = {
		id = treasure.id,
		segment = Catalog.treasureSegment[treasure.id],
		rarity = treasure.rarity,
		mutation = mutation,
		level = 1,
		t = os.time(),
	}
	if InventoryService.count(profile) >= Economy.inventoryCap then
		if treasure.rarity < Economy.autoSellBelowRarity then
			local value = EconomyMath.sellValue(entry)
			grantSale(player, profile, value)
			return nil, value
		end
		local victim = lowestUnplaced(profile)
		if victim then
			InventoryService.sell(player, profile, victim)
		end
	end
	local uid = "t" .. tostring(profile.nextUid)
	profile.nextUid += 1
	profile.inventory[uid] = entry
	StateService.invChanged(player, uid)
	InventoryService.added:Fire(player, uid, entry)
	return uid, nil
end

function InventoryService.init() end
function InventoryService.start() end

return InventoryService
