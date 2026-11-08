--!strict
--[[
	ShopController: the Shop panel (GDD §5) with Tools / Potions / Upgrades tabs.
	Prices shown here use the same shared formulas as the server, but the server
	recomputes and validates every purchase; buttons only send intents.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Config = Shared:WaitForChild("Config")
local Tools = require(Config:WaitForChild("Tools")) :: any
local Potions = require(Config:WaitForChild("Potions")) :: any
local Upgrades = require(Config:WaitForChild("Upgrades")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)

local C = Theme.colors
local SEGMENT = "pets"

local Shop = {}

local modal: Root.Modal
local list: ScrollingFrame
local tabButtons: { [string]: Kit.Button } = {}
local currentTab = "Tools"

local POTION_TEXT = {
	luck = "Luck x2 for 10 min",
	speed = "Search 1.5x faster for 10 min",
	mutation = "Mutation chance x2 for 10 min",
	cash = "Plot income x2 for 10 min",
}
local POTION_ICON = { luck = "potion_luck", speed = "potion_speed", mutation = "potion_mutation", cash = "potion_cash" }

local function row(order: number, iconName: string, titleText: string, subText: string): Frame
	local frame = Kit.panel({
		Name = "Row" .. order,
		Size = UDim2.new(1, -12, 0, 60),
		LayoutOrder = order,
		BackgroundColor3 = C.white,
		Parent = list,
	}, UDim.new(0, 12))
	local icon = Kit.icon(iconName, 36)
	icon.Position = UDim2.fromOffset(10, 11)
	icon.Parent = frame
	Kit.label(titleText, {
		Size = UDim2.new(1, -230, 0, 24),
		Position = UDim2.fromOffset(56, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	Kit.text(subText, {
		Size = UDim2.new(1, -230, 0, 18),
		Position = UDim2.fromOffset(56, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.fonts.body,
		TextColor3 = C.muted,
		Parent = frame,
	})
	return frame
end

local function rowButton(frame: Frame, text: string, kind: string, enabled: boolean, onActivated: () -> ())
	local button = Kit.button(text, kind, onActivated, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(160, 48),
	})
	button.setEnabled(enabled)
	button.instance.Parent = frame
end

local function renderTools(profile: any)
	local segment = Catalog.segmentById[SEGMENT]
	local tool = profile.tools[SEGMENT]
	local owned, equipped = tool.owned, tool.equipped
	for _, entry in segment.tools do
		local stats = Tools.tiers[entry.tier]
		local price = stats.basePrice * segment.toolPriceMult
		local sub = string.format("Every %.2fs · Luck x%.2f · Mutation x%.2f", stats.interval, stats.luck, stats.mutation)
		local frame = row(entry.tier, "tool", entry.name, sub)
		if entry.tier == equipped then
			rowButton(frame, "Equipped", "success", false, function() end)
		elseif entry.tier <= owned then
			rowButton(frame, "Equip", "secondary", true, function()
				Remotes.fire(Net.Shop_EquipTool, entry.id)
			end)
		elseif entry.tier == owned + 1 then
			rowButton(frame, "Buy " .. Format.cash(price), "primary", profile.cash >= price, function()
				Remotes.fire(Net.Shop_BuyTool, entry.id)
			end)
		else
			rowButton(frame, "🔒 " .. Format.cash(price), "neutral", false, function() end)
		end
	end
end

local function renderPotions(profile: any)
	local base = tonumber(State.derived.baseIncome) or 0
	local now = os.time()
	for i, potion in Potions.list do
		local price = EconomyMath.potionPrice(potion, base)
		local remaining = math.max(0, (tonumber(profile.potions[potion.id]) or 0) - now)
		local sub = (POTION_TEXT :: any)[potion.id] .. (if remaining > 0 then " · active " .. Format.duration(remaining) else "")
		local frame = row(i, (POTION_ICON :: any)[potion.id], potion.name, sub)
		local full = remaining + potion.durationSeconds > Potions.maxRemainingSeconds
		rowButton(frame, if full then "Max 60 min" else "Buy " .. Format.cash(price), "primary", not full and profile.cash >= price, function()
			Remotes.fire(Net.Shop_BuyPotion, potion.id)
		end)
	end
end

local function renderUpgrades(profile: any)
	local slots = profile.plot.slots
	local maxed = slots >= Upgrades.slots.max
	local price = EconomyMath.slotPrice(slots)
	local frame = row(1, "slot", string.format("Plot slots %d / %d", slots, Upgrades.slots.max), "One more pedestal for a treasure that earns cash")
	rowButton(frame, if maxed then "Maxed" else "Buy " .. Format.cash(price), "primary", not maxed and profile.cash >= price, function()
		Remotes.fire(Net.Shop_BuySlot)
	end)
end

local function render()
	if not Root.isOpen("Shop") or not State.loaded then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local profile = State.profile
	if currentTab == "Tools" then
		renderTools(profile)
	elseif currentTab == "Potions" then
		renderPotions(profile)
	else
		renderUpgrades(profile)
	end
	for name, button in tabButtons do
		button.setColor(if name == currentTab then C.sun else C.white)
	end
end
Shop.render = render

function Shop.init()
	modal = Root.modal("Shop", "Shop", Vector2.new(660, 430))
	local tabs = Kit.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 50),
		Parent = modal.content,
	}, { Kit.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left) })
	for i, name in { "Tools", "Potions", "Upgrades" } do
		local button = Kit.button(name, "neutral", function()
			currentTab = name
			render()
		end, { Size = UDim2.fromOffset(140, 48), LayoutOrder = i, Name = name })
		button.instance.Parent = tabs
		tabButtons[name] = button
	end
	list = Kit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.ink,
		Parent = modal.content,
	}, { Kit.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top), Kit.padding(4) })
	modal.onOpen = render
end

function Shop.start()
	State.watch({ "cash", "tools", "potions", "plot" }, render)
	State.watch({ "derived" }, function()
		if currentTab == "Potions" then
			render()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if currentTab == "Potions" then
				render()
			end
		end
	end)
end

return Shop
