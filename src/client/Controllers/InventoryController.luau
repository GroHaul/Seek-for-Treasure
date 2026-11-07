--!strict
--[[
	InventoryController: the Bag panel. Treasures sorted by income, a card per
	treasure (rarity-colored frame, mutation badges, $/s, "On plot #n" tag),
	and Place / Remove / Sell for the selected card, plus Place Best.
	Selling Legendary+ needs a second tap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)

local C = Theme.colors
local CONFIRM_SELL_FROM = 5 -- Legendary+

local Inventory = {}

local modal: Root.Modal
local grid: ScrollingFrame
local countText: TextLabel
local detailText: TextLabel
local placeButton: Kit.Button
local removeButton: Kit.Button
local sellButton: Kit.Button
local selected: string? = nil
local sellArmed: string? = nil
local dirty = false

type Item = { uid: string, entry: any, income: number, slot: number? }

local function sortedItems(profile: any): { Item }
	local slotOf: { [string]: number } = {}
	for slot, uid in profile.plot.layout do
		slotOf[uid] = tonumber(slot) or 0
	end
	local items: { Item } = {}
	for uid, entry in profile.inventory do
		table.insert(items, { uid = uid, entry = entry, income = EconomyMath.treasureIncome(entry), slot = slotOf[uid] })
	end
	table.sort(items, function(a, b)
		if a.income ~= b.income then
			return a.income > b.income
		end
		return a.uid < b.uid
	end)
	return items
end

local function mutationText(mutation: { string }): string
	local names = {}
	for _, id in mutation do
		local m = Catalog.mutationById[id]
		if m then
			table.insert(names, m.name)
		end
	end
	return table.concat(names, " · ")
end

local function lowestPlacedSlot(profile: any): number?
	local worstSlot, worstIncome = nil, math.huge
	for slot, uid in profile.plot.layout do
		local entry = profile.inventory[uid]
		local income = if entry then EconomyMath.treasureIncome(entry) else 0
		if income < worstIncome then
			worstSlot, worstIncome = tonumber(slot), income
		end
	end
	return worstSlot
end

local function targetSlot(profile: any): number?
	for slot = 1, profile.plot.slots do
		if profile.plot.layout[tostring(slot)] == nil then
			return slot
		end
	end
	return lowestPlacedSlot(profile)
end

local function refreshDetail()
	local profile = State.profile
	local entry = if selected then profile.inventory[selected] else nil
	if entry == nil then
		selected = nil
		detailText.Text = "Tap a treasure to place, remove or sell it"
		placeButton.setEnabled(false)
		removeButton.setEnabled(false)
		sellButton.setEnabled(false)
		sellButton.setText("Sell")
		return
	end
	local treasure = Catalog.treasureById[entry.id]
	local rarity = Catalog.rarities[entry.rarity]
	local placed = false
	for _, uid in profile.plot.layout do
		if uid == selected then
			placed = true
		end
	end
	local mut = mutationText(entry.mutation)
	detailText.Text = string.format(
		'%s <font color="#%s">[%s]</font>%s · %s/s',
		if treasure then treasure.name else entry.id,
		Kit.readable(Color3.fromHex(rarity.color)):ToHex(),
		rarity.name,
		if mut ~= "" then " · " .. mut else "",
		Format.cash(EconomyMath.treasureIncome(entry) * EconomyMath.rebirthCashMult(profile.rebirths))
	)
	placeButton.setEnabled(not placed)
	removeButton.setEnabled(placed)
	sellButton.setEnabled(not placed)
	local value = EconomyMath.sellValue(entry)
	sellButton.setText(if sellArmed == selected then "Tap to confirm" else "Sell " .. Format.cash(value))
end

local function card(item: Item, order: number, rebirthMult: number)
	local entry = item.entry
	local rarity = Catalog.rarities[entry.rarity]
	local treasure = Catalog.treasureById[entry.id]
	local color = Color3.fromHex(rarity.color)
	local button = Kit.new("TextButton", {
		Name = item.uid,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = if item.uid == selected then C.sun else C.white,
		LayoutOrder = order,
	}, { Kit.corner(UDim.new(0, 14)) }) :: TextButton
	Kit.rarityStroke(button, color, entry.rarity)
	local orb = Kit.new("Frame", {
		Name = "Model",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = color,
		Parent = button,
	}, { Kit.corner(UDim.new(0.5, 0)), Kit.stroke(C.ink, 2) })
	for _, id in entry.mutation do
		local m = Catalog.mutationById[id]
		if m and m.visual.color then
			orb.BackgroundColor3 = Color3.fromHex(m.visual.color)
		end
	end
	Kit.text(if treasure then treasure.name else entry.id, { Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 56), Parent = button })
	Kit.text(rarity.name, {
		Size = UDim2.new(1, -8, 0, 14),
		Position = UDim2.fromOffset(4, 74),
		TextColor3 = Kit.readable(color),
		Parent = button,
	})
	local mut = mutationText(entry.mutation)
	if mut ~= "" then
		Kit.text(
			mut,
			{ Size = UDim2.new(1, -8, 0, 12), Position = UDim2.fromOffset(4, 89), TextColor3 = C.grape, FontFace = Theme.fonts.body, Parent = button }
		)
	end
	Kit.text(Format.cash(item.income * rebirthMult) .. "/s", {
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.fromOffset(4, 104),
		FontFace = Theme.fonts.number,
		TextColor3 = C.cash,
		TextStrokeColor3 = C.ink,
		TextStrokeTransparency = 0.3,
		Parent = button,
	})
	if item.slot then
		Kit.text(
			"📍" .. item.slot,
			{ Size = UDim2.fromOffset(36, 16), Position = UDim2.fromOffset(4, 4), TextXAlignment = Enum.TextXAlignment.Left, Parent = button }
		)
	end
	button.Activated:Connect(function()
		-- highlight in place; no full rebuild needed for a selection change
		for _, other in grid:GetChildren() do
			if other:IsA("TextButton") then
				other.BackgroundColor3 = if other == button then C.sun else C.white
			end
		end
		selected = item.uid
		sellArmed = nil
		refreshDetail()
	end)
	button.Parent = grid
end

local function render()
	dirty = false
	if not Root.isOpen("Bag") or not State.loaded then
		return
	end
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local profile = State.profile
	local items = sortedItems(profile)
	countText.Text = string.format(
		"%d / %d treasures · %d / %d on your plot",
		#items,
		Economy.inventoryCap,
		(function()
			local n = 0
			for _ in profile.plot.layout do
				n += 1
			end
			return n
		end)(),
		profile.plot.slots
	)
	local mult = EconomyMath.rebirthCashMult(profile.rebirths)
	for i, item in items do
		card(item, i, mult)
	end
	refreshDetail()
end

function Inventory.init()
	modal = Root.modal("Bag", "Bag", Vector2.new(760, 450))
	local content = modal.content
	countText = Kit.text("", {
		Size = UDim2.new(1, -180, 0, 26),
		Position = UDim2.fromOffset(0, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})
	local best = Kit.button("Place Best", "secondary", function()
		Remotes.fire(Net.Plot_PlaceBest)
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(170, 48) })
	best.instance.Parent = content
	grid = Kit.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 1, -116),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.ink,
		Parent = content,
	}, {
		Kit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(112, 126),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Kit.padding(6),
	}) :: ScrollingFrame
	local footer = Kit.new("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 58),
		Parent = content,
	})
	detailText = Kit.text("", {
		Size = UDim2.new(1, -420, 1, -8),
		Position = UDim2.fromOffset(0, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = footer,
	})
	placeButton = Kit.button("Place", "primary", function()
		local profile = State.profile
		local slot = targetSlot(profile)
		if selected and slot then
			Remotes.fire(Net.Plot_Place, slot, selected)
		end
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -276, 0.5, 0), Size = UDim2.fromOffset(128, 48) })
	removeButton = Kit.button("Remove", "secondary", function()
		local profile = State.profile
		for slot, uid in profile.plot.layout do
			if uid == selected then
				Remotes.fire(Net.Plot_Remove, tonumber(slot))
			end
		end
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -140, 0.5, 0), Size = UDim2.fromOffset(128, 48) })
	sellButton = Kit.button("Sell", "danger", function()
		local uid = selected
		if uid == nil then
			return
		end
		local entry = State.profile.inventory[uid]
		if entry and entry.rarity >= CONFIRM_SELL_FROM and sellArmed ~= uid then
			sellArmed = uid
			refreshDetail()
			return
		end
		sellArmed = nil
		Remotes.fire(Net.Inv_Sell, uid)
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(132, 48) })
	placeButton.instance.Parent = footer
	removeButton.instance.Parent = footer
	sellButton.instance.Parent = footer
	modal.onOpen = render
	modal.onClose = function()
		selected = nil
		sellArmed = nil
	end
end

function Inventory.start()
	State.watch({ "inventory", "plot", "rebirths" }, function()
		dirty = true
	end)
	-- rebuild at most twice a second while the bag is open
	task.spawn(function()
		while true do
			task.wait(0.5)
			if dirty then
				render()
			end
		end
	end)
end

return Inventory
